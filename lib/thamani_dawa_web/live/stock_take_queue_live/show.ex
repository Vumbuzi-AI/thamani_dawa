defmodule ThamaniDawaWeb.StockTakeQueueLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.StockTakes

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    stock_take = StockTakes.get_stock_take!(organization_id, id)
    products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})
    site = Sites.get_site!(organization_id, stock_take.site_id)

    {:ok,
     socket
     |> assign(:stock_take, stock_take)
     |> assign(:site, site)
     |> assign(:products_by_id, products_by_id)}
  end

  def handle_event("approve", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    admin_id = socket.assigns.current_scope.user.id
    stock_take = socket.assigns.stock_take

    case StockTakes.approve_stock_take(organization_id, stock_take.id, admin_id) do
      {:ok, _approved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock take approved. Batch quantities updated.")
         |> push_navigate(to: ~p"/org/stock-takes")}

      {:error, :not_approvable} ->
        {:noreply, put_flash(socket, :error, "That stock take can no longer be approved.")}
    end
  end

  defp product_name(products_by_id, product_id) do
    case Map.get(products_by_id, product_id) do
      nil -> "(unknown product)"
      product -> product.generic_name || product.brand_name || "(unnamed)"
    end
  end

  defp person_name(nil), do: "—"
  defp person_name(user), do: user.name

  defp requester_label(%{admin_id: admin_id, admin: admin}) when not is_nil(admin_id),
    do: "#{person_name(admin)} (admin)"

  defp requester_label(%{requested_by: requested_by}), do: person_name(requested_by)

  defp variance_class(nil), do: ""
  defp variance_class(0), do: "text-slate-500"
  defp variance_class(v) when v > 0, do: "text-emerald-600 font-medium"
  defp variance_class(_), do: "text-rose-600 font-medium"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/stock-takes">
      <.header icon="hero-clipboard-document-list">
        Stock take — {@site.name}
        <:subtitle>{Phoenix.Naming.humanize(@stock_take.inventory_type)} count details.</:subtitle>
        <:actions>
          <.button
            :if={@stock_take.status in [:draft, :pending]}
            variant="primary"
            phx-click="approve"
            phx-disable-with="Approving…"
          >
            Approve
          </.button>
          <.button
            :if={@stock_take.status == :pending}
            variant="ghost"
            navigate={~p"/org/stock-takes/#{@stock_take.id}/reject"}
          >
            Reject
          </.button>
          <.button variant="ghost" navigate={~p"/org/stock-takes"}>
            <.icon name="hero-arrow-left" class="size-4" /> Stock takes
          </.button>
        </:actions>
      </.header>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Status</dt>
            <dd class="mt-1"><.status_badge status={@stock_take.status} /></dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Requested by
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{requester_label(@stock_take)}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Started
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {Calendar.strftime(@stock_take.inserted_at, "%d %b %Y, %H:%M UTC")}
            </dd>
          </div>
          <div :if={@stock_take.approved_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Reviewed by
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{person_name(@stock_take.approved_by)}</dd>
          </div>
        </dl>

        <div :if={@stock_take.notes} class="mt-5 border-t border-thamani-stone pt-5">
          <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Notes</dt>
          <dd class="mt-1 text-sm text-thamani-ink">{@stock_take.notes}</dd>
        </div>

        <div
          :if={@stock_take.status == :rejected and @stock_take.rejection_reason}
          class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4"
        >
          <p class="text-sm font-semibold text-rose-800">Rejected</p>
          <p class="mt-1 text-sm text-rose-700">{@stock_take.rejection_reason}</p>
        </div>
      </section>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-subtle">Items</h2>

        <div class="mt-3 overflow-hidden rounded-lg border border-thamani-stone">
          <table class="w-full table-fixed text-left text-sm">
            <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
              <tr>
                <th class="px-3 py-2">Product</th>
                <th class="px-3 py-2">Batch</th>
                <th class="px-3 py-2 text-right">Expected</th>
                <th class="px-3 py-2 text-right">Counted</th>
                <th class="px-3 py-2 text-right">Variance</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-thamani-stone">
              <tr :for={item <- @stock_take.items}>
                <td class="px-3 py-2 font-medium text-thamani-forest">
                  {product_name(@products_by_id, item.batch && item.batch.product_id)}
                </td>
                <td class="px-3 py-2 font-mono text-xs">{item.batch && item.batch.batch_no}</td>
                <td class="px-3 py-2 text-right tabular-nums">{item.expected_quantity}</td>
                <td class="px-3 py-2 text-right tabular-nums">{item.counted_quantity || "—"}</td>
                <td class={["px-3 py-2 text-right tabular-nums", variance_class(item.variance)]}>
                  {if item.variance,
                    do: if(item.variance >= 0, do: "+#{item.variance}", else: "#{item.variance}"),
                    else: "—"}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.org_shell>
    """
  end
end
