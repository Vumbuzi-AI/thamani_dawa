defmodule ThamaniDawaWeb.DistributorGoodsReceiptLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.GoodsReceipts

  def mount(%{"id" => id}, _session, socket) do
    receipt = GoodsReceipts.get_receipt!(socket.assigns.current_scope.organization_id, id)

    portal =
      if Scope.admin?(socket.assigns.current_scope), do: :organization, else: :distributor

    index_path =
      if portal == :organization, do: ~p"/org/receiving", else: ~p"/distributor/receiving"

    {:ok,
     socket
     |> assign(:receipt, receipt)
     |> assign(:receiving_portal, portal)
     |> assign(:receiving_index_path, index_path)}
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "Unknown product"
  defp unit_label("H87"), do: "piece(s)"
  defp unit_label("U2"), do: "tablet(s)"
  defp unit_label("C62"), do: "unit(s)"
  defp unit_label(nil), do: "unit(s)"
  defp unit_label(unit), do: if(String.ends_with?(unit, "(s)"), do: unit, else: "#{unit}(s)")
  defp supplier_summary(items), do: summary(items, :supplier_id, :supplier, "Multiple suppliers")
  defp warehouse_summary(items), do: summary(items, :site_id, :site, "Multiple warehouses")

  defp summary(items, id_field, association, multiple) do
    case items |> Enum.map(&Map.get(&1, id_field)) |> Enum.uniq() do
      [nil] -> "—"
      [_id] -> items |> hd() |> Map.get(association) |> then(&if(&1, do: &1.name, else: "—"))
      _ -> multiple
    end
  end

  def render(assigns) do
    ~H"""
    <.receipt_shell
      portal={@receiving_portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={@receiving_index_path}
    >
      <.header icon="hero-document-check">
        {@receipt.number}
        <:subtitle>Complete record of this received delivery.</:subtitle>
        <:actions>
          <.button variant="ghost" navigate={@receiving_index_path}><.icon
            name="hero-arrow-left"
            class="size-4"
          /> Receiving</.button>
        </:actions>
      </.header>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-white p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Received</dt><dd class="mt-1 text-sm text-thamani-ink">
              {Calendar.strftime(@receipt.received_at, "%d %b %Y, %H:%M UTC")}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Supplier</dt><dd class="mt-1 text-sm text-thamani-ink">
              {supplier_summary(@receipt.items)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Warehouse</dt><dd class="mt-1 text-sm text-thamani-ink">
              {warehouse_summary(@receipt.items)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Received by
            </dt><dd class="mt-1 text-sm text-thamani-ink">
              {if @receipt.received_by, do: @receipt.received_by.email, else: "—"}
            </dd>
          </div>
        </dl>
      </section>

      <section class="mt-6">
        <.header variant="plain">
          <span>Received items</span><:subtitle>
            Each line was posted to inventory as part of this receipt.
          </:subtitle>
        </.header>
        <.table id="goods-receipt-items" rows={@receipt.items}>
          <:col :let={batch} label="Product">{product_name(batch.product)}</:col>
          <:col :let={batch} label="Batch"><span class="font-mono">{batch.batch_no}</span></:col>
          <:col :let={batch} label="Expiry">{Calendar.strftime(batch.expiry_date, "%b %Y")}</:col>
          <:col :let={batch} label="Location">
            {if batch.site, do: batch.site.name, else: "Organization stock"}
          </:col>
          <:col :let={batch} label="Quantity">
            <span class="font-semibold text-thamani-forest">{batch.quantity} {unit_label(
              batch.product.uom
            )}</span>
          </:col>
        </.table>
      </section>
    </.receipt_shell>
    """
  end

  attr :portal, :atom, required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  defp receipt_shell(%{portal: :organization} = assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      {render_slot(@inner_block)}
    </Layouts.org_shell>
    """
  end

  defp receipt_shell(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      {render_slot(@inner_block)}
    </Layouts.distributor_shell>
    """
  end
end
