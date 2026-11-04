defmodule ThamaniDawaWeb.DistributorSupplierLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Suppliers
  alias ThamaniDawa.Suppliers.Supplier
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket),
    do: {:ok, socket |> assign(:page_number, 1) |> reload_suppliers()}

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> reload_suppliers()

    {supplier, form} =
      case socket.assigns.live_action do
        :new ->
          {nil, to_form(Supplier.changeset(%Supplier{}, %{}), as: :supplier)}

        :edit ->
          supplier =
            Suppliers.get_supplier!(socket.assigns.current_scope.organization_id, params["id"])

          {supplier, to_form(Suppliers.change_supplier(supplier), as: :supplier)}

        _ ->
          {nil, nil}
      end

    {:noreply, assign(socket, supplier: supplier, form: form)}
  end

  def handle_event("validate", %{"supplier" => attrs}, socket) do
    changeset = Map.put(Supplier.changeset(%Supplier{}, attrs), :action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
  end

  def handle_event("save", %{"supplier" => attrs}, socket) do
    supplier_result(socket, attrs)
  end

  def handle_event("delete_supplier", %{"id" => id}, socket) do
    case Suppliers.delete_supplier(socket.assigns.current_scope.organization_id, id) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplier deleted.")
         |> stream_delete(:suppliers, supplier)
         |> reload_suppliers()}

      {:error, :in_use} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This supplier is used by received stock and cannot be deleted."
         )}
    end
  end

  defp supplier_result(%{assigns: %{live_action: :new}} = socket, attrs) do
    case Suppliers.create_supplier(socket.assigns.current_scope.organization_id, attrs) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplier added.")
         |> stream_insert(:suppliers, supplier)
         |> push_patch(to: ~p"/distributor/suppliers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
    end
  end

  defp supplier_result(socket, attrs) do
    case Suppliers.update_supplier(
           socket.assigns.current_scope.organization_id,
           socket.assigns.supplier.id,
           attrs
         ) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplier updated.")
         |> stream_insert(:suppliers, supplier)
         |> push_patch(to: ~p"/distributor/suppliers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
    end
  end

  defp reload_suppliers(socket) do
    suppliers = Suppliers.list_suppliers(socket.assigns.current_scope.organization_id)
    page_info = DistributorPagination.page(suppliers, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:suppliers, page_info.entries, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/suppliers"}
    >
      <.header icon="hero-truck">
        Suppliers
        <:subtitle>Maintain the manufacturers and wholesalers supplying your warehouses.</:subtitle>
        <:actions>
          <.button
            id="add-distributor-supplier"
            variant="primary"
            patch={~p"/distributor/suppliers/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Add supplier
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="distributor-supplier-modal"
        show
        on_cancel={JS.patch(~p"/distributor/suppliers")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
          {if @live_action == :new, do: "Add supplier", else: "Edit supplier"}
        </h2>
        <.form
          for={@form}
          id="distributor-supplier-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-4"
        >
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:name]} label="Supplier name" required />
            <.input field={@form[:contact]} label="Contact person" />
            <.input field={@form[:phone]} label="Phone" required />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:location]} label="Location" />
          </div>
          <.button class="mt-2" variant="primary">
            {if @live_action == :new, do: "Add supplier", else: "Save changes"}
          </.button>
        </.form>
      </.modal>

      <div class="mt-5">
        <.table id="distributor-suppliers" rows={@streams.suppliers}>
          <:col :let={{_id, supplier}} label="Supplier">
            <span class="font-medium text-thamani-forest">{supplier.name}</span>
          </:col>
          <:col :let={{_id, supplier}} label="Contact">{supplier.contact || "—"}</:col>
          <:col :let={{_id, supplier}} label="Phone">{supplier.phone}</:col>
          <:col :let={{_id, supplier}} label="Email">{supplier.email}</:col>
          <:action :let={{_id, supplier}}>
            <.button
              id={"edit-distributor-supplier-#{supplier.id}"}
              variant="ghost-edit"
              patch={~p"/distributor/suppliers/#{supplier.id}/edit"}
              class="px-3 py-1.5 text-xs"
            >Edit</.button>
          </:action>
          <:action :let={{_id, supplier}}>
            <.button
              id={"delete-distributor-supplier-#{supplier.id}"}
              variant="ghost-delete"
              phx-click="delete_supplier"
              phx-value-id={supplier.id}
              data-confirm="Delete this supplier? This cannot be undone."
              class="px-3 py-1.5 text-xs"
            >
              Delete
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-truck" title="No suppliers yet">
              Add a supplier before receiving distributor stock.
            </.blank_state>
          </:empty_state>
        </.table>
        <.pagination page={@page_info} path={~p"/distributor/suppliers"} />
      </div>
    </Layouts.distributor_shell>
    """
  end
end
