defmodule ThamaniDawaWeb.InventoryDisposalQueueLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    disposal = InventoryDisposals.get_disposal!(organization_id, id)
    products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})
    site = Sites.get_site!(organization_id, disposal.site_id)

    {:ok,
     socket
     |> assign(:disposal, disposal)
     |> assign(:site, site)
     |> assign(:products_by_id, products_by_id)}
  end

  def handle_event("approve", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    admin_id = socket.assigns.current_scope.user.id
    disposal = socket.assigns.disposal

    case InventoryDisposals.approve_disposal(organization_id, disposal.id, admin_id) do
      {:ok, _approved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Disposal approved. Batch quantities updated.")
         |> push_navigate(to: ~p"/org/disposals")}

      {:error, :not_approvable} ->
        {:noreply, put_flash(socket, :error, "That disposal can no longer be approved.")}
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

  defp kind_label(:expiry), do: "Expiry write-off"
  defp kind_label(:returned), do: "Supplier return"

  defp supplier_name(%{batch: %{supplier: %{name: name}}}), do: name
  defp supplier_name(_item), do: "—"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/disposals">
      <.td_detail_page
        title={"#{kind_label(@disposal.kind)} — #{@site.name}"}
        subtitle={"#{Phoenix.Naming.humanize(@disposal.inventory_type)} disposal details."}
      >
        <:actions>
          <.button
            :if={@disposal.status in [:draft, :pending]}
            variant="primary"
            phx-click="approve"
            phx-disable-with="Approving…"
          >
            Approve
          </.button>
          <.button
            :if={@disposal.status == :pending}
            variant="ghost"
            navigate={~p"/org/disposals/#{@disposal.id}/reject"}
          >
            Reject
          </.button>
          <.button variant="ghost" navigate={~p"/org/disposals"}>
            <.icon name="hero-arrow-left" class="size-4" /> Disposals
          </.button>
        </:actions>
        <:body>
      <section class="mt-5 rounded-2xl border border-thamani-stone bg-td-surface p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Status</dt>
            <dd class="mt-1"><.status_badge status={@disposal.status} /></dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Requested by
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{requester_label(@disposal)}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Started
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {ThamaniDawaWeb.TimeFormat.datetime(@disposal.inserted_at)}
            </dd>
          </div>
          <div :if={@disposal.approved_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Reviewed by
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{person_name(@disposal.approved_by)}</dd>
          </div>
        </dl>

        <div :if={@disposal.reason} class="mt-5 border-t border-thamani-stone pt-5">
          <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Reason</dt>
          <dd class="mt-1 text-sm text-thamani-ink">{@disposal.reason}</dd>
        </div>

        <div :if={@disposal.notes} class="mt-5 border-t border-thamani-stone pt-5">
          <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Notes</dt>
          <dd class="mt-1 text-sm text-thamani-ink">{@disposal.notes}</dd>
        </div>

        <div
          :if={@disposal.status == :rejected and @disposal.rejection_reason}
          class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4"
        >
          <p class="text-sm font-semibold text-rose-800">Rejected</p>
          <p class="mt-1 text-sm text-rose-700">{@disposal.rejection_reason}</p>
        </div>
      </section>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-td-surface p-5 sm:p-6">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-subtle">Items</h2>

        <div class="mt-3 overflow-hidden rounded-lg border border-thamani-stone">
          <table class="w-full table-fixed text-left text-sm">
            <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
              <tr>
                <th class="px-3 py-2">Product</th>
                <th class="px-3 py-2">Batch</th>
                <th :if={@disposal.kind == :returned} class="px-3 py-2">Supplier</th>
                <th class="px-3 py-2 text-right">Available</th>
                <th class="px-3 py-2 text-right">Requested</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-thamani-stone">
              <tr :for={item <- @disposal.items}>
                <td class="px-3 py-2 font-medium text-thamani-forest">
                  {product_name(@products_by_id, item.batch && item.batch.product_id)}
                </td>
                <td class="px-3 py-2 font-mono text-xs">{item.batch && item.batch.batch_no}</td>
                <td :if={@disposal.kind == :returned} class="px-3 py-2">
                  {supplier_name(item)}
                </td>
                <td class="px-3 py-2 text-right tabular-nums">{item.available_quantity}</td>
                <td class="px-3 py-2 text-right tabular-nums">{item.quantity}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
        </:body>
      </.td_detail_page>
    </Layouts.org_shell>
    """
  end
end
