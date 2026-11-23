defmodule ThamaniDawaWeb.DistributorShipmentLive.Form do
  @moduledoc """
  Creates or edits a draft shipment: order number, origin GLN (one of the
  organization's own sites) and destination GLN (resolved live — another
  organization's site on this platform, or any GS1-registered company).
  Editing is blocked once the shipment has left draft.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{GlnLookup, Shipment}
  alias ThamaniDawaWeb.SiteScoping

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  def mount(params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:origins, GlnLookup.search_origin(organization_id, "", 500))
      |> assign(:referenceable_shipments, Distributor.list_approved_shipments(organization_id))

    case socket.assigns.live_action do
      :new ->
        shipment = %Shipment{origin_gln: default_origin_gln(socket)}

        {:ok,
         socket
         |> assign(:destination_check, :idle)
         |> assign(:transfer_mode, false)
         |> assign_form(shipment, "New shipment")}

      :edit ->
        case Distributor.fetch_editable_shipment(organization_id, params["id"]) do
          {:ok, shipment} ->
            destination_check =
              if shipment.destination_gln,
                do: {:matched, shipment.destination_company, shipment.destination_address},
                else: :idle

            {:ok,
             socket
             |> assign(:destination_check, destination_check)
             |> assign(:transfer_mode, false)
             |> assign_form(shipment, "Edit #{shipment.order_number}")}

          {:error, :not_editable} ->
            {:ok,
             socket
             |> put_flash(:error, "Only draft shipments can be edited.")
             |> push_navigate(to: ~p"/distributor/shipments/#{params["id"]}")}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Shipment not found.")
             |> push_navigate(to: ~p"/distributor/shipments")}
        end
    end
  end

  defp assign_form(socket, shipment, title) do
    socket
    |> assign(:shipment, shipment)
    |> assign(:page_title, title)
    |> assign(:form, to_form(Distributor.change_shipment(shipment), as: :shipment))
  end

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

  def handle_event("toggle_transfer_mode", _params, socket) do
    {:noreply, update(socket, :transfer_mode, &(!&1))}
  end

  def handle_event("save", %{"shipment" => attrs}, socket) do
    cond do
      socket.assigns.destination_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still verifying the destination GLN. Press Save again in a moment."
         )}

      socket.assigns.destination_check == :idle ->
        {:noreply,
         socket
         |> check_destination_gln(attrs)
         |> put_flash(:error, "Verifying the destination GLN. Press Save again in a moment.")}

      not match?({:matched, _, _}, socket.assigns.destination_check) ->
        {:noreply,
         put_flash(socket, :error, "Enter a valid, verified destination GLN before saving.")}

      true ->
        save_shipment(socket, attrs)
    end
  end

  defp save_shipment(socket, attrs) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    result =
      case socket.assigns.live_action do
        :new -> Distributor.create_shipment(scope.organization_id, scope.user, attrs)
        :edit -> Distributor.update_shipment(scope.organization_id, scope.user, shipment, attrs)
      end

    case result do
      {:ok, shipment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shipment saved. Your mobile team can now find it by order number.")
         |> push_navigate(to: ~p"/distributor/shipments/#{shipment.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :shipment))}

      {:error, :not_editable} ->
        {:noreply,
         socket
         |> put_flash(:error, "This shipment has already been submitted and can't be edited.")
         |> push_navigate(to: ~p"/distributor/shipments/#{shipment.id}")}
    end
  end

  defp selected(records, gln), do: Enum.find(records, &(&1.gln == gln))

  defp other_origins(origins, origin_gln), do: Enum.reject(origins, &(&1.gln == origin_gln))

  defp destination_record({:matched, company, address}, gln),
    do: %{name: company, address: address, po_box: nil, gln: gln}

  defp destination_record(_check, _gln), do: nil

  defp default_origin_gln(socket) do
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)
    Enum.find_value(socket.assigns.origins, fn site -> site.id == site_id && site.gln end)
  end

  defp maybe_check_destination(socket, params, attrs) do
    if Map.get(params, "_target") == ["shipment", "destination_gln"] do
      check_destination_gln(socket, attrs)
    else
      socket
    end
  end

  defp check_destination_gln(socket, attrs) do
    gln = attrs |> Map.get("destination_gln", "") |> to_string() |> String.trim()

    if Regex.match?(~r/^\d{13}$/, gln) do
      socket
      |> assign(:destination_check, :checking)
      |> start_async(:destination_lookup, fn -> GlnLookup.resolve_party(gln) end)
    else
      assign(socket, :destination_check, :idle)
    end
  end

  def handle_async(:destination_lookup, {:ok, {:ok, resolved}}, socket) do
    {:noreply, assign(socket, :destination_check, {:matched, resolved.company, resolved.address})}
  end

  def handle_async(:destination_lookup, {:ok, {:error, :not_found}}, socket) do
    {:noreply, assign(socket, :destination_check, :not_found)}
  end

  def handle_async(:destination_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :destination_check, :unavailable)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <.header
        icon="hero-truck"
        back={
          if @live_action == :edit,
            do: ~p"/distributor/shipments/#{@shipment.id}",
            else: ~p"/distributor/shipments"
        }
      >
        {@page_title}
        <:subtitle>
          The mobile team finds this shipment by its order number, then scans units into shippers.
        </:subtitle>
      </.header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <section class="rounded-2xl ff-surface-card p-5 sm:p-6">
          <.form
            for={@form}
            id="distributor-shipment-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-6"
          >
            <div>
              <.input
                field={@form[:order_number]}
                label="Order number"
                placeholder="e.g. PO-2026-0142"
                required
              />
            </div>

            <div class="space-y-3 border-t border-thamani-stone pt-5">
              <.input
                field={@form[:origin_gln]}
                type="select"
                label="Origin (ship from)"
                prompt="Choose one of your sites"
                options={Enum.map(@origins, &{"#{&1.name} · #{&1.gln}", &1.gln})}
                required
              />
              <p :if={@origins == []} class="text-xs leading-5 text-thamani-pewter">
                No sites with a GLN yet. <.link
                  navigate={~p"/org/sites/new"}
                  class="font-semibold text-thamani-forest hover:underline"
                >
                  Add a warehouse
                </.link>.
              </p>
            </div>

            <div class="space-y-3 border-t border-thamani-stone pt-5">
              <div>
                <p class="text-sm font-medium text-thamani-forest">Destination</p>
                <label class="mt-2 flex min-h-8 w-fit cursor-pointer items-center gap-2.5 text-sm font-medium text-thamani-forest">
                  <input
                    type="checkbox"
                    checked={@transfer_mode}
                    phx-click="toggle_transfer_mode"
                    class="size-4 rounded border-thamani-stone accent-thamani-forest"
                  /> Destination is one of your sites
                </label>
              </div>

              <.input
                :if={@transfer_mode}
                field={@form[:destination_gln]}
                type="select"
                label="Destination site"
                prompt="Choose one of your sites"
                options={
                  Enum.map(other_origins(@origins, @form[:origin_gln].value), &{"#{&1.name} · #{&1.gln}", &1.gln})
                }
                phx-debounce="0"
                required
              />
              <p
                :if={@transfer_mode and other_origins(@origins, @form[:origin_gln].value) == []}
                class="text-xs leading-5 text-thamani-pewter"
              >
                No other sites with a GLN yet.
              </p>
              <.input
                :if={!@transfer_mode}
                field={@form[:destination_gln]}
                label="Destination GLN (ship to)"
                placeholder="13-digit GLN of the receiving party"
                inputmode="numeric"
                phx-debounce="500"
                required
              />

              <%= case @destination_check do %>
                <% :checking -> %>
                  <p class="inline-flex items-center gap-1.5 text-xs font-medium text-thamani-pewter">
                    <.icon name="hero-arrow-path" class="size-3.5 motion-safe:animate-spin" />
                    Verifying&hellip;
                  </p>
                <% {:matched, _company, _address} -> %>
                  <div class="rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2.5 text-xs font-semibold text-thamani-forest">
                    <p class="inline-flex items-center gap-1.5">
                      <.icon name="hero-check-circle" class="size-4" /> Verified
                    </p>
                  </div>
                <% :not_found -> %>
                  <p class="inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                    <.icon name="hero-exclamation-triangle" class="size-4" />
                    We couldn't verify this GLN. Double-check the number before continuing.
                  </p>
                <% :unavailable -> %>
                  <p class="text-xs leading-5 text-thamani-pewter">
                    We couldn't verify this GLN right now. Try again in a moment.
                  </p>
                <% _ -> %>
                  <p class="text-xs leading-5 text-thamani-pewter">
                    We verify this as soon as you enter it — against your own sites and the GS1 registry.
                  </p>
              <% end %>

              <label class="flex min-h-8 w-fit cursor-pointer items-center gap-2.5 pt-2 text-sm font-medium text-thamani-forest">
                <input
                  type="checkbox"
                  name="shipment[is_return]"
                  value="true"
                  checked={@form[:is_return].value in [true, "true"]}
                  class="size-4 rounded border-thamani-stone accent-thamani-forest"
                /> This is a return
              </label>

              <.input
                :if={@form[:is_return].value in [true, "true"]}
                field={@form[:reference_shipment_id]}
                type="select"
                label="Returning against shipment"
                prompt="Choose the original shipment (optional)"
                options={Enum.map(@referenceable_shipments, &{&1.order_number, &1.id})}
              />
            </div>

            <div class="flex flex-col-reverse gap-3 border-t border-thamani-stone pt-6 sm:flex-row sm:justify-end">
              <.button
                id="cancel-distributor-shipment"
                variant="ghost"
                navigate={
                  if @live_action == :edit,
                    do: ~p"/distributor/shipments/#{@shipment.id}",
                    else: ~p"/distributor/shipments"
                }
              >
                Cancel
              </.button>
              <.button id="save-distributor-shipment" variant="primary" phx-disable-with="Saving…">
                {if @live_action == :new, do: "Create draft shipment", else: "Save changes"}
              </.button>
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
          <p class="px-1 text-xs leading-5 text-thamani-pewter">
            The company name, address and P.O. box are copied onto the shipment when you save, so
            labels keep the details as they were at the time of shipping.
          </p>
        </aside>
      </div>
    </Layouts.distributor_shell>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :record, :any, required: true

  defp gln_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border p-4 transition-colors duration-200",
      if(@record,
        do: "border-thamani-forest/30 bg-thamani-lime/30",
        else: "border-dashed border-thamani-stone bg-thamani-canvas"
      )
    ]}>
      <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
        <.icon name={@icon} class="size-4" /> {@title}
      </div>
      <%= if @record do %>
        <p class="mt-2 font-medium text-thamani-forest">{@record.name}</p>
        <p :if={@record.address} class="text-sm text-thamani-ink">{@record.address}</p>
        <p :if={Map.get(@record, :po_box)} class="text-sm text-thamani-ink">{@record.po_box}</p>
        <p class="mt-1 font-mono text-xs text-thamani-pewter">GLN {@record.gln}</p>
      <% else %>
        <p class="mt-2 text-sm text-thamani-pewter">Not selected yet.</p>
      <% end %>
    </div>
    """
  end
end
