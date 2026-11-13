defmodule ThamaniDawaWeb.RequisitionLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Products
  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.Sites

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    requisition = Requisitions.get_requisition!(organization_id, id)

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
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/requisitions"
    >
      <.header icon="hero-clipboard-document-list">
        {@requisition.number}
        <:subtitle>Details of this stock request to the organization.</:subtitle>
        <:actions>
          <.button variant="ghost" navigate={~p"/pharmacy/requisitions"}>
            <.icon name="hero-arrow-left" class="size-4" /> Requisitions
          </.button>
        </:actions>
      </.header>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Status</dt>
            <dd class="mt-1">
              <.status_badge status={@requisition.status} />
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
          <div class="mt-3 overflow-hidden rounded-lg border border-thamani-stone">
            <table class="w-full table-fixed text-left text-sm">
              <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                <tr>
                  <th class="w-[40%] px-3 py-2">Product</th>
                  <th class="w-[20%] px-3 py-2">Requested</th>
                  <th class="w-[20%] px-3 py-2">Approved</th>
                  <th class="w-[20%] px-3 py-2">Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-thamani-stone">
                <tr :for={line <- @requisition.lines}>
                  <td class="px-3 py-2 font-medium text-thamani-forest">
                    {product_name(@products_by_id, line.product_id)}
                  </td>
                  <td class="px-3 py-2">{line.requested_quantity}</td>
                  <td class="px-3 py-2">{line.approved_quantity || "—"}</td>
                  <td class="px-3 py-2"><.status_badge status={line.status} /></td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>
    </Layouts.pharmacy_shell>
    """
  end
end
