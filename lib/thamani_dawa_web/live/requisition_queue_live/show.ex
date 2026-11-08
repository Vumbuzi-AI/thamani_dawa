defmodule ThamaniDawaWeb.RequisitionQueueLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Products
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.Sites

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    requisition =
      organization_id
      |> Requisitions.get_requisition!(id)
      |> Repo.preload(lines: [fulfillments: [:dispatched_batch]])

    products_by_id =
      organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    sites_by_id =
      organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:requisition, requisition)
     |> assign(:products_by_id, products_by_id)
     |> assign(:sites_by_id, sites_by_id)}
  end

  defp product_name(products_by_id, product_id) do
    case Map.get(products_by_id, product_id) do
      nil -> "(unknown product)"
      product -> product.generic_name || product.brand_name || "(unnamed)"
    end
  end

  defp site_name(sites_by_id, site_id) do
    case Map.get(sites_by_id, site_id) do
      nil -> "—"
      site -> site.name
    end
  end

  defp person_name(nil), do: "—"
  defp person_name(user), do: user.name

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/requisitions">
      <.header icon="hero-clipboard-document-list">
        {@requisition.number}
        <:subtitle>Stock request details, approval and fulfillment history.</:subtitle>
        <:actions>
          <.button
            :if={@requisition.status == :pending}
            variant="primary"
            navigate={~p"/org/requisitions/#{@requisition.id}/review"}
          >
            Review
          </.button>
          <.button
            :if={@requisition.status in [:approved, :partially_approved, :partially_fulfilled]}
            variant="primary"
            navigate={~p"/org/requisitions/#{@requisition.id}/fulfill"}
          >
            Fulfill
          </.button>
          <.button variant="ghost" navigate={~p"/org/requisitions"}>
            <.icon name="hero-arrow-left" class="size-4" /> Requisitions
          </.button>
        </:actions>
      </.header>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Status</dt>
            <dd class="mt-1 flex items-center gap-2">
              <.status_badge status={@requisition.status} />
              <span :if={@requisition.needs_reorder} class="text-xs font-medium text-thamani-error">
                Needs reorder
              </span>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Site</dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {site_name(@sites_by_id, @requisition.site_id)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Requested by
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{person_name(@requisition.requested_by)}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Requested
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {Calendar.strftime(@requisition.inserted_at, "%d %b %Y, %H:%M UTC")}
            </dd>
          </div>
          <div :if={@requisition.reviewed_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Reviewed by
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{person_name(@requisition.reviewed_by)}</dd>
          </div>
          <div :if={@requisition.reviewed_at}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Reviewed
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {Calendar.strftime(@requisition.reviewed_at, "%d %b %Y, %H:%M UTC")}
            </dd>
          </div>
        </dl>

        <div :if={@requisition.notes} class="mt-5 border-t border-thamani-stone pt-5">
          <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Notes</dt>
          <dd class="mt-1 text-sm text-thamani-ink">{@requisition.notes}</dd>
        </div>

        <div
          :if={@requisition.status == :rejected and @requisition.rejection_reason}
          class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4"
        >
          <p class="text-sm font-semibold text-rose-800">Rejected</p>
          <p class="mt-1 text-sm text-rose-700">{@requisition.rejection_reason}</p>
        </div>
      </section>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-subtle">Items</h2>

        <%= if @requisition.lines == [] do %>
          <div class="mt-3 overflow-hidden rounded-lg border border-thamani-stone">
            <table class="w-full table-fixed text-left text-sm">
              <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                <tr>
                  <th class="px-3 py-2">Product</th>
                  <th class="px-3 py-2">Quantity</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td class="px-3 py-2 font-medium text-thamani-forest">
                    {product_name(@products_by_id, @requisition.product_id)}
                  </td>
                  <td class="px-3 py-2">{@requisition.quantity}</td>
                </tr>
              </tbody>
            </table>
          </div>
        <% else %>
          <div class="mt-3 flex flex-col gap-4">
            <div
              :for={line <- @requisition.lines}
              class="overflow-hidden rounded-xl border border-thamani-stone"
            >
              <div class="flex flex-wrap items-center justify-between gap-2 bg-thamani-canvas px-4 py-3">
                <p class="text-sm font-medium text-thamani-forest">
                  {product_name(@products_by_id, line.product_id)}
                </p>
                <div class="flex items-center gap-3 text-xs text-thamani-pewter">
                  <span>Requested {line.requested_quantity}</span>
                  <span>Approved {line.approved_quantity || "—"}</span>
                  <.status_badge status={line.status} />
                </div>
              </div>
              <table :if={line.fulfillments != []} class="w-full table-fixed text-left text-sm">
                <thead class="text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                  <tr>
                    <th class="px-4 py-2">Batch</th>
                    <th class="px-4 py-2">Dispatched</th>
                    <th class="px-4 py-2">Received</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-thamani-stone">
                  <tr :for={fulfillment <- line.fulfillments}>
                    <td class="px-4 py-2 font-mono text-xs">
                      {fulfillment.dispatched_batch && fulfillment.dispatched_batch.batch_no}
                    </td>
                    <td class="px-4 py-2">{fulfillment.dispatched_quantity}</td>
                    <td class="px-4 py-2">{fulfillment.received_quantity || "Awaiting receipt"}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.org_shell>
    """
  end
end
