defmodule ThamaniDawaWeb.DistributorWarehouseLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket),
    do: {:ok, socket |> assign(:page_number, 1) |> reload_warehouses()}

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> reload_warehouses()

    form =
      if socket.assigns.live_action == :new do
        to_form(warehouse_changeset(%Site{}, %{}), as: :site)
      else
        nil
      end

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("validate", %{"site" => attrs}, socket) do
    changeset = Map.put(warehouse_changeset(%Site{}, attrs), :action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
  end

  def handle_event("save", %{"site" => attrs}, socket) do
    case Sites.create_site(
           socket.assigns.current_scope.organization_id,
           Map.put(attrs, "site_type", "warehouse")
         ) do
      {:ok, warehouse} ->
        {:noreply,
         socket
         |> put_flash(:info, "Warehouse added.")
         |> stream_insert(:warehouses, warehouse)
         |> push_patch(to: ~p"/distributor/warehouses")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp reload_warehouses(socket) do
    warehouses =
      socket.assigns.current_scope.organization_id
      |> Sites.list_sites()
      |> Enum.filter(&(&1.site_type == :warehouse))

    page_info = DistributorPagination.page(warehouses, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:warehouses, page_info.entries, reset: true)
  end

  defp warehouse_changeset(site, attrs),
    do: Site.changeset(site, Map.put(attrs, "site_type", "warehouse"))

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/warehouses"}
    >
      <.header icon="hero-building-office-2">
        Warehouses
        <:subtitle>Set up the locations where distributor stock is received and held.</:subtitle>
        <:actions>
          <.button
            id="add-distributor-warehouse"
            variant="primary"
            patch={~p"/distributor/warehouses/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Add warehouse
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="distributor-warehouse-modal"
        show
        on_cancel={JS.patch(~p"/distributor/warehouses")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">Add warehouse</h2>
        <.form
          for={@form}
          id="distributor-warehouse-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-4"
        >
          <div class="space-y-4">
            <.input field={@form[:name]} label="Warehouse name" required />
            <.input field={@form[:address]} label="Address" required />
          </div>
          <.button class="mt-2" variant="primary">Add warehouse</.button>
        </.form>
      </.modal>

      <div class="mt-5">
        <.table id="distributor-warehouses" rows={@streams.warehouses}>
          <:col :let={{_id, warehouse}} label="Warehouse">{warehouse.name}</:col>
          <:col :let={{_id, warehouse}} label="Address">{warehouse.address}</:col>
          <:col :let={{_id, warehouse}} label="Status">
            <.status_badge status={if warehouse.is_active, do: :active, else: :inactive} />
          </:col>
          <:empty_state>
            <.blank_state icon="hero-building-office-2" title="No warehouses yet">
              Add a warehouse before receiving distributor stock.
            </.blank_state>
          </:empty_state>
        </.table>
        <.pagination page={@page_info} path={~p"/distributor/warehouses"} />
      </div>
    </Layouts.distributor_shell>
    """
  end
end
