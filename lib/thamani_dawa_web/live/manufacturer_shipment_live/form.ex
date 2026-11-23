defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Form do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Distributor.Shipment
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    origins = GlnLookup.search_origin(organization_id, "", 500)
    shipment = %Shipment{origin_gln: default_origin_gln(origins, socket)}

    {:ok,
     socket
     |> assign(:page_title, "New shipment")
     |> assign(:shipment, shipment)
     |> assign(:origins, origins)
     |> assign(:destination_check, :idle)
     |> assign(:transfer_mode, false)
     |> assign(:form, to_form(Distributor.change_shipment(shipment), as: :shipment))}
  end

  def handle_event("toggle_transfer_mode", _params, socket),
    do: {:noreply, update(socket, :transfer_mode, &(!&1))}

  def handle_event("validate", %{"shipment" => attrs} = params, socket) do
    changeset =
      socket.assigns.shipment
      |> Distributor.change_shipment(attrs)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form, to_form(changeset, as: :shipment))
      |> maybe_check_destination(params, attrs)

    {:noreply, socket}
  end

  def handle_event("save", %{"shipment" => attrs}, socket) do
    scope = socket.assigns.current_scope

    case Distributor.create_shipment(scope.organization_id, scope.user, attrs, "manufacturer") do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shipment saved and ready for review.")
         |> push_navigate(to: ~p"/manufacturer/shipments/#{shipment.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :shipment))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Shipment could not be created.")}
    end
  end

  defp default_origin_gln(origins, socket) do
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)
    Enum.find_value(origins, fn site -> site.id == site_id && site.gln end)
  end

  defp selected(records, gln), do: Enum.find(records, &(&1.gln == gln))

  defp destination_record({:matched, company, address}, gln),
    do: %{name: company, address: address, gln: gln}

  defp destination_record(_, _), do: nil

  defp maybe_check_destination(socket, params, attrs) do
    if Map.get(params, "_target") == ["shipment", "destination_gln"],
      do: check_destination_gln(socket, attrs),
      else: socket
  end

  defp check_destination_gln(socket, attrs) do
    gln = attrs |> Map.get("destination_gln", "") |> to_string() |> String.trim()

    if Regex.match?(~r/^\d{13}$/, gln),
      do:
        socket
        |> assign(:destination_check, :checking)
        |> start_async(:destination_lookup, fn -> GlnLookup.resolve_party(gln) end),
      else: assign(socket, :destination_check, :idle)
  end

  def handle_async(:destination_lookup, {:ok, {:ok, party}}, socket),
    do: {:noreply, assign(socket, :destination_check, {:matched, party.company, party.address})}

  def handle_async(:destination_lookup, {:ok, {:error, :not_found}}, socket),
    do: {:noreply, assign(socket, :destination_check, :not_found)}

  def handle_async(:destination_lookup, {:exit, _}, socket),
    do: {:noreply, assign(socket, :destination_check, :unavailable)}

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
      crumb="Shipments"
    >
      <.td_page_header
        title="New shipment"
        subtitle="The mobile team finds this shipment by its order number, then scans units into shippers."
      />

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <section class="rounded-2xl ff-surface-card p-5 sm:p-6">
          <.form
            for={@form}
            id="manufacturer-shipment-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-6"
          >
            <.td_input
              field={@form[:order_number]}
              label="Order number"
              placeholder="e.g. MO-2026-0142"
              required
            />
            <div class="space-y-3 border-t border-thamani-stone pt-5">
              <.td_select
                field={@form[:origin_gln]}
                label="Origin (ship from)"
                prompt="Choose one of your sites"
                options={Enum.map(@origins, &{"#{&1.name} · #{&1.gln}", &1.gln})}
                required
              />
            </div>
            <div class="space-y-3 border-t border-thamani-stone pt-5">
              <p class="td-note">Destination</p>
              <.td_switch
                id="manufacturer-shipment-transfer"
                on={@transfer_mode}
                label="Destination is one of your sites"
                phx-click="toggle_transfer_mode"
              />
              <.td_select
                :if={@transfer_mode}
                field={@form[:destination_gln]}
                label="Destination site"
                prompt="Choose one of your sites"
                options={Enum.map(@origins, &{"#{&1.name} · #{&1.gln}", &1.gln})}
                required
              />
              <.td_input
                :if={!@transfer_mode}
                field={@form[:destination_gln]}
                label="Destination GLN (ship to)"
                placeholder="13-digit GLN of the receiving party"
                inputmode="numeric"
                phx-debounce="500"
                required
              />
              <p :if={@destination_check == :checking} class="text-xs text-thamani-pewter">
                <.icon name="hero-arrow-path" class="inline size-3.5 motion-safe:animate-spin" />
                Verifying…
              </p>
              <p
                :if={match?({:matched, _, _}, @destination_check)}
                class="rounded-lg bg-td-accent-tint px-3 py-2 text-xs font-semibold text-thamani-forest"
              >
                <.icon name="hero-check-circle" class="inline size-4" /> Verified
              </p>
              <p
                :if={@destination_check == :not_found}
                class="rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800"
              >
                We couldn't verify this GLN.
              </p>
            </div>
            <div class="td-header-actions">
              <.td_button
                id="cancel-manufacturer-shipment"
                variant="secondary"
                label="Cancel"
                navigate={~p"/manufacturer/shipments"}
              />
              <.td_button
                id="save-manufacturer-shipment"
                type="submit"
                variant="primary"
                label="Create draft shipment"
                phx-disable-with="Saving…"
              />
            </div>
          </.form>
        </section>
        <aside class="space-y-4">
          <.gln_card
            title="Ship from"
            icon="hero-building-office-2"
            record={selected(@origins, @form[:origin_gln].value)}
          />
          <.gln_card
            title="Ship to"
            icon="hero-building-storefront"
            record={destination_record(@destination_check, @form[:destination_gln].value)}
          />
        </aside>
      </div>
    </Layouts.manufacturer_shell>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :record, :any, required: true

  defp gln_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border p-4",
      if(@record,
        do: "border-thamani-forest/30 bg-td-accent-tint",
        else: "border-dashed border-thamani-stone bg-thamani-canvas"
      )
    ]}>
      <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
        <.icon name={@icon} class="size-4" /> {@title}
      </div>
      <%= if @record do %>
        <p class="mt-2 font-medium text-thamani-forest">{@record.name}</p><p class="text-sm">
          {@record.address}
        </p><p class="mt-1 font-mono text-xs text-thamani-pewter">GLN {@record.gln}</p>
      <% else %>
        <p class="mt-2 text-sm text-thamani-pewter">Not selected yet.</p>
      <% end %>
    </div>
    """
  end
end
