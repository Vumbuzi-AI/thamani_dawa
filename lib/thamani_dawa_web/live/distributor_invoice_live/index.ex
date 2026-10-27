defmodule ThamaniDawaWeb.DistributorInvoiceLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.DistributorInvoices
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id

    invoices =
      org_id
      |> DistributorInvoices.list_invoices()
      |> Enum.map(fn invoice ->
        balance = DistributorInvoices.invoice_balance(invoice)
        status = DistributorInvoices.invoice_status(invoice)
        %{invoice: invoice, balance: balance, status: status}
      end)

    {:ok, assign(socket, all_invoices: invoices, page_title: "Invoices")}
  end

  def handle_params(params, _url, socket) do
    page_info =
      DistributorPagination.page(
        socket.assigns.all_invoices,
        DistributorPagination.page_number(params)
      )

    {:noreply, assign(socket, invoices: page_info.entries, page_info: page_info)}
  end

  defp money(amount), do: "KES #{amount}"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/invoices"}
    >
      <.header icon="hero-document-text">
        Invoices
        <:subtitle>Invoices are generated automatically when an order is dispatched.</:subtitle>
      </.header>

      <%= if @invoices == [] do %>
        <.blank_state icon="hero-document-text" title="No invoices yet">
          Invoices will appear here once orders have been dispatched.
        </.blank_state>
      <% else %>
        <div class="mt-6 rounded-2xl border border-thamani-stone bg-white shadow-sm overflow-hidden">
          <table class="min-w-full divide-y divide-thamani-stone">
            <thead class="bg-thamani-stone/30">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Invoice #
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Customer
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Order #
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Total
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Balance
                </th>
                <th class="px-6 py-3 text-center text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                  Status
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium uppercase tracking-wide text-thamani-pewter">
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-thamani-stone">
              <%= for %{invoice: invoice, balance: balance, status: status} <- @invoices do %>
                <tr class="hover:bg-thamani-stone/10 transition-colors">
                  <td class="px-6 py-4 text-sm font-medium text-thamani-forest">#{invoice.id}</td>
                  <td class="px-6 py-4 text-sm text-thamani-forest">{invoice.customer.name}</td>
                  <td class="px-6 py-4 text-sm text-thamani-forest">
                    <.link
                      navigate={~p"/distributor/orders/#{invoice.order.id}"}
                      class="hover:underline"
                    >
                      Order #{invoice.order.id}
                    </.link>
                  </td>
                  <td class="px-6 py-4 text-sm text-right text-thamani-forest">
                    {money(invoice.total_amount)}
                  </td>
                  <td class="px-6 py-4 text-sm text-right font-medium text-thamani-forest">
                    {money(balance)}
                  </td>
                  <td class="px-6 py-4 text-center">
                    <.status_badge status={status} />
                  </td>
                  <td class="px-6 py-4 text-right">
                    <.link
                      navigate={~p"/distributor/invoices/#{invoice.id}"}
                      class="text-sm font-medium text-thamani-forest hover:underline"
                    >
                      View →
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
      <.pagination page={@page_info} path={~p"/distributor/invoices"} />
    </Layouts.distributor_shell>
    """
  end
end
