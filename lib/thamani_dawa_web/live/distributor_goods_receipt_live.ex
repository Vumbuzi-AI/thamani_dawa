defmodule ThamaniDawaWeb.DistributorGoodsReceiptLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.GoodsReceipts

  def mount(%{"id" => id}, _session, socket) do
    receipt = GoodsReceipts.get_receipt!(socket.assigns.current_scope.organization_id, id)

    portal =
      if socket.assigns.live_action == :distributor_show,
        do: :distributor,
        else: :organization

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

  defp supplier_summary(%{origin_gln: origin_gln} = receipt) when is_binary(origin_gln),
    do: receipt.origin_company || "—"

  defp supplier_summary(receipt),
    do: summary(receipt.items, :supplier_id, :supplier, "Multiple suppliers")

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
              {supplier_summary(@receipt)}
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

      <section :if={@receipt.attachments != []} class="mt-6">
        <.header variant="plain">
          <span>Documents</span>
          <:subtitle>GRN, invoice, and any other documents attached to this delivery.</:subtitle>
        </.header>
        <ul id="goods-receipt-documents" class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          <li
            :for={attachment <- @receipt.attachments}
            id={"goods-receipt-document-#{attachment.id}"}
            class="group flex min-w-0 flex-col rounded-2xl border border-thamani-stone bg-white p-4 shadow-[0_1px_2px_rgba(23,48,42,0.04)] transition-all duration-200 hover:-translate-y-0.5 hover:border-[color-mix(in_srgb,var(--thamani-forest)_28%,white)] hover:shadow-md"
          >
            <div class="flex min-w-0 items-start gap-3">
              <span class={[
                "flex size-11 shrink-0 items-center justify-center rounded-xl",
                document_icon_class(attachment)
              ]}>
                <.icon name={document_icon(attachment)} class="size-5" />
              </span>
              <div class="min-w-0 flex-1">
                <span class="inline-flex rounded-full bg-thamani-canvas px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-thamani-pewter">
                  {doc_type_label(attachment.doc_type)}
                </span>
                <p
                  class="mt-2 truncate text-sm font-semibold text-thamani-forest"
                  title={attachment.filename}
                >
                  {attachment.filename}
                </p>
                <p class="mt-1 text-xs text-thamani-subtle">
                  {document_kind(attachment)} · {format_file_size(attachment.byte_size)}
                </p>
              </div>
            </div>

            <div class="mt-4 grid grid-cols-2 gap-2 border-t border-thamani-stone pt-3">
              <a
                href={attachment.path}
                target="_blank"
                rel="noopener"
                aria-label={"Preview #{attachment.filename}"}
                class="inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg px-3 text-xs font-semibold text-thamani-forest transition-colors hover:bg-thamani-canvas focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-lime"
              >
                <.icon name="hero-eye" class="size-4" /> Preview
              </a>
              <a
                href={attachment.path}
                download={attachment.filename}
                aria-label={"Download #{attachment.filename}"}
                class="inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg bg-thamani-forest px-3 text-xs font-semibold text-white transition-all hover:-translate-y-px hover:bg-[#10221e] hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-lime focus-visible:ring-offset-2"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Download
              </a>
            </div>
          </li>
        </ul>
      </section>
    </.receipt_shell>
    """
  end

  defp doc_type_label(:grn), do: "GRN"
  defp doc_type_label(:invoice), do: "Invoice"
  defp doc_type_label(:other), do: "Other document"

  defp document_icon(%{content_type: "application/pdf"}), do: "hero-document-text"
  defp document_icon(%{content_type: "image/" <> _}), do: "hero-photo"
  defp document_icon(_attachment), do: "hero-document"

  defp document_icon_class(%{content_type: "application/pdf"}),
    do: "bg-red-50 text-red-700"

  defp document_icon_class(%{content_type: "image/" <> _}),
    do: "bg-sky-50 text-sky-700"

  defp document_icon_class(_attachment), do: "bg-thamani-canvas text-thamani-forest"

  defp document_kind(%{content_type: "application/pdf"}), do: "PDF"
  defp document_kind(%{content_type: "image/jpeg"}), do: "JPEG image"
  defp document_kind(%{content_type: "image/png"}), do: "PNG image"
  defp document_kind(%{content_type: "image/" <> _}), do: "Image"
  defp document_kind(_attachment), do: "Document"

  defp format_file_size(nil), do: "Size unavailable"
  defp format_file_size(bytes) when bytes < 1_000, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_000_000, do: "#{Float.round(bytes / 1_000, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"

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
