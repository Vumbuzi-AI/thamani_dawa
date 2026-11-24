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
      |> assign(:gs1_api_key, ThamaniDawa.Organizations.gs1_api_key(organization_id))

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

  def handle_event("toggle_transfer_mode", _params, socket) do
    {:noreply, socket |> update(:transfer_mode, &(!&1)) |> assign(:destination_check, :idle)}
  end

  def handle_event("save", %{"shipment" => attrs}, socket) do
    cond do
      socket.assigns.transfer_mode ->
        if selected(
             other_origins(socket.assigns.origins, attrs["origin_gln"]),
             attrs["destination_gln"]
           ),
           do: save_shipment(socket, attrs),
           else: {:noreply, put_flash(socket, :error, "Choose a destination site before saving.")}

      not match?({:matched, _, _}, socket.assigns.destination_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Search the GS1 directory and pick a destination GLN before saving."
         )}

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

  defp destination_selection({:matched, company, address}, gln) when is_binary(gln),
    do: %{gln: gln, company: company, address: address}

  defp destination_selection(_check, _gln), do: nil

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
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <.td_detail_page
        title={@page_title}
        subtitle="The mobile team finds this shipment by its order number, then scans units into shippers."
        back={
          if @live_action == :edit,
            do: ~p"/distributor/shipments/#{@shipment.id}",
            else: ~p"/distributor/shipments"
        }
      >
        <:body>
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
                      Enum.map(
                        other_origins(@origins, @form[:origin_gln].value),
                        &{"#{&1.name} · #{&1.gln}", &1.gln}
                      )
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
                  <.live_component
                    :if={!@transfer_mode}
                    module={ThamaniDawaWeb.GlnSearchField}
                    id="destination-gln-search"
                    name="shipment[destination_gln]"
                    label="Destination GLN (ship to)"
                    api_token={@gs1_api_key}
                    selected={destination_selection(@destination_check, @shipment.destination_gln)}
                    required
                  />

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
                  <.button
                    id="save-distributor-shipment"
                    variant="primary"
                    phx-disable-with="Saving…"
                  >
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
                record={
                  destination_record(@destination_check, @form[:destination_gln].value) ||
                    (@transfer_mode && selected(@origins, @form[:destination_gln].value))
                }
              />
              <p class="px-1 text-xs leading-5 text-thamani-pewter">
                The company name, address and P.O. box are copied onto the shipment when you save, so
                labels keep the details as they were at the time of shipping.
              </p>
            </aside>
          </div>
        </:body>
      </.td_detail_page>
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
        do: "border-thamani-forest/30 bg-td-accent-tint",
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
