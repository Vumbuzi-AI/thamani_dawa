defmodule ThamaniDawaWeb.DistributorCustomerLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.DistributorCustomers
  alias ThamaniDawa.DistributorCustomers.Customer
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_number, 1) |> reload_customers()}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> reload_customers()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_event("validate", %{"customer" => attrs}, socket) do
    changeset =
      socket.assigns.customer
      |> Kernel.||(%Customer{})
      |> DistributorCustomers.change_customer(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :customer))}
  end

  def handle_event("save", %{"customer" => attrs}, socket) do
    case socket.assigns.live_action do
      :new -> create_customer(socket, attrs)
      :edit -> update_customer(socket, attrs)
    end
  end

  defp apply_action(socket, :new, _params) do
    assign(socket,
      customer: nil,
      form: to_form(DistributorCustomers.change_customer(%Customer{}), as: :customer)
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    customer =
      DistributorCustomers.get_customer!(socket.assigns.current_scope.organization_id, id)

    assign(socket,
      customer: customer,
      form: to_form(DistributorCustomers.change_customer(customer), as: :customer)
    )
  end

  defp apply_action(socket, :index, _params), do: assign(socket, customer: nil, form: nil)

  defp create_customer(socket, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case DistributorCustomers.create_customer(organization_id, attrs) do
      {:ok, customer} ->
        {:noreply,
         socket
         |> put_flash(:info, "Customer added.")
         |> stream_insert(:customers, customer)
         |> push_patch(to: ~p"/distributor/customers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :customer))}
    end
  end

  defp update_customer(socket, attrs) do
    case DistributorCustomers.update_customer(socket.assigns.customer, attrs) do
      {:ok, customer} ->
        {:noreply,
         socket
         |> put_flash(:info, "Customer updated.")
         |> stream_insert(:customers, customer)
         |> push_patch(to: ~p"/distributor/customers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :customer))}
    end
  end

  defp reload_customers(socket) do
    customers = DistributorCustomers.list_customers(socket.assigns.current_scope.organization_id)
    page_info = DistributorPagination.page(customers, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:customers, page_info.entries, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/customers"}
    >
      <.header icon="hero-building-storefront">
        Customers
        <:subtitle>Manage the pharmacies, clinics, and facilities you supply.</:subtitle>
        <:actions>
          <.button
            id="add-distributor-customer"
            variant="primary"
            patch={~p"/distributor/customers/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Add customer
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="distributor-customer-modal"
        show
        on_cancel={JS.patch(~p"/distributor/customers")}
      >
        <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">
          {if @live_action == :new, do: "Add customer", else: "Edit customer"}
        </h2>
        <.form for={@form} id="distributor-customer-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label="Organization name" required />
          <.input field={@form[:contact_name]} label="Contact person" />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:phone]} label="Phone" />
            <.input field={@form[:email]} type="email" label="Email" />
          </div>
          <.input field={@form[:address]} type="textarea" label="Delivery address" />
          <.input field={@form[:is_active]} type="checkbox" label="Active customer" />
          <.button class="mt-3 w-full" variant="primary">Save customer</.button>
        </.form>
      </.modal>

      <.table id="distributor-customers" rows={@streams.customers}>
        <:col :let={{_id, customer}} label="Customer">
          <span class="font-medium text-thamani-forest">{customer.name}</span>
        </:col>
        <:col :let={{_id, customer}} label="Contact">{customer.contact_name || "—"}</:col>
        <:col :let={{_id, customer}} label="Phone">{customer.phone || "—"}</:col>
        <:col :let={{_id, customer}} label="Status">
          <.status_badge status={if customer.is_active, do: :active, else: :inactive} />
        </:col>
        <:action :let={{_id, customer}}>
          <.button
            id={"edit-distributor-customer-#{customer.id}"}
            variant="ghost-edit"
            patch={~p"/distributor/customers/#{customer.id}/edit"}
          >
            Edit
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-building-storefront" title="No customers yet">
            Add the first facility you supply to begin creating distributor orders.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={~p"/distributor/customers"} />
    </Layouts.distributor_shell>
    """
  end
end
