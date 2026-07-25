defmodule ThamaniDawaWeb.SupplierLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Suppliers
  alias ThamaniDawa.Suppliers.Supplier

  @default_filters %{status: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> reload_suppliers()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    socket = socket |> assign(:page, page) |> reload_suppliers()
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket,
      form: to_form(Suppliers.change_supplier(%Supplier{}, %{}), as: :supplier),
      supplier: nil
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    organization_id = socket.assigns.current_scope.organization_id
    supplier = Suppliers.get_supplier!(organization_id, id)

    assign(socket,
      form: to_form(Suppliers.change_supplier(supplier, %{}), as: :supplier),
      supplier: supplier
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, supplier: nil)
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> reload_suppliers()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{status: Map.get(filter_params, "status", "")}
    {:noreply, socket |> assign(:filters, filters) |> reload_suppliers()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> reload_suppliers()}
  end

  def handle_event("clear_chip", %{"field" => "status"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | status: ""}) |> reload_suppliers()}
  end

  def handle_event("validate", %{"supplier" => attrs}, socket) do
    changeset =
      socket.assigns.supplier
      |> Kernel.||(%Supplier{})
      |> Suppliers.change_supplier(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :supplier))}
  end

  def handle_event("save", %{"supplier" => attrs}, socket) do
    save_supplier(socket, socket.assigns.live_action, attrs)
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    supplier = Suppliers.get_supplier!(org_id, id)

    case Suppliers.update_supplier(supplier, %{is_active: !supplier.is_active}) do
      {:ok, _updated} ->
        {:noreply, reload_suppliers(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update supplier.")}
    end
  end

  defp save_supplier(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Suppliers.create_supplier(organization_id, attrs) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplier created.")
         |> stream_insert(:suppliers, supplier)
         |> push_patch(to: ~p"/org/suppliers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
    end
  end

  defp save_supplier(socket, :edit, attrs) do
    case Suppliers.update_supplier(socket.assigns.supplier, attrs) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplier updated.")
         |> stream_insert(:suppliers, supplier)
         |> push_patch(to: ~p"/org/suppliers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
    end
  end

  defp reload_suppliers(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = Suppliers.list_suppliers_paginated(organization_id, page)
    suppliers = page_result.entries

    filtered =
      suppliers
      |> filter_by_search(socket.assigns.search)
      |> filter_by_status(socket.assigns.filters.status)

    socket
    |> stream(:suppliers, filtered, reset: true)
    |> assign(:page_info, page_result)
  end

  defp filter_by_search(suppliers, ""), do: suppliers

  defp filter_by_search(suppliers, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(suppliers, fn supplier ->
      [supplier.name, supplier.contact, supplier.email, supplier.gln]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_status(suppliers, ""), do: suppliers
  defp filter_by_status(suppliers, "active"), do: Enum.filter(suppliers, & &1.is_active)
  defp filter_by_status(suppliers, "inactive"), do: Enum.filter(suppliers, &(!&1.is_active))

  defp active_filter_count(filters) do
    Enum.count([filters.status != ""], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"}
    ]
    |> Enum.filter(& &1)
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/suppliers"}>
      <.header icon="hero-truck">
        Suppliers
        <:subtitle>Search, filter, and manage your organization's suppliers.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/org/suppliers/new"}>+ Add supplier</.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by name, contact, email, or GLN"
            />
          </form>

          <.filter_drawer
            id="suppliers-filters"
            title="Filter suppliers"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={[{"Active", "active"}, {"Inactive", "inactive"}]}
                prompt="All statuses"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="supplier-modal"
        show
        on_cancel={JS.patch(~p"/org/suppliers")}
      >
        <h2 class="font-semibold mb-2">
          {if @live_action == :new, do: "Add a supplier", else: "Edit supplier"}
        </h2>
        <.form for={@form} id="supplier-form" phx-submit="save" phx-change="validate">
          <.input field={@form[:name]} label="Name" required />
          <div class="grid grid-cols-2 gap-x-4">
            <.input field={@form[:contact]} label="Contact person" />
            <.input field={@form[:phone]} label="Phone" required />
          </div>
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:location]} label="Location" />
          <.input field={@form[:is_active]} type="checkbox" label="Active" />
          <div class="flex gap-2 mt-2">
            <.button variant="primary">Save</.button>
            <.button patch={~p"/org/suppliers"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.table id="suppliers" rows={@streams.suppliers}>
        <:col :let={{_id, supplier}} label="Name">{supplier.name}</:col>
        <:col :let={{_id, supplier}} label="Contact">{supplier.contact}</:col>
        <:col :let={{_id, supplier}} label="Phone">{supplier.phone}</:col>
        <:col :let={{_id, supplier}} label="Email">{supplier.email}</:col>
        <:col :let={{_id, supplier}} label="GLN">{supplier.gln}</:col>
        <:col :let={{_id, supplier}} label="Status">
          <.status_badge status={if supplier.is_active, do: :active, else: :inactive} />
        </:col>
        <:action :let={{_id, supplier}}>
          <.button
            variant="ghost-edit"
            patch={~p"/org/suppliers/#{supplier.id}/edit"}
            class="gap-2"
          >
            <.icon name="hero-pencil-square" class="size-4" />
            Edit
          </.button>
        </:action>
        <:action :let={{_id, supplier}}>
          <.button
            type="button"
            phx-click="toggle_active"
            phx-value-id={supplier.id}
            class="gap-2"
            variant={if supplier.is_active, do: "ghost-delete", else: "ghost"}
          >
            <.icon
              name={if supplier.is_active, do: "hero-power", else: "hero-arrow-path"}
              class="size-4"
            />
            {if supplier.is_active, do: "Deactivate", else: "Reactivate"}
          </.button>
        </:action>
        <:empty_state>
          <.blank_state
            icon="hero-truck"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No suppliers match your search or filters",
                else: "No suppliers yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Suppliers you add will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.pagination page={@page_info} path={~p"/org/suppliers"} />
    </Layouts.org_shell>
    """
  end
end
