defmodule ThamaniDawaWeb.DistributorShipmentLive.Form do
  @moduledoc """
  Creates or edits a draft shipment: order number, origin GLN (one of the
  organization's own sites) and destination GLN (one of its customers).
  Editing is blocked once the shipment has left draft.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{GlnLookup, Shipment}

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  def mount(params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:origins, GlnLookup.search_origin(organization_id, "", 500))
      |> assign(:destinations, GlnLookup.search_destination(organization_id, "", 500))

    case socket.assigns.live_action do
      :new ->
        {:ok, assign_form(socket, %Shipment{}, "New shipment")}

      :edit ->
        case Distributor.fetch_editable_shipment(organization_id, params["id"]) do
          {:ok, shipment} ->
            {:ok, assign_form(socket, shipment, "Edit #{shipment.order_number}")}

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

  def handle_event("validate", %{"shipment" => params}, socket) do
    changeset =
      socket.assigns.shipment
      |> Distributor.change_shipment(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :shipment))}
  end

  def handle_event("save", %{"shipment" => params}, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    result =
      case socket.assigns.live_action do
        :new -> Distributor.create_shipment(scope.organization_id, scope.user, params)
        :edit -> Distributor.update_shipment(scope.organization_id, scope.user, shipment, params)
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
          >
            <.input
              field={@form[:order_number]}
              label="Order number"
              placeholder="e.g. PO-2026-0142"
              required
            />

            <.input
              field={@form[:origin_gln]}
              type="select"
              label="Origin (ship from)"
              prompt="Choose one of your sites"
              options={Enum.map(@origins, &{"#{&1.name} · #{&1.gln}", &1.gln})}
              required
            />
            <p :if={@origins == []} class="-mt-1 mb-3 text-xs text-thamani-pewter">
              No sites with a GLN yet —
              <.link navigate={~p"/distributor/warehouses/new"} class="font-semibold text-thamani-forest hover:underline">
                add a warehouse
              </.link>.
            </p>

            <.input
              field={@form[:destination_gln]}
              type="select"
              label="Destination (ship to)"
              prompt="Choose a customer"
              options={Enum.map(@destinations, &{"#{&1.name} · #{&1.gln}", &1.gln})}
              required
            />
            <p :if={@destinations == []} class="-mt-1 mb-3 text-xs text-thamani-pewter">
              No customers yet —
              <.link navigate={~p"/distributor/customers/new"} class="font-semibold text-thamani-forest hover:underline">
                add a customer
              </.link>.
            </p>

            <div class="mt-4 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
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
          <.gln_card title="Ship from" icon="hero-building-office-2" record={selected(@origins, @form[:origin_gln].value)} />
          <.gln_card
            title="Ship to"
            icon="hero-building-storefront"
            record={selected(@destinations, @form[:destination_gln].value)}
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
