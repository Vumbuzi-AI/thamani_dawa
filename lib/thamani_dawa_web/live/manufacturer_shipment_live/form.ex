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
     |> assign(:gs1_api_key, ThamaniDawa.Organizations.gs1_api_key(organization_id))
     |> assign(:form, to_form(Distributor.change_shipment(shipment), as: :shipment))}
  end

  def handle_event("toggle_transfer_mode", _params, socket),
    do: {:noreply, socket |> update(:transfer_mode, &(!&1)) |> assign(:destination_check, :idle)}

  def handle_event("validate", %{"shipment" => attrs}, socket) do
    changeset =
      socket.assigns.shipment
      |> Distributor.change_shipment(attrs)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:form, to_form(changeset, as: :shipment))

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

  def handle_info({:gln_selected, "destination-gln-search", party}, socket) do
    check = if party, do: {:matched, party.company, party.address}, else: :idle
    gln = party && party.gln

    form =
      socket.assigns.shipment
      |> Distributor.change_shipment(Map.put(socket.assigns.form.params, "destination_gln", gln))
      |> to_form(as: :shipment)

    {:noreply, assign(socket, destination_check: check, form: form)}
  end

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
              <.live_component
                :if={!@transfer_mode}
                module={ThamaniDawaWeb.GlnSearchField}
                id="destination-gln-search"
                name="shipment[destination_gln]"
                label="Destination GLN (ship to)"
                api_token={@gs1_api_key}
                required
              />
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
            record={
              destination_record(@destination_check, @form[:destination_gln].value) ||
                (@transfer_mode && selected(@origins, @form[:destination_gln].value))
            }
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
