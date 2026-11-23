defmodule ThamaniDawaWeb.DistributorShipmentLive.OrderFormComponent do
  @moduledoc """
  The New order and Edit order details modals (Doop `oOLJEW6Y9i` and
  `x-C3WyM0JH`). Same rules as the full-page form: an order number, a
  ship-from site, and a ship-to party that is either one of the
  organization's own sites or a party GS1 confirmed. Ship-to is picked with
  the shared `GlnField`. Editing only works while the order is a draft.

  On save it navigates to the order with a flash. `cancel` is the path the
  Cancel and close buttons patch or navigate back to.
  """

  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{GlnLookup, Shipment}
  alias ThamaniDawaWeb.SiteScoping

  def update(%{gln_selected: {_field_id, party}}, socket) do
    attrs = Map.put(socket.assigns.form.params, "destination_gln", party && party.gln)

    form =
      socket.assigns.shipment
      |> Distributor.change_shipment(attrs)
      |> to_form(as: :shipment)

    {:ok, assign(socket, destination: party, form: form)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:form] do
      {:ok, socket}
    else
      organization_id = assigns.current_scope.organization_id
      origins = GlnLookup.search_origin(organization_id, "", 500)
      socket = assign(socket, :origins, origins)

      shipment =
        case assigns.action do
          :new -> %Shipment{origin_gln: default_origin_gln(assigns.current_scope, origins)}
          :edit -> assigns.shipment
        end

      destination =
        shipment.destination_gln &&
          %{
            gln: shipment.destination_gln,
            company: shipment.destination_company,
            address: shipment.destination_address,
            po_box: shipment.destination_po_box,
            source: if(shipment.destination_site_id && own_site?(origins, shipment.destination_gln), do: :site, else: :gs1)
          }

      {:ok,
       socket
       |> assign(:shipment, shipment)
       |> assign(:destination, destination)
       |> assign(:own_sites?, destination && destination.source == :site)
       |> assign(:referenceable_shipments, Distributor.list_approved_shipments(organization_id))
       |> assign(:gs1_api_key, ThamaniDawa.Organizations.gs1_api_key(organization_id))
       |> assign(:error, nil)
       |> assign(:form, to_form(Distributor.change_shipment(shipment), as: :shipment))}
    end
  end

  def handle_event("validate", %{"shipment" => attrs}, socket) do
    attrs = Map.put(attrs, "destination_gln", socket.assigns.destination && socket.assigns.destination.gln)

    changeset =
      socket.assigns.shipment
      |> Distributor.change_shipment(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :shipment), error: nil)}
  end

  def handle_event("toggle_own_sites", _params, socket) do
    {:noreply, socket |> update(:own_sites?, &(!&1)) |> assign(destination: nil, error: nil)}
  end

  def handle_event("save", %{"shipment" => attrs}, socket) do
    destination = socket.assigns.destination
    attrs = Map.put(attrs, "destination_gln", destination && destination.gln)

    cond do
      is_nil(destination) ->
        {:noreply, assign(socket, :error, "Pick who this order ships to.")}

      socket.assigns.own_sites? and destination.source != :site ->
        {:noreply, assign(socket, :error, "Choose one of your own sites to ship to.")}

      destination.source == :site and destination.gln == attrs["origin_gln"] ->
        {:noreply, assign(socket, :error, "Ship to a different site than the one it ships from.")}

      true ->
        save(socket, attrs)
    end
  end

  defp save(socket, attrs) do
    %{current_scope: scope, shipment: shipment, action: action} = socket.assigns

    result =
      case action do
        :new -> Distributor.create_shipment(scope.organization_id, scope.user, attrs)
        :edit -> Distributor.update_shipment(scope.organization_id, scope.user, shipment, attrs)
      end

    case result do
      {:ok, saved} ->
        {message, query} =
          if action == :new,
            do: {"Order #{saved.order_number} created. Your mobile team can start packing it.", %{"return_to" => "/distributor/orders"}},
            else: {"Order details saved.", %{}}

        query = Map.merge(socket.assigns[:return_query] || %{}, query)

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/distributor/shipments/#{saved.id}?#{query}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :shipment))}

      {:error, :not_editable} ->
        {:noreply, assign(socket, :error, "This order has already been submitted and can't be edited.")}
    end
  end

  defp own_site?(origins, gln), do: Enum.any?(origins, &(&1.gln == gln))

  defp default_origin_gln(scope, origins) do
    site_id = SiteScoping.default_site_id(scope)
    Enum.find_value(origins, fn site -> site.id == site_id && site.gln end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <.modal
        id={"#{@id}-modal"}
        show
        title={if @action == :new, do: "New order", else: "Edit order details"}
        subtitle={
          if @action == :new,
            do: "Record a customer order. Your mobile team packs it, then you approve it here.",
            else: "Change these while the order is still a draft."
        }
        on_cancel={JS.navigate(@cancel)}
      >
        <.form
          for={@form}
          id="distributor-shipment-form"
          class="td-modal-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <div class="td-fgrid is-2">
            <.input
              field={@form[:order_number]}
              label="Customer order number"
              placeholder="For example PO-1042"
              required
            />
            <.input
              field={@form[:origin_gln]}
              type="select"
              label="Ship from"
              prompt="Choose one of your sites"
              options={Enum.map(@origins, &{&1.name, &1.gln})}
              required
            />
          </div>
          <p :if={@origins == []} class="td-note">
            No sites with a GLN yet. <.link navigate={~p"/org/sites/new"} class="td-link">Add a warehouse</.link>.
          </p>
          <div class="td-toggle-row">
            <span id="order-own-sites-label">Ship to one of your own sites</span>
            <.td_switch
              id="order-own-sites-toggle"
              on={@own_sites?}
              label="Ship to one of your own sites"
              phx-click="toggle_own_sites"
              phx-target={@myself}
            />
          </div>
          <.live_component
            module={ThamaniDawaWeb.GlnField}
            id={if @own_sites?, do: "destination-gln-sites", else: "destination-gln-search"}
            name="shipment[destination_gln_display]"
            label="Ship to"
            organization_id={@current_scope.organization_id}
            api_token={@gs1_api_key}
            scope={if @own_sites?, do: :sites, else: :all}
            exclude_gln={@own_sites? && @form[:origin_gln].value}
            selected={@destination}
            notify={{__MODULE__, @id}}
            required
          />
          <label class="td-check">
            <input
              type="checkbox"
              name="shipment[is_return]"
              value="true"
              checked={@form[:is_return].value in [true, "true"]}
            />
            <span>This is a return</span>
          </label>
          <.input
            :if={@form[:is_return].value in [true, "true"]}
            field={@form[:reference_shipment_id]}
            type="select"
            label="Returning against shipment"
            prompt="Choose the original shipment (optional)"
            options={Enum.map(@referenceable_shipments, &{&1.order_number, &1.id})}
          />
          <p :if={@error} id="order-form-error" class="td-field-error">{@error}</p>
        </.form>
        <:footer>
          <.td_button type="button" id="cancel-distributor-shipment" phx-click={JS.navigate(@cancel)}>
            Cancel
          </.td_button>
          <.td_button
            id="save-distributor-shipment"
            type="submit"
            form="distributor-shipment-form"
            variant="primary"
            phx-disable-with="Saving…"
          >
            {if @action == :new, do: "Create order", else: "Save changes"}
          </.td_button>
        </:footer>
      </.modal>
    </div>
    """
  end
end
