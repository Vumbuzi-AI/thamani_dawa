defmodule ThamaniDawaWeb.DistributorInvoiceLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.DistributorInvoices
  alias ThamaniDawa.DistributorInvoices.Payment
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:invoice, nil)
     |> assign(:payment_form, nil)}
  end

  def handle_params(%{"id" => id} = params, _url, socket) do
    org_id = socket.assigns.current_scope.organization_id
    invoice = DistributorInvoices.get_invoice!(org_id, id)
    balance = DistributorInvoices.invoice_balance(invoice)
    status = DistributorInvoices.invoice_status(invoice)

    payment_form =
      if status != :paid do
        to_form(Payment.changeset(%Payment{}, %{}), as: :payment)
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:invoice, invoice)
     |> assign(:balance, balance)
     |> assign(:invoice_status, status)
     |> assign(
       :line_page,
       DistributorPagination.page(
         invoice.lines,
         DistributorPagination.page_number(params, "lines_page")
       )
     )
     |> assign(
       :payment_page,
       DistributorPagination.page(
         invoice.payments,
         DistributorPagination.page_number(params, "payments_page")
       )
     )
     |> assign(:payment_form, payment_form)
     |> assign(:page_title, "Invoice ##{invoice.id}")}
  end

  def handle_event("validate_payment", %{"payment" => params}, socket) do
    changeset =
      %Payment{}
      |> Payment.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :payment_form, to_form(changeset, as: :payment))}
  end

  def handle_event("record_payment", %{"payment" => params}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    invoice = socket.assigns.invoice

    case DistributorInvoices.record_payment(org_id, invoice, params) do
      {:ok, _payment} ->
        reloaded = DistributorInvoices.get_invoice!(org_id, invoice.id)
        balance = DistributorInvoices.invoice_balance(reloaded)
        status = DistributorInvoices.invoice_status(reloaded)

        payment_form =
          if status != :paid do
            to_form(Payment.changeset(%Payment{}, %{}), as: :payment)
          else
            nil
          end

        {:noreply,
         socket
         |> put_flash(:info, "Payment recorded.")
         |> assign(:invoice, reloaded)
         |> assign(:balance, balance)
         |> assign(:invoice_status, status)
         |> assign(
           :line_page,
           DistributorPagination.page(reloaded.lines, socket.assigns.line_page.page_number)
         )
         |> assign(
           :payment_page,
           DistributorPagination.page(
             reloaded.payments,
             socket.assigns.payment_page.page_number
           )
         )
         |> assign(:payment_form, payment_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, :payment_form, to_form(changeset, as: :payment))}
    end
  end

  defp money(amount), do: "KES #{amount}"

  defp invoice_total(invoice) do
    Enum.reduce(invoice.lines, 0, fn line, acc -> acc + line.quantity * line.unit_price end)
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/invoices"}
    >
      <.header icon="hero-document-text">
        {@page_title}
        <:subtitle>
          <.link navigate={~p"/distributor/invoices"} class="text-thamani-forest hover:underline">
            ← Back to invoices
          </.link>
        </:subtitle>
      </.header>

      <%!-- Invoice header card --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white p-6 shadow-sm">
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Customer</p>
            <p class="mt-1 text-sm font-semibold text-thamani-forest">{@invoice.customer.name}</p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Order</p>
            <p class="mt-1 text-sm text-thamani-forest">
              <.link
                navigate={~p"/distributor/orders/#{@invoice.order.id}"}
                class="hover:underline font-medium"
              >
                Order #{@invoice.order.id}
              </.link>
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Issued at</p>
            <p class="mt-1 text-sm text-thamani-forest">
              {Calendar.strftime(@invoice.inserted_at, "%d %b %Y, %H:%M")}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Status</p>
            <div class="mt-1">
              <.status_badge status={@invoice_status} />
            </div>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Total</p>
            <p class="mt-1 text-sm font-semibold text-thamani-forest">
              {money(invoice_total(@invoice))}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-pewter">Balance due</p>
            <p class={[
              "mt-1 text-sm font-bold",
              if(@balance > 0, do: "text-rose-700", else: "text-green-700")
            ]}>
              {money(@balance)}
            </p>
          </div>
        </div>
      </div>

      <%!-- Invoice lines table --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white shadow-sm overflow-hidden">
        <div class="border-b border-thamani-stone px-6 py-4">
          <h2 class="text-sm font-semibold text-thamani-forest">Invoice lines</h2>
        </div>
        <table class="min-w-full divide-y divide-thamani-stone">
          <thead class="bg-thamani-stone/30">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Product
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Qty
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Unit price
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                Line total
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-thamani-stone">
            <%= for line <- @line_page.entries do %>
              <tr class="hover:bg-thamani-stone/10 transition-colors">
                <td class="px-6 py-4 text-sm text-thamani-forest">
                  {line.product.generic_name || line.product.brand_name}
                </td>
                <td class="px-6 py-4 text-sm text-right text-thamani-forest">{line.quantity}</td>
                <td class="px-6 py-4 text-sm text-right text-thamani-forest">
                  {money(line.unit_price)}
                </td>
                <td class="px-6 py-4 text-sm text-right font-medium text-thamani-forest">
                  {money(line.quantity * line.unit_price)}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <.pagination
          page={@line_page}
          path={~p"/distributor/invoices/#{@invoice.id}"}
          query_param="lines_page"
        />
      </div>

      <%!-- Payments section --%>
      <div class="mt-6 rounded-2xl border border-thamani-stone bg-white shadow-sm overflow-hidden">
        <div class="border-b border-thamani-stone px-6 py-4">
          <h2 class="text-sm font-semibold text-thamani-forest">Payments</h2>
        </div>

        <%= if @payment_page.total_entries == 0 do %>
          <div class="px-6 py-8 text-center text-sm text-thamani-pewter">
            No payments recorded yet.
          </div>
        <% else %>
          <table class="min-w-full divide-y divide-thamani-stone">
            <thead class="bg-thamani-stone/30">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Method
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Note
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-thamani-stone">
              <%= for payment <- @payment_page.entries do %>
                <tr>
                  <td class="px-6 py-4 text-sm text-thamani-forest">
                    {Calendar.strftime(payment.inserted_at, "%d %b %Y, %H:%M")}
                  </td>
                  <td class="px-6 py-4 text-sm text-thamani-forest capitalize">{payment.method}</td>
                  <td class="px-6 py-4 text-sm text-right font-medium text-thamani-forest">
                    {money(payment.amount)}
                  </td>
                  <td class="px-6 py-4 text-sm text-thamani-pewter">{payment.note || "—"}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <.pagination
            page={@payment_page}
            path={~p"/distributor/invoices/#{@invoice.id}"}
            query_param="payments_page"
          />
        <% end %>
      </div>

      <%!-- Payment form (only if not fully paid) --%>
      <%= if @invoice_status != :paid and @payment_form != nil do %>
        <div class="mt-6 rounded-2xl border border-thamani-stone bg-white p-6 shadow-sm">
          <h2 class="text-sm font-semibold text-thamani-forest">Record a payment</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Balance remaining: <span class="font-semibold text-rose-700">{money(@balance)}</span>
          </p>

          <.form
            for={@payment_form}
            id="payment-form"
            phx-change="validate_payment"
            phx-submit="record_payment"
            class="mt-4 grid gap-4 sm:grid-cols-2"
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
              <.input
                field={@payment_form[:note]}
                type="textarea"
                label="Note (optional)"
              />
            </div>
            <div class="sm:col-span-2 flex justify-end">
              <.button id="record-payment-btn" variant="primary">
                <.icon name="hero-banknotes" class="size-4" /> Record payment
              </.button>
            </div>
          </.form>
        </div>
      <% end %>
    </Layouts.distributor_shell>
    """
  end
end
