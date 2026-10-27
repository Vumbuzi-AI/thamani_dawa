defmodule ThamaniDawaWeb.DistributorOrderLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.DistributorInvoices
  alias ThamaniDawa.DistributorInvoices.Payment
  alias ThamaniDawa.DistributorOrders
  alias ThamaniDawa.DistributorShipments
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id

    warehouses =
      org_id
      |> Sites.list_sites()
      |> Enum.filter(&(&1.site_type == :warehouse and &1.is_active))

    {:ok, assign(socket, :warehouses, warehouses)}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    org_id = socket.assigns.current_scope.organization_id
    order = DistributorOrders.get_order!(org_id, id)

    warehouses = socket.assigns.warehouses

    first_warehouse_id =
      case warehouses do
        [w | _] -> w.id
        [] -> nil
      end

    selected_warehouse_id = first_warehouse_id

    stock_preview =
      if order.status == :pending do
        compute_stock_preview(org_id, order, selected_warehouse_id)
      else
        %{}
      end

    allocate_form = to_form(%{"warehouse_id" => selected_warehouse_id}, as: :allocate)

    {invoice, invoice_balance, invoice_status} = load_invoice(org_id, order)
    payment_form = build_payment_form(invoice_status)

    {:noreply,
     socket
     |> assign(:order, order)
     |> assign(:page_title, "Order ##{order.id}")
     |> assign(:selected_warehouse_id, selected_warehouse_id)
     |> assign(:stock_preview, stock_preview)
     |> assign(:allocating_item_id, nil)
     |> assign(:batch_picks, [])
     |> assign(:invoice, invoice)
     |> assign(:invoice_balance, invoice_balance)
     |> assign(:invoice_status, invoice_status)
     |> assign(:payment_form, payment_form)
     |> assign(:allocate_form, allocate_form)}
  end

  def handle_event("validate_payment", %{"payment" => params}, socket) do
    changeset = %Payment{} |> Payment.changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :payment_form, to_form(changeset, as: :payment))}
  end

  def handle_event("record_payment", %{"payment" => params}, socket) do
    org_id = socket.assigns.current_scope.organization_id

    case DistributorInvoices.record_payment(org_id, socket.assigns.invoice, params) do
      {:ok, _payment} ->
        invoice = DistributorInvoices.get_invoice!(org_id, socket.assigns.invoice.id)
        balance = DistributorInvoices.invoice_balance(invoice)
        status = DistributorInvoices.invoice_status(invoice)

        {:noreply,
         socket
         |> assign(:invoice, invoice)
         |> assign(:invoice_balance, balance)
         |> assign(:invoice_status, status)
         |> assign(:payment_form, build_payment_form(status))
         |> put_flash(:info, "Payment recorded.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :payment_form, to_form(changeset, as: :payment))}
    end
  end

  def handle_event(
        "select_warehouse",
        %{"allocate" => %{"warehouse_id" => warehouse_id}},
        socket
      ) do
    org_id = socket.assigns.current_scope.organization_id
    order = socket.assigns.order

    warehouse_id = parse_warehouse_id(warehouse_id)

    stock_preview = compute_stock_preview(org_id, order, warehouse_id)
    allocate_form = to_form(%{"warehouse_id" => warehouse_id}, as: :allocate)

    {:noreply,
     socket
     |> assign(:selected_warehouse_id, warehouse_id)
     |> assign(:stock_preview, stock_preview)
     |> assign(:allocate_form, allocate_form)}
  end

  def handle_event("open_allocate", %{"item_id" => item_id}, socket) do
    item = Enum.find(socket.assigns.order.items, &(&1.id == String.to_integer(item_id)))

    picks =
      Batches.preview_fefo_allocation(
        socket.assigns.current_scope.organization_id,
        socket.assigns.selected_warehouse_id,
        item.product_id,
        item.quantity
      )

    {:noreply, assign(socket, allocating_item_id: item.id, batch_picks: picks)}
  end

  def handle_event(
        "confirm_item_allocation",
        %{"item_id" => item_id, "quantities" => quantities},
        socket
      ) do
    item = Enum.find(socket.assigns.order.items, &(&1.id == String.to_integer(item_id)))

    picks =
      Enum.map(quantities, fn {batch_id, quantity} ->
        %{
          batch_id: String.to_integer(batch_id),
          quantity: String.to_integer(if(quantity == "", do: "0", else: quantity))
        }
      end)

    case DistributorShipments.allocate_order_item(
           socket.assigns.current_scope.organization_id,
           socket.assigns.order,
           item,
           socket.assigns.selected_warehouse_id,
           picks
         ) do
      {:ok, _} ->
        order =
          DistributorOrders.get_order!(
            socket.assigns.current_scope.organization_id,
            socket.assigns.order.id
          )

        {:noreply,
         socket
         |> assign(order: order, allocating_item_id: nil, batch_picks: [])
         |> put_flash(:info, "Allocation saved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Allocation could not be saved.")}
    end
  end

  def handle_event(
        "allocate",
        %{"allocate" => %{"warehouse_id" => warehouse_id}},
        socket
      ) do
    org_id = socket.assigns.current_scope.organization_id
    order = socket.assigns.order

    if order.status != :pending do
      {:noreply, put_flash(socket, :error, "Only pending orders can be allocated.")}
    else
      case DistributorShipments.allocate_order(
             org_id,
             order,
             parse_warehouse_id(warehouse_id)
           ) do
        {:ok, {_shipment, _carton}} ->
          reloaded = DistributorOrders.get_order!(org_id, order.id)

          {:noreply,
           socket
           |> put_flash(:info, "Stock allocated. Review allocation then dispatch.")
           |> assign(:order, reloaded)
           |> push_navigate(to: ~p"/distributor/orders/#{order.id}")}

        {:error, :not_pending} ->
          {:noreply, put_flash(socket, :error, "Order is not pending.")}

        {:error, :missing_gs1_company_prefix} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "GS1 Company Prefix not configured. Set it in organization settings before allocating."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Allocation failed. Please try again.")}
      end
    end
  end

  def handle_event("dispatch", _params, socket) do
    org_id = socket.assigns.current_scope.organization_id
    order = socket.assigns.order

    if order.status != :allocated do
      {:noreply, put_flash(socket, :error, "Only allocated orders can be dispatched.")}
    else
      case DistributorShipments.dispatch_order(org_id, order) do
        {:ok, {_shipment, invoice}} ->
          reloaded = DistributorOrders.get_order!(org_id, order.id)

          {:noreply,
           socket
           |> put_flash(:info, "Order dispatched. Invoice ##{invoice.number} generated.")
           |> assign(:order, reloaded)
           |> push_navigate(to: ~p"/distributor/orders/#{order.id}")}

        {:error, :not_allocated} ->
          {:noreply, put_flash(socket, :error, "Order has not been allocated yet.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Dispatch failed. Please try again.")}
      end
    end
  end

  defp parse_warehouse_id(""), do: nil
  defp parse_warehouse_id(nil), do: nil
  defp parse_warehouse_id(id) when is_integer(id), do: id

  defp parse_warehouse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {warehouse_id, ""} -> warehouse_id
      _ -> nil
    end
  end

  defp parse_warehouse_id(_id), do: nil

  defp compute_stock_preview(_org_id, _order, nil), do: %{}

  defp compute_stock_preview(org_id, order, warehouse_id) do
    Enum.reduce(order.items, %{}, fn item, acc ->
      allocations =
        Batches.preview_fefo_allocation(org_id, warehouse_id, item.product_id, item.quantity)

      can_fulfill = Enum.reduce(allocations, 0, fn alloc, sum -> sum + alloc.quantity end)

      Map.put(acc, item.id, %{can_fulfill: can_fulfill, needed: item.quantity})
    end)
  end

  defp load_invoice(_org_id, %{invoice: nil}), do: {nil, nil, nil}

  defp load_invoice(org_id, order) do
    invoice = DistributorInvoices.get_invoice!(org_id, order.invoice.id)

    {invoice, DistributorInvoices.invoice_balance(invoice),
     DistributorInvoices.invoice_status(invoice)}
  end

  defp build_payment_form(:paid), do: nil

  defp build_payment_form(_status) do
    to_form(Payment.changeset(%Payment{}, %{}), as: :payment)
  end

  defp money(amount), do: "KES #{amount}"

  defp order_total(order) do
    Enum.reduce(order.items, 0, fn item, total -> total + item.quantity * item.unit_price end)
  end

  defp fulfill_icon(can_fulfill, needed) when can_fulfill >= needed, do: :ok
  defp fulfill_icon(can_fulfill, _needed) when can_fulfill > 0, do: :partial
  defp fulfill_icon(_can_fulfill, _needed), do: :none

  defp allocation_icon(allocated, ordered) when allocated >= ordered, do: :full
  defp allocation_icon(allocated, _ordered) when allocated > 0, do: :partial
  defp allocation_icon(_allocated, _ordered), do: :none

  defp first_sscc(order) do
    case order.shipment do
      %{cartons: [carton | _]} -> carton.sscc
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/orders"}
    >
      <.header icon="hero-clipboard-document-list">
        {@page_title}
        <:subtitle>
          <.link navigate={~p"/distributor/orders"} class="text-thamani-forest hover:underline">
            ← Back to orders
          </.link>
        </:subtitle>
      </.header>

      <%!-- Order header card --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white p-6 shadow-sm">
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Customer</p>
            <p class="mt-1 text-sm font-semibold text-thamani-forest">{@order.customer.name}</p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">
              Delivery address
            </p>
            <p class="mt-1 text-sm text-thamani-forest">
              {if @order.delivery_address && @order.delivery_address != "",
                do: @order.delivery_address,
                else: "—"}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Ordered at</p>
            <p class="mt-1 text-sm text-thamani-forest">
              {Calendar.strftime(@order.ordered_at, "%d %b %Y, %H:%M")}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Status</p>
            <div class="mt-1">
              <.status_badge status={@order.status} />
            </div>
          </div>
        </div>
      </div>

      <%= if @invoice do %>
        <div class="mt-6 rounded-2xl border border-thamani-stone bg-white p-6 shadow-sm">
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h2 class="text-sm font-semibold text-thamani-forest">Invoice #{@invoice.number}</h2>
              <p class="mt-1 text-sm text-thamani-pewter">
                Issued {Calendar.strftime(@invoice.issued_at, "%d %b %Y, %H:%M")}
              </p>
            </div>
            <.status_badge status={@invoice_status} />
          </div>
          <div class="mt-5 grid gap-4 sm:grid-cols-2">
            <div>
              <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Invoice total
              </p>
              <p class="mt-1 text-sm font-semibold text-thamani-forest">{money(@invoice.total)}</p>
            </div>
            <div>
              <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Balance due
              </p>
              <p class={[
                "mt-1 text-sm font-semibold",
                if(@invoice_balance > 0, do: "text-rose-700", else: "text-green-700")
              ]}>
                {money(@invoice_balance)}
              </p>
            </div>
          </div>

          <details class="mt-5 border-t border-thamani-stone pt-4">
            <summary class="cursor-pointer text-sm font-semibold text-thamani-forest hover:text-thamani-moss">
              View invoice details
            </summary>
            <div class="mt-4 overflow-x-auto rounded-lg border border-thamani-stone">
              <table class="min-w-full divide-y divide-thamani-stone text-sm">
                <thead class="bg-thamani-stone/30 text-xs uppercase tracking-wide text-thamani-pewter">
                  <tr>
                    <th class="px-4 py-2 text-left font-medium">Product</th>
                    <th class="px-4 py-2 text-right font-medium">Quantity</th>
                    <th class="px-4 py-2 text-right font-medium">Unit price</th>
                    <th class="px-4 py-2 text-right font-medium">Total</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-thamani-stone">
                  <tr :for={line <- @invoice.lines}>
                    <td class="px-4 py-2 text-thamani-forest">
                      {line.product.generic_name || line.product.brand_name}
                    </td>
                    <td class="px-4 py-2 text-right text-thamani-forest">{line.quantity}</td>
                    <td class="px-4 py-2 text-right text-thamani-forest">{money(line.unit_price)}</td>
                    <td class="px-4 py-2 text-right font-medium text-thamani-forest">
                      {money(line.line_total)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Payments</p>
              <p :if={@invoice.payments == []} class="mt-1 text-sm text-thamani-pewter">
                No payments recorded yet.
              </p>
              <div
                :for={payment <- @invoice.payments}
                class="mt-2 flex flex-wrap justify-between gap-2 text-sm"
              >
                <span class="text-thamani-forest">
                  {Calendar.strftime(payment.paid_at, "%d %b %Y")} · {payment.method}
                </span>
                <span class="font-medium text-thamani-forest">{money(payment.amount)}</span>
              </div>
            </div>
          </details>

          <div :if={@payment_form} class="mt-5 border-t border-thamani-stone pt-4">
            <h3 class="text-sm font-semibold text-thamani-forest">Record a payment</h3>
            <.form
              for={@payment_form}
              id="order-payment-form"
              phx-change="validate_payment"
              phx-submit="record_payment"
              class="mt-3 grid gap-4 sm:grid-cols-2"
            >
              <.input
                field={@payment_form[:amount]}
                type="number"
                label="Amount (KES)"
                min="1"
                required
              />
              <.input
                field={@payment_form[:method]}
                type="select"
                label="Payment method"
                prompt="Select method"
                options={["Cash", "M-Pesa", "Bank Transfer"]}
                required
              />
              <div class="sm:col-span-2">
                <.input field={@payment_form[:note]} type="textarea" label="Note (optional)" />
              </div>
              <div class="sm:col-span-2 flex justify-end">
                <.button id="order-record-payment-btn" variant="primary">
                  <.icon name="hero-banknotes" class="size-4" /> Record payment
                </.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Order items table --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white shadow-sm overflow-hidden">
        <div class="border-b border-thamani-stone px-6 py-4">
          <h2 class="text-sm font-semibold text-thamani-forest">Order items</h2>
        </div>
        <table class="min-w-full divide-y divide-thamani-stone">
          <thead class="bg-thamani-stone/30">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Product
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Qty ordered
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Unit price
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Subtotal
              </th>
              <%= if @order.status == :pending and @selected_warehouse_id != nil do %>
                <th class="px-6 py-3 text-center text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Stock
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Action
                </th>
              <% end %>
              <%= if @order.status == :allocated do %>
                <th class="px-6 py-3 text-center text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Allocated
                </th>
              <% end %>
            </tr>
          </thead>
          <tbody class="divide-y divide-thamani-stone">
            <%= for item <- @order.items do %>
              <tr class="hover:bg-thamani-stone/10 transition-colors">
                <td class="px-6 py-4 text-sm text-thamani-forest">
                  {item.product.generic_name || item.product.brand_name}
                </td>
                <td class="px-6 py-4 text-sm text-right text-thamani-forest">{item.quantity}</td>
                <td class="px-6 py-4 text-sm text-right text-thamani-forest">
                  {money(item.unit_price)}
                </td>
                <td class="px-6 py-4 text-sm text-right font-medium text-thamani-forest">
                  {money(item.quantity * item.unit_price)}
                </td>
                <%= if @order.status == :pending and @selected_warehouse_id != nil do %>
                  <td class="px-6 py-4 text-center">
                    <%= case Map.get(@stock_preview, item.id) do %>
                      <% nil -> %>
                        <span class="text-thamani-pewter text-xs">—</span>
                      <% %{can_fulfill: can_fulfill, needed: needed} -> %>
                        <%= case fulfill_icon(can_fulfill, needed) do %>
                          <% :ok -> %>
                            <span class="inline-flex items-center gap-1 text-xs font-medium text-green-700">
                              <.icon name="hero-check-circle" class="size-4 text-green-600" /> {can_fulfill}/{needed}
                            </span>
                          <% :partial -> %>
                            <span class="inline-flex items-center gap-1 text-xs font-medium text-amber-700">
                              <.icon
                                name="hero-exclamation-triangle"
                                class="size-4 text-amber-500"
                              /> {can_fulfill}/{needed}
                            </span>
                          <% :none -> %>
                            <span class="inline-flex items-center gap-1 text-xs font-medium text-rose-700">
                              <.icon name="hero-x-circle" class="size-4 text-rose-500" /> 0/{needed}
                            </span>
                        <% end %>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 text-right">
                    <.button
                      :if={not item.allocation_processed and @allocating_item_id != item.id}
                      phx-click="open_allocate"
                      phx-value-item_id={item.id}
                      variant={
                        if(Map.get(@stock_preview, item.id, %{can_fulfill: 0}).can_fulfill == 0,
                          do: "ghost",
                          else: "ghost-edit"
                        )
                      }
                      class={[
                        "px-3 py-1.5 text-xs",
                        Map.get(@stock_preview, item.id, %{can_fulfill: 0}).can_fulfill == 0 &&
                          "cursor-not-allowed opacity-45"
                      ]}
                      disabled={Map.get(@stock_preview, item.id, %{can_fulfill: 0}).can_fulfill == 0}
                      title={
                        if(Map.get(@stock_preview, item.id, %{can_fulfill: 0}).can_fulfill == 0,
                          do: "No stock is available for this product.",
                          else: nil
                        )
                      }
                    >Allocate</.button>
                  </td>
                <% end %>
                <%= if @order.status == :allocated do %>
                  <td class="px-6 py-4 text-center">
                    <%= case allocation_icon(item.quantity_allocated, item.quantity) do %>
                      <% :full -> %>
                        <span class="inline-flex items-center gap-1 text-xs font-medium text-green-700">
                          <.icon name="hero-check-circle" class="size-4 text-green-600" />
                          {item.quantity_allocated}/{item.quantity}
                        </span>
                      <% :partial -> %>
                        <span class="inline-flex items-center gap-1 text-xs font-medium text-amber-700">
                          <.icon name="hero-exclamation-triangle" class="size-4 text-amber-500" />
                          {item.quantity_allocated}/{item.quantity}
                          <span class="text-amber-600">(shortfall: {item.quantity -
                            item.quantity_allocated})</span>
                        </span>
                      <% :none -> %>
                        <span class="inline-flex items-center gap-1 text-xs font-medium text-rose-700">
                          <.icon name="hero-x-circle" class="size-4 text-rose-500" />
                          0/{item.quantity}
                          <span class="text-rose-600">(no stock)</span>
                        </span>
                    <% end %>
                  </td>
                <% end %>
              </tr>
              <tr :if={@allocating_item_id == item.id} class="bg-thamani-canvas">
                <td colspan="6" class="px-6 py-4">
                  <.form
                    for={to_form(%{}, as: :allocation)}
                    id={"allocate-item-#{item.id}"}
                    phx-submit="confirm_item_allocation"
                    phx-value-item_id={item.id}
                    class="rounded-xl border border-thamani-stone bg-white p-4"
                  >
                    <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                      Available batches · earliest expiry first
                    </p>
                    <div
                      :for={allocation <- @batch_picks}
                      class="mb-2 grid grid-cols-[minmax(0,1fr)_6rem] items-center gap-4 rounded-lg border border-thamani-stone bg-thamani-canvas p-3"
                    >
                      <div class="min-w-0">
                        <p class="truncate text-sm font-medium text-thamani-forest">
                          Batch {allocation.batch.batch_no}
                        </p>
                        <p class="mt-0.5 text-xs text-thamani-pewter">
                          Expires {allocation.batch.expiry_date} · {allocation.batch.remaining_quantity} in stock
                        </p>
                      </div>
                      <input
                        type="number"
                        name={"quantities[#{allocation.batch.id}]"}
                        value={allocation.quantity}
                        min="0"
                        max={allocation.batch.remaining_quantity}
                        class="w-full rounded-lg border border-thamani-stone px-2 py-1.5 text-right text-sm"
                      />
                    </div>
                    <.button variant="primary" class="mt-2 w-full">Confirm allocation</.button>
                  </.form>
                </td>
              </tr>
            <% end %>
          </tbody>
          <tfoot>
            <tr class="bg-thamani-stone/20">
              <td
                colspan={
                  cond do
                    @order.status == :pending and @selected_warehouse_id != nil -> "4"
                    @order.status == :allocated -> "4"
                    true -> "3"
                  end
                }
                class="px-6 py-4 text-sm font-semibold text-right text-thamani-forest"
              >
                Order total
              </td>
              <td class="px-6 py-4 text-sm font-bold text-right text-thamani-forest">
                {money(order_total(@order))}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      <%!-- Allocate section (pending orders only) --%>
      <%= if false do %>
        <div class="hidden">
          <h2 class="text-sm font-semibold text-thamani-forest">Allocate stock</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Allocate each line from the earliest-expiring available batch.
          </p>

          <%= if @warehouses == [] do %>
            <p class="mt-4 rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-800">
              No active warehouses found. Please add a warehouse before allocating.
            </p>
          <% else %>
            <div class="mt-4 space-y-3">
              <div :for={item <- @order.items} class="rounded-xl border border-thamani-stone p-4">
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <p class="font-medium text-thamani-forest">
                      {item.product.generic_name || item.product.brand_name}
                    </p><p class="text-sm text-thamani-pewter">
                      {item.quantity_allocated} / {item.quantity} allocated
                    </p>
                  </div>
                  <.button
                    :if={not item.allocation_processed and @allocating_item_id != item.id}
                    phx-click="open_allocate"
                    phx-value-item_id={item.id}
                  >Allocate</.button>
                </div>
                <.form
                  :if={@allocating_item_id == item.id}
                  for={to_form(%{}, as: :allocation)}
                  id={"allocate-item-#{item.id}"}
                  phx-submit="confirm_item_allocation"
                  phx-value-item_id={item.id}
                  class="mt-4 rounded-xl border border-thamani-stone bg-thamani-canvas p-4"
                >
                  <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                    Available batches · earliest expiry first
                  </p>
                  <div
                    :for={allocation <- @batch_picks}
                    class="mb-2 flex items-center justify-between rounded-lg border border-thamani-stone bg-white p-3"
                  >
                    <span>Batch {allocation.batch.batch_no} · expires {allocation.batch.expiry_date}</span><input
                      type="number"
                      name={"quantities[#{allocation.batch.id}]"}
                      value={allocation.quantity}
                      min="0"
                      max={allocation.batch.remaining_quantity}
                      class="w-24 rounded-lg border border-thamani-stone px-2 py-1 text-right"
                    />
                  </div>
                  <.button variant="primary" class="mt-2 w-full">Confirm allocation</.button>
                </.form>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Allocated panel (allocated orders only) --%>
      <%= if @order.status == :allocated do %>
        <div class="mt-6 rounded-2xl border border-blue-200 bg-blue-50 p-6 shadow-sm">
          <div class="flex items-start gap-3">
            <.icon
              name="hero-archive-box-arrow-down"
              class="mt-0.5 size-5 text-blue-600 shrink-0"
            />
            <div class="flex-1">
              <p class="text-sm font-semibold text-blue-800">
                Stock allocated — ready to dispatch.
              </p>

              <%!-- SSCC label --%>
              <%= if first_sscc(@order) do %>
                <div class="mt-5 flex flex-wrap items-start gap-4">
                  <section
                    id={"sscc-label-#{@order.shipment.id}"}
                    class="printable-sscc-label w-full max-w-md border-2 border-black bg-white p-4 text-black shadow-sm"
                    aria-label={"SSCC logistics label for shipment #{@order.shipment.id}"}
                  >
                    <header class="flex items-start justify-between border-b-2 border-black pb-3">
                      <div>
                        <p class="text-base font-bold uppercase tracking-wide">Thamani Dawa</p>
                        <p class="mt-0.5 text-xs">Distribution shipment</p>
                      </div>
                      <div class="text-right text-xs">
                        <p class="font-bold uppercase">Shipment</p>
                        <p>#{@order.shipment.id}</p>
                      </div>
                    </header>

                    <div class="grid grid-cols-2 gap-4 border-b border-black py-3 text-xs">
                      <div>
                        <p class="font-bold uppercase">From</p>
                        <p class="mt-1 font-semibold">{@order.shipment.warehouse.name}</p>
                        <p class="leading-relaxed">{@order.shipment.warehouse.address}</p>
                      </div>
                      <div>
                        <p class="font-bold uppercase">Ship to</p>
                        <p class="mt-1 font-semibold">{@order.customer.name}</p>
                        <p class="leading-relaxed">{@order.shipment.destination}</p>
                      </div>
                    </div>

                    <div class="py-3">
                      <p class="text-xs font-bold uppercase tracking-wide">
                        Serial shipping container code
                      </p>
                      <canvas
                        id={"sscc-barcode-#{@order.shipment.id}"}
                        phx-hook="SsccBarcode"
                        phx-update="ignore"
                        data-sscc={first_sscc(@order)}
                        class="mt-2 h-24 w-full bg-white"
                      ></canvas>
                      <p class="mt-1 text-center font-mono text-sm font-semibold tracking-[0.16em]">
                        (00) {first_sscc(@order)}
                      </p>
                    </div>
                  </section>

                  <.button
                    type="button"
                    variant="ghost-edit"
                    onclick="window.print()"
                    class="no-print shrink-0"
                  >
                    <.icon name="hero-printer" class="size-4" /> Print label
                  </.button>
                </div>
              <% end %>

              <%!-- Partial allocation notice --%>
              <%= if Enum.any?(@order.items, &(&1.quantity_allocated < &1.quantity)) do %>
                <div class="mt-4 rounded-lg bg-amber-50 border border-amber-200 px-4 py-3">
                  <p class="text-sm font-medium text-amber-800">
                    <.icon name="hero-exclamation-triangle" class="size-4 inline mr-1" />
                    Partial allocation — some items have insufficient stock. The invoice will reflect only the allocated quantities.
                  </p>
                </div>
              <% end %>

              <div class="mt-4">
                <.button
                  id="dispatch-btn"
                  phx-click="dispatch"
                  variant="primary"
                >
                  <.icon name="hero-truck" class="size-4" /> Dispatch now
                </.button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Dispatched success banner --%>
      <%= if @order.status == :dispatched do %>
        <div class="mt-6 rounded-2xl border border-green-200 bg-green-50 p-6">
          <div class="flex items-start gap-3">
            <.icon name="hero-check-circle" class="mt-0.5 size-5 text-green-600 shrink-0" />
            <div class="flex-1">
              <p class="text-sm font-semibold text-green-800">This order has been dispatched.</p>
              <div class="mt-3 flex flex-wrap gap-3">
                <%= if @order.shipment do %>
                  <.link
                    navigate={~p"/distributor/shipments/#{@order.shipment.id}"}
                    class="inline-flex items-center gap-1.5 rounded-lg bg-white border border-green-200 px-3 py-1.5 text-sm font-medium text-green-800 hover:bg-green-100 transition-colors"
                  >
                    <.icon name="hero-truck" class="size-4" /> View Shipment
                  </.link>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.distributor_shell>
    """
  end
end
