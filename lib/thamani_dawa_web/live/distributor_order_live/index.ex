defmodule ThamaniDawaWeb.DistributorOrderLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.DistributorCustomers
  alias ThamaniDawa.DistributorCustomers.Customer
  alias ThamaniDawa.DistributorOrders
  alias ThamaniDawa.DistributorOrders.Order
  alias ThamaniDawa.DistributorOrders.OrderItem
  alias ThamaniDawa.Products
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(
       :customers,
       Enum.filter(DistributorCustomers.list_customers(organization_id), & &1.is_active)
     )
     |> assign(:products, Enum.filter(Products.list_products(organization_id), & &1.is_active))
     |> assign(:show_customer_form, false)
     |> assign(:customer_form, nil)
     |> stream(:orders, [])}
  end

  def handle_params(params, _url, socket) do
    orders = DistributorOrders.list_orders(socket.assigns.current_scope.organization_id)
    page_info = DistributorPagination.page(orders, DistributorPagination.page_number(params))

    {form, editing_order} =
      case socket.assigns.live_action do
        :new ->
          order = %Order{items: [%OrderItem{}]}
          {to_form(Order.changeset(order, %{}), as: :order), nil}

        :edit ->
          order =
            DistributorOrders.get_order!(
              socket.assigns.current_scope.organization_id,
              params["id"]
            )

          {to_form(Order.changeset(order, %{}), as: :order), order}

        _action ->
          {nil, nil}
      end

    {:noreply,
     socket
     |> assign(:page_info, page_info)
     |> stream(:orders, page_info.entries, reset: true)
     |> assign(:form, form)
     |> assign(:editing_order, editing_order)
     |> assign(:show_customer_form, false)
     |> assign(:customer_form, nil)}
  end

  def handle_event("validate", %{"order" => attrs}, socket) do
    order = socket.assigns.form.source.data
    changeset = order |> Order.changeset(attrs) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :order))}
  end

  def handle_event("add_customer", _params, socket) do
    customer_form = to_form(DistributorCustomers.change_customer(%Customer{}), as: :customer)

    {:noreply,
     socket
     |> assign(:show_customer_form, true)
     |> assign(:customer_form, customer_form)}
  end

  def handle_event("back_to_order", _params, socket) do
    {:noreply, assign(socket, :show_customer_form, false)}
  end

  def handle_event("validate_customer", %{"customer" => attrs}, socket) do
    changeset =
      %Customer{}
      |> DistributorCustomers.change_customer(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :customer_form, to_form(changeset, as: :customer))}
  end

  def handle_event("save_customer", %{"customer" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case DistributorCustomers.create_customer(organization_id, attrs) do
      {:ok, customer} ->
        order_changeset =
          Ecto.Changeset.put_change(socket.assigns.form.source, :customer_id, customer.id)

        {:noreply,
         socket
         |> assign(
           :customers,
           Enum.sort_by([customer | socket.assigns.customers], &String.downcase(&1.name))
         )
         |> assign(:form, to_form(order_changeset, as: :order))
         |> assign(:show_customer_form, false)
         |> assign(:customer_form, nil)
         |> put_flash(:info, "Customer added. Continue building the order.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :customer_form, to_form(changeset, as: :customer))}
    end
  end

  def handle_event("add_line", _params, socket) do
    changeset = socket.assigns.form.source
    lines = Ecto.Changeset.get_assoc(changeset, :items)
    changeset = Ecto.Changeset.put_assoc(changeset, :items, lines ++ [%OrderItem{}])
    {:noreply, assign(socket, :form, to_form(changeset, as: :order))}
  end

  def handle_event("save", %{"order" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    result =
      case socket.assigns.live_action do
        :new ->
          DistributorOrders.create_order(organization_id, attrs)

        :edit ->
          DistributorOrders.update_order(organization_id, socket.assigns.editing_order, attrs)
      end

    case result do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           if(socket.assigns.live_action == :new,
             do: "Customer order created.",
             else: "Order updated."
           )
         )
         |> stream_insert(:orders, order, at: 0)
         |> push_patch(to: ~p"/distributor/orders")}

      {:error, :not_editable} ->
        {:noreply, put_flash(socket, :error, "Only pending orders can be edited.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :order))}
    end
  end

  defp customer_name(%Customer{name: name}), do: name

  defp order_total(order) do
    Enum.reduce(order.items, 0, fn item, total -> total + item.quantity * item.unit_price end)
  end

  defp money(amount), do: "KES #{amount}"

  defp order_date(date), do: Calendar.strftime(date, "%d %b %Y, %H:%M")

  defp item_summary(items) do
    count = length(items)
    "#{count} #{if count == 1, do: "item", else: "items"}"
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/orders"}
    >
      <.header icon="hero-clipboard-document-list">
        Orders
        <:subtitle>Record customer orders and track what is waiting to be fulfilled.</:subtitle>
        <:actions>
          <.button
            id="new-distributor-order"
            variant="primary"
            patch={~p"/distributor/orders/new"}
          >
            <.icon name="hero-plus" class="size-4" /> New order
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="distributor-order-modal"
        show
        on_cancel={JS.patch(~p"/distributor/orders")}
      >
        <div class="border-b border-thamani-stone pb-4">
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
            {if @live_action == :new,
              do: "New customer order",
              else: "Edit order ##{@editing_order.id}"}
          </h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Choose a customer and add the products and quantities they requested.
          </p>
        </div>

        <%= if @show_customer_form do %>
          <div class="mt-5">
            <h3 class="text-sm font-semibold text-thamani-forest">Add a customer</h3>
            <p class="mt-1 text-sm text-thamani-pewter">
              Save the customer and they will be selected for this order.
            </p>
          </div>
          <.form
            for={@customer_form}
            id="distributor-order-customer-form"
            phx-change="validate_customer"
            phx-submit="save_customer"
            class="mt-4"
          >
            <.input field={@customer_form[:name]} label="Customer name" required />
            <div class="grid gap-x-4 sm:grid-cols-2">
              <.input field={@customer_form[:contact_name]} label="Contact name" />
              <.input field={@customer_form[:phone]} label="Phone" />
              <.input field={@customer_form[:email]} type="email" label="Email" />
              <.input field={@customer_form[:address]} label="Address" />
            </div>
            <div class="mt-5 flex gap-3">
              <button
                id="back-to-distributor-order"
                type="button"
                phx-click="back_to_order"
                class="flex-1 rounded-lg border border-thamani-stone px-4 py-2 text-sm font-semibold text-thamani-forest hover:bg-thamani-canvas"
              >
                Back to order
              </button>
              <.button class="flex-1" variant="primary">Save customer</.button>
            </div>
          </.form>
        <% else %>
          <.form
            for={@form}
            id="distributor-order-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-5"
          >
            <.input
              field={@form[:customer_id]}
              type="select"
              label="Customer"
              prompt="Select customer"
              options={Enum.map(@customers, &{&1.name, &1.id})}
              required
            />
            <button
              id="add-customer-from-order"
              type="button"
              phx-click="add_customer"
              class="mt-2 inline-flex items-center gap-1 text-sm font-semibold text-thamani-forest hover:underline"
            >
              <.icon name="hero-plus" class="size-4" /> Customer not listed? Add customer
            </button>
            <.input field={@form[:delivery_address]} label="Delivery address (optional)" />

            <div class="mt-5 flex items-center justify-between">
              <h3 class="text-sm font-semibold text-thamani-forest">Order items</h3>
              <button
                type="button"
                phx-click="add_line"
                class="text-sm font-semibold text-thamani-forest hover:underline"
              >
                <.icon name="hero-plus" class="size-4" /> Add item
              </button>
            </div>

            <.inputs_for :let={item_form} field={@form[:items]}>
              <div class="mt-3 grid gap-x-4 sm:grid-cols-[1fr_10rem]">
                <.input
                  field={item_form[:product_id]}
                  type="select"
                  label="Product"
                  prompt="Select product"
                  options={Enum.map(@products, &{&1.generic_name || &1.brand_name, &1.id})}
                  required
                />
                <.input field={item_form[:quantity]} type="number" label="Quantity" min="1" required />
              </div>
            </.inputs_for>

            <p :if={@customers == []} class="mt-3 text-sm text-thamani-error">
              Add an active customer before creating an order.
            </p>
            <p :if={@products == []} class="mt-3 text-sm text-thamani-error">
              Add an active product before creating an order.
            </p>

            <.button
              class="mt-5 w-full"
              variant="primary"
              disabled={@customers == [] or @products == []}
            >
              {if @live_action == :new, do: "Create order", else: "Save changes"}
            </.button>
          </.form>
        <% end %>
      </.modal>

      <.table
        id="distributor-orders"
        rows={@streams.orders}
      >
        <:col :let={{_id, order}} label="Order">#{order.id}</:col>
        <:col :let={{_id, order}} label="Customer">{customer_name(order.customer)}</:col>
        <:col :let={{_id, order}} label="Items">{item_summary(order.items)}</:col>
        <:col :let={{_id, order}} label="Order total">{money(order_total(order))}</:col>
        <:col :let={{_id, order}} label="Placed">{order_date(order.ordered_at)}</:col>
        <:col :let={{_id, order}} label="Status">
          <.status_badge status={order.status} />
        </:col>
        <:action :let={{_id, order}}>
          <.button
            id={"view-distributor-order-#{order.id}"}
            variant="ghost"
            navigate={~p"/distributor/orders/#{order.id}"}
            class="px-3 py-1.5 text-xs"
          >
            View
          </.button>
        </:action>
        <:action :let={{_id, order}}>
          <.button
            :if={order.status == :pending}
            id={"edit-distributor-order-#{order.id}"}
            variant="ghost-edit"
            patch={~p"/distributor/orders/#{order.id}/edit"}
            class="px-3 py-1.5 text-xs"
          >
            Edit
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No customer orders yet">
            New orders will appear here as customers request stock.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination page={@page_info} path={~p"/distributor/orders"} />
    </Layouts.distributor_shell>
    """
  end
end
