defmodule ThamaniDawaWeb.DistributorBatchLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches

  def mount(%{"id" => id}, _session, socket) do
    batch = Batches.get_batch_with_details!(socket.assigns.current_scope.organization_id, id)
    {:ok, assign(socket, :batch, batch)}
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "Unknown product"
  defp date_or_dash(nil), do: "—"
  defp date_or_dash(date), do: Calendar.strftime(date, "%d %b %Y")
  defp unit_label("H87"), do: "piece(s)"
  defp unit_label("U2"), do: "tablet(s)"
  defp unit_label("C62"), do: "unit(s)"
  defp unit_label(nil), do: "unit(s)"
  defp unit_label(unit), do: if(String.ends_with?(unit, "(s)"), do: unit, else: "#{unit}(s)")

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/products?view=batches"}
    >
      <.header icon="hero-archive-box">
        {@batch.batch_no}
        <:subtitle>{product_name(@batch.product)} batch details and receiving record.</:subtitle>
        <:actions>
          <.button variant="ghost" navigate={~p"/distributor/products?view=batches"}><.icon
            name="hero-arrow-left"
            class="size-4"
          /> All batches</.button>
        </:actions>
      </.header>
      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">GTIN</dt><dd class="mt-1 font-mono text-sm text-thamani-ink">
              {@batch.gtin}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufacturer
            </dt><dd class="mt-1 text-sm text-thamani-ink">
              {@batch.manufacturer || @batch.product.manufacturer || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufactured
            </dt><dd class="mt-1 text-sm text-thamani-ink">
              {date_or_dash(@batch.manufacture_date)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Expiry</dt><dd class="mt-1 text-sm text-thamani-ink">
              {date_or_dash(@batch.expiry_date)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Warehouse</dt><dd class="mt-1 text-sm text-thamani-ink">
              {@batch.site.name}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Received</dt><dd class="mt-1 text-sm text-thamani-ink">
              {@batch.quantity} {unit_label(@batch.product.uom)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">On hand</dt><dd class="mt-1 text-sm text-thamani-ink">
              {@batch.remaining_quantity} {unit_label(@batch.product.uom)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Goods receipt
            </dt><dd class="mt-1 text-sm text-thamani-ink">
              <.link
                :if={@batch.goods_receipt}
                navigate={~p"/distributor/receiving/#{@batch.goods_receipt.id}"}
                class="font-mono font-semibold text-thamani-forest hover:underline"
              >{@batch.goods_receipt.number}</.link><span :if={is_nil(@batch.goods_receipt)}>Legacy receipt</span>
            </dd>
          </div>
        </dl>
      </section>
    </Layouts.distributor_shell>
    """
  end
end
