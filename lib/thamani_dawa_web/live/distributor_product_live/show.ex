defmodule ThamaniDawaWeb.DistributorProductLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.DistributorPagination

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    warehouse_ids =
      organization_id
      |> Sites.list_sites()
      |> Enum.filter(&(&1.site_type == :warehouse and &1.is_active))
      |> Enum.map(& &1.id)

    batches = Batches.list_batches_for_product(organization_id, product.id, warehouse_ids)

    {:ok,
     socket
     |> assign(:product, product)
     |> assign(:all_batches, batches)
     |> assign(:batch_count, length(batches))
     |> assign(:remaining_stock, Enum.sum(Enum.map(batches, & &1.remaining_quantity)))
     |> assign(:page_number, 1)
     |> stream(:batches, [])}
  end

  def handle_params(params, _url, socket) do
    page_info =
      DistributorPagination.page(
        socket.assigns.all_batches,
        DistributorPagination.page_number(params)
      )

    {:noreply,
     socket
     |> assign(:page_info, page_info)
     |> stream(:batches, page_info.entries, reset: true)}
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp date_or_dash(nil), do: "—"
  defp date_or_dash(date), do: Calendar.strftime(date, "%d %b %Y")

  defp supplier_name(nil), do: "—"
  defp supplier_name(supplier), do: supplier.name

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/products"}
    >
      <.header icon="hero-cube">
        {product_name(@product)}
        <:subtitle>Product details and warehouse batches for this catalog item.</:subtitle>
        <:actions>
          <.button variant="ghost" navigate={~p"/distributor/products"}>
            <.icon name="hero-arrow-left" class="size-4" /> Products
          </.button>
          <.button variant="primary" navigate={~p"/distributor/receiving/new"}>
            <.icon name="hero-plus" class="size-4" /> Receive stock
          </.button>
        </:actions>
      </.header>

      <div class="mt-5 grid gap-4 sm:grid-cols-3">
        <.stat_tile
          icon="hero-archive-box"
          label="Batches"
          value={@batch_count}
          sublabel="Across your warehouses"
        />
        <.stat_tile
          icon="hero-cube-transparent"
          label="Remaining stock"
          value={@remaining_stock}
          sublabel="Units across all batches"
        />
        <.stat_tile
          icon="hero-tag"
          label="Reorder level"
          value={@product.reorder_level || "—"}
          sublabel="Units"
        />
      </div>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <h2 class="text-lg font-semibold text-thamani-forest">Product details</h2>
        <dl class="mt-4 grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Brand</dt><dd class="mt-1 text-sm text-thamani-ink">
              {@product.brand_name || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Category</dt><dd class="mt-1 text-sm text-thamani-ink">
              {@product.category || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufacturer
            </dt><dd class="mt-1 text-sm text-thamani-ink">{@product.manufacturer || "—"}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Unit</dt><dd class="mt-1 text-sm text-thamani-ink">
              {@product.uom || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">GTIN</dt><dd class="mt-1 font-mono text-sm text-thamani-ink">
              {@product.gtin || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Unit price
            </dt><dd class="mt-1 text-sm text-thamani-ink">
              {if @product.price, do: "KES #{@product.price}", else: "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Status</dt><dd class="mt-1 text-sm text-thamani-ink">
              {if @product.is_active, do: "Active", else: "Inactive"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Reorder level
            </dt><dd class="mt-1 text-sm text-thamani-ink">{@product.reorder_level || "—"}</dd>
          </div>
        </dl>
      </section>

      <.header variant="plain" class="mt-6">
        Batches
        <:subtitle>
          Batch numbers, warehouse locations, expiry dates, and remaining quantities.
        </:subtitle>
      </.header>
      <.table
        id="distributor-product-batches"
        rows={@streams.batches}
      >
        <:col :let={{_id, batch}} label="Warehouse">
          {if batch.site, do: batch.site.name, else: "—"}
        </:col>
        <:col :let={{_id, batch}} label="Batch / lot">
          <span class="font-mono">{batch.batch_no}</span>
        </:col>
        <:col :let={{_id, batch}} label="Manufactured">{date_or_dash(batch.manufacture_date)}</:col>
        <:col :let={{_id, batch}} label="Expires">{date_or_dash(batch.expiry_date)}</:col>
        <:col :let={{_id, batch}} label="Supplier">{supplier_name(batch.supplier)}</:col>
        <:col :let={{_id, batch}} label="Remaining / received">
          {batch.remaining_quantity} / {batch.quantity}
        </:col>
        <:col :let={{_id, batch}} label="Status">
          <.status_badge status={if batch.approver_id, do: :active, else: :pending} />
        </:col>
        <:empty_state>
          <.blank_state icon="hero-archive-box" title="No batches for this product yet">
            Batches will appear here after you receive this product into a warehouse.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination
        page={@page_info}
        path={~p"/distributor/products/#{@product.id}"}
      />
    </Layouts.distributor_shell>
    """
  end
end
