defmodule ThamaniDawaWeb.DistributorGoodsReceiptLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.Products

  def mount(%{"id" => id}, _session, socket) do
    receipt = GoodsReceipts.get_receipt!(socket.assigns.current_scope.organization_id, id)

    portal = if socket.assigns.live_action == :org_show, do: :organization, else: :distributor
    index_path = if portal == :organization, do: ~p"/org/receiving", else: ~p"/distributor/receiving"

    {:ok,
     socket
     |> assign(:receipt, receipt)
     |> assign(:receiving_portal, portal)
     |> assign(:receiving_index_path, index_path)
     |> assign(:resolving_id, nil)
     |> assign(:resolving_status, nil)
     |> assign(:resolution_reference, "")}
  end

  def handle_event("open_resolve", %{"id" => id, "status" => status}, socket)
      when status in ["found", "lost", "stolen"] do
    {:noreply,
     socket
     |> assign(:resolving_id, String.to_integer(id))
     |> assign(:resolving_status, status)
     |> assign(:resolution_reference, "")}
  end

  def handle_event("close_resolve", _params, socket) do
    {:noreply, assign(socket, :resolving_id, nil)}
  end

  def handle_event(
        "confirm_resolve",
        %{"resolution_reference" => reference},
        %{assigns: %{resolving_id: id, resolving_status: status}} = socket
      )
      when not is_nil(id) and status in ["found", "lost", "stolen"] do
    organization_id = socket.assigns.current_scope.organization_id
    discrepancy = GoodsReceipts.get_discrepancy!(organization_id, id)

    if discrepancy.goods_receipt_id == socket.assigns.receipt.id and discrepancy.status == :open do
      case GoodsReceipts.resolve_discrepancy(discrepancy, socket.assigns.current_scope.user.id, %{
             "status" => status,
             "resolution_reference" => reference
           }) do
        {:ok, _discrepancy} ->
          {:noreply,
           socket
           |> put_flash(:info, "Line closed as #{status}.")
           |> assign(:resolving_id, nil)
           |> reload_receipt()}

        {:error, changeset} ->
          {:noreply,
           put_flash(socket, :error, "Could not close this line: #{format_errors(changeset)}")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "That line is not an open discrepancy on this receipt.")}
    end
  end

  defp reload_receipt(socket) do
    receipt =
      GoodsReceipts.get_receipt!(
        socket.assigns.current_scope.organization_id,
        socket.assigns.receipt.id
      )

    assign(socket, :receipt, receipt)
  end

  defp format_errors(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp product_name(nil), do: "Unknown product"
  defp product_name(product), do: product.generic_name || product.brand_name || "Unknown product"

  defp receipt_lines(receipt) do
    received = Enum.map(receipt.items, &batch_line/1)
    missing = Enum.map(receipt.discrepancies, &discrepancy_line/1)
    received ++ missing
  end

  defp receipt_groups(receipt) do
    receipt
    |> receipt_lines()
    |> Enum.group_by(& &1.sscc)
    |> Enum.sort_by(fn {sscc, _lines} -> if(sscc, do: {0, sscc}, else: {1, ""}) end)
    |> Enum.map(fn {sscc, lines} ->
      batches =
        lines
        |> Enum.group_by(&{&1.product_name, &1.gtin, &1.batch_no, &1.expiry, &1.uom})
        |> Enum.map(fn {{product_name, gtin, batch_no, expiry, uom}, batch_lines} ->
          %{
            product_name: product_name,
            gtin: gtin,
            batch_no: batch_no,
            expiry: expiry,
            uom: uom,
            quantity: batch_lines |> Enum.map(&(&1.quantity || 0)) |> Enum.sum(),
            location: batch_lines |> Enum.map(& &1.location) |> Enum.find(&(&1 not in [nil, "—"])) || "—",
            lines: batch_lines
          }
        end)

      logistic_unit_id =
        lines |> Enum.map(& &1[:logistic_unit_id]) |> Enum.find(&(&1 != nil))

      %{sscc: sscc, logistic_unit_id: logistic_unit_id, batches: batches}
    end)
  end

  defp batch_line(batch) do
    %{
      id: "batch-#{batch.id}",
      product_name: product_name(batch.product),
      gtin: batch.gtin,
      batch_no: batch.batch_no,
      serials: batch.serials || [],
      expiry: batch.expiry_date,
      quantity: batch.quantity,
      uom: batch.product && batch.product.uom,
      condition: batch_condition(batch.status),
      sscc: batch.sscc,
      logistic_unit_id: batch.logistic_unit_id,
      location: if(batch.site, do: batch.site.name, else: "—"),
      discrepancy_id: nil,
      resolvable: false,
      resolution_reference: nil
    }
  end

  defp discrepancy_line(discrepancy) do
    %{
      id: "discrepancy-#{discrepancy.id}",
      product_name:
        if(discrepancy.product, do: product_name(discrepancy.product), else: discrepancy.gtin),
      gtin: discrepancy.gtin,
      batch_no: discrepancy.batch_no,
      serials: if(is_binary(discrepancy.serial), do: [discrepancy.serial], else: []),
      expiry: discrepancy.expiry_date,
      quantity: discrepancy.quantity,
      uom: discrepancy.product && discrepancy.product.uom,
      condition: discrepancy_condition(discrepancy),
      sscc: discrepancy.sscc,
      logistic_unit_id: nil,
      location: "—",
      discrepancy_id: discrepancy.id,
      resolvable: discrepancy.status == :open,
      resolution_reference: discrepancy.resolution_reference
    }
  end

  defp discrepancy_condition(%{status: :open}), do: :missing
  defp discrepancy_condition(%{status: status}), do: status

  defp batch_condition(:active), do: nil
  defp batch_condition(:quarantined), do: :damaged
  defp batch_condition(:damaged), do: :damaged
  defp batch_condition(status), do: status

  defp condition_label(:damaged), do: "Damaged"
  defp condition_label(:missing), do: "Missing"
  defp condition_label(:found), do: "Found"
  defp condition_label(:lost), do: "Lost"
  defp condition_label(:expired), do: "Expired"
  defp condition_label(:recalled), do: "Recalled"
  defp condition_label(:stolen), do: "Stolen"
  defp condition_label(:inactive), do: "Inactive"
  defp condition_label(:non_sellable_other), do: "Not sellable"
  defp condition_label(:destroyed), do: "Destroyed"
  defp condition_label(:returned), do: "Returned"
  defp condition_label(status), do: Phoenix.Naming.humanize(status)

  defp condition_classes(:damaged), do: "bg-amber-900 text-amber-50"
  defp condition_classes(:missing), do: "bg-thamani-error text-td-on-danger"
  defp condition_classes(:found), do: "bg-emerald-100 text-emerald-800"
  defp condition_classes(:lost), do: "bg-amber-100 text-amber-800"
  defp condition_classes(:expired), do: "bg-amber-900 text-amber-50"

  defp condition_classes(status) when status in [:stolen, :destroyed, :recalled],
    do: "bg-thamani-error text-td-on-danger"

  defp condition_classes(_status), do: "bg-thamani-stone text-thamani-forest"

  defp format_expiry(nil), do: "—"
  defp format_expiry(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")

  defp case_units(group) do
    group.batches |> Enum.map(& &1.quantity) |> Enum.sum()
  end

  defp received_lines(lines), do: Enum.reject(lines, & &1.discrepancy_id)
  defp follow_up_lines(lines), do: Enum.filter(lines, & &1.discrepancy_id)

  defp serial_entries(lines) do
    Enum.flat_map(lines, fn line ->
      Enum.map(line.serials, fn serial -> %{serial: serial, condition: line.condition} end)
    end)
  end

  attr :batch, :map, required: true

  defp receipt_batch(assigns) do
    received = received_lines(assigns.batch.lines)

    assigns =
      assigns
      |> assign(:serial_entries, serial_entries(Enum.filter(received, &(&1.serials != []))))
      |> assign(:quantity_lines, Enum.filter(received, &(&1.serials == [])))
      |> assign(:follow_up, follow_up_lines(assigns.batch.lines))

    ~H"""
    <div class="border-b border-thamani-stone last:border-b-0">
      <div class="grid grid-cols-2 gap-x-4 gap-y-3 px-4 py-3.5 sm:grid-cols-4 sm:px-5">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-thamani-evergreen" title={@batch.product_name}>
            {@batch.product_name}
          </p>
          <p
            :if={@batch.gtin}
            class="mt-0.5 truncate text-xs tabular-nums tracking-tight text-thamani-pewter"
          >
            {@batch.gtin}
          </p>
        </div>
        <div class="min-w-0">
          <p class="text-xs font-medium text-thamani-pewter">Batch</p>
          <p class="mt-0.5 text-sm font-medium tabular-nums tracking-tight text-thamani-evergreen [overflow-wrap:anywhere]">
            {@batch.batch_no}
          </p>
        </div>
        <div>
          <p class="text-xs font-medium text-thamani-pewter">Expiry</p>
          <p class="mt-0.5 text-sm font-medium tabular-nums text-thamani-evergreen">
            {format_expiry(@batch.expiry)}
          </p>
        </div>
        <div>
          <p class="text-xs font-medium text-thamani-pewter">Units</p>
          <p class="mt-0.5 text-sm font-medium tabular-nums text-thamani-evergreen">
            {@batch.quantity} {Products.unit_label(@batch.uom)}
          </p>
        </div>
      </div>

      <details
        :if={@serial_entries != []}
        class="group border-t border-thamani-stone bg-thamani-canvas/60 px-4 py-3 sm:px-5"
      >
        <summary class="w-fit cursor-pointer list-none text-xs font-medium text-thamani-pewter hover:text-thamani-evergreen">
          <span class="inline-flex items-center gap-1">
            <.icon
              name="hero-chevron-right"
              class="size-3.5 transition-transform group-open:rotate-90"
            />
            {length(@serial_entries)} serial(s)
          </span>
        </summary>
        <ul class="mt-2 flex flex-wrap gap-1.5">
          <li
            :for={entry <- @serial_entries}
            class="inline-flex items-center gap-1.5 rounded-lg border border-thamani-stone bg-td-surface px-2 py-1 text-xs font-medium tabular-nums tracking-tight text-thamani-evergreen"
          >
            {entry.serial}
            <span
              :if={entry.condition}
              class={[
                "inline-flex shrink-0 items-center rounded-full px-1.5 py-0.5 text-[10px] font-medium",
                condition_classes(entry.condition)
              ]}
            >
              {condition_label(entry.condition)}
            </span>
          </li>
        </ul>
      </details>

      <ul
        :if={@quantity_lines != []}
        class="grid gap-3 px-4 py-4 sm:grid-cols-2 sm:px-5 xl:grid-cols-3"
      >
        <li
          :for={line <- @quantity_lines}
          id={"goods-receipt-line-#{line.id}"}
          class="rounded-xl border border-thamani-stone bg-td-surface p-3"
        >
          <p class="text-sm font-medium text-thamani-evergreen">
            {line.quantity} {Products.unit_label(line.uom)}
          </p>
          <p class="mt-0.5 text-xs text-thamani-pewter">No serial recorded</p>
          <span
            :if={line.condition}
            class={[
              "mt-2 inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
              condition_classes(line.condition)
            ]}
          >
            {condition_label(line.condition)}
          </span>
        </li>
      </ul>

      <div :if={@follow_up != []} class="border-t border-thamani-stone px-4 py-4 sm:px-5">
        <p class="text-xs font-medium text-thamani-pewter">Not confirmed</p>
        <ul class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          <li
            :for={line <- @follow_up}
            id={"goods-receipt-line-#{line.id}"}
            class="rounded-xl border border-thamani-stone bg-td-surface p-3"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="min-w-0 text-sm font-medium tabular-nums tracking-tight text-thamani-evergreen [overflow-wrap:anywhere]">
                {if line.serials == [],
                  do: "#{line.quantity} #{Products.unit_label(line.uom)}, no serial",
                  else: Enum.join(line.serials, ", ")}
              </p>
              <span
                :if={line.condition}
                class={[
                  "inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  condition_classes(line.condition)
                ]}
              >
                {condition_label(line.condition)}
              </span>
            </div>
            <p
              :if={line.resolution_reference not in [nil, ""]}
              class="mt-2 text-xs text-thamani-pewter"
            >
              Reference
              <span class="font-medium text-thamani-evergreen">{line.resolution_reference}</span>
            </p>
            <div
              :if={line.resolvable}
              id={"discrepancy-actions-#{line.discrepancy_id}"}
              class="mt-3 flex flex-wrap gap-2"
            >
              <button
                :for={status <- ["found", "lost", "stolen"]}
                type="button"
                id={"discrepancy-#{line.discrepancy_id}-#{status}"}
                phx-click="open_resolve"
                phx-value-id={line.discrepancy_id}
                phx-value-status={status}
                class={[
                  "inline-flex h-8 items-center rounded-full border border-thamani-frosted bg-td-surface px-3 text-xs font-semibold transition-colors hover:bg-thamani-canvas",
                  status == "stolen" && "text-thamani-error",
                  status != "stolen" && "text-thamani-evergreen"
                ]}
              >
                {condition_label(String.to_existing_atom(status))}
              </button>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end

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

  defp received_by_label(%{received_by: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp received_by_label(%{received_by: %{email: email}}) when is_binary(email), do: email
  defp received_by_label(_receipt), do: "—"

  defp receipt_received_at(dt) do
    ThamaniDawaWeb.TimeFormat.datetime(dt) <> " EAT"
  end

  defp follow_up_from_groups(groups) do
    groups
    |> Enum.flat_map(& &1.batches)
    |> Enum.flat_map(&follow_up_lines(&1.lines))
  end

  def render(assigns) do
    groups = receipt_groups(assigns.receipt)

    assigns =
      assigns
      |> assign(:receipt_groups, groups)
      |> assign(:receipt_follow_up, follow_up_from_groups(groups))

    ~H"""
    <.receipt_shell
      portal={@receiving_portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={@receiving_index_path}
    >
      <%= if @receiving_portal == :organization do %>
        <div class="td-recipe">
          <div class="td-back">
            <.link navigate={@receiving_index_path} class="td-back-link">
              <.td_icon name="arrow-left" class="size-3.5" /> Back to Receiving
            </.link>
          </div>
          <.td_page_header title="Goods receipt" subtitle={receipt_received_at(@receipt.received_at)}>
            <:actions>
              <.td_badge tone="success" label="Received" />
            </:actions>
          </.td_page_header>
          <div class="td-kv-grid">
            <.td_key_value label="Receipt" value={@receipt.number} mono />
            <.td_key_value label="Supplier" value={supplier_summary(@receipt)} />
            <.td_key_value label="Warehouse" value={warehouse_summary(@receipt.items)} />
            <.td_key_value label="Received by" value={received_by_label(@receipt)} />
          </div>

          <section class="mt-6">
            <.td_card_header title="Items" subtitle="Batches checked in on this receipt." />
            <table :if={@receipt_groups != []} id="goods-receipt-items" class="td-rows">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Batch</th>
                  <th>Expiry</th>
                  <th>Location</th>
                  <th class="is-num">Quantity</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={batch <- Enum.flat_map(@receipt_groups, & &1.batches)}>
                  <td>{batch.product_name}</td>
                  <td class="is-num">{batch.batch_no || "—"}</td>
                  <td>{format_expiry(batch.expiry)}</td>
                  <td>{batch.location}</td>
                  <td class="is-num">
                    {batch.quantity} {Products.unit_label(batch.uom)}
                  </td>
                </tr>
              </tbody>
            </table>
            <.blank_state
              :if={@receipt_groups == []}
              icon="hero-archive-box"
              title="Nothing on this receipt"
            >
              Received batches and missing lines will show here.
            </.blank_state>

            <div :if={@receipt_follow_up != []} class="mt-4">
              <p class="td-muted">Not confirmed</p>
              <ul class="mt-3 grid gap-3 sm:grid-cols-2">
                <li
                  :for={line <- @receipt_follow_up}
                  id={"goods-receipt-line-#{line.id}"}
                  class="rounded-xl border border-thamani-stone bg-td-surface p-3"
                >
                  <div class="flex items-start justify-between gap-3">
                    <p class="min-w-0 text-sm font-medium">{line.product_name}</p>
                    <span
                      :if={line.condition}
                      class={[
                        "inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-medium",
                        condition_classes(line.condition)
                      ]}
                    >
                      {condition_label(line.condition)}
                    </span>
                  </div>
                  <p
                    :if={line.resolution_reference not in [nil, ""]}
                    class="mt-2 text-xs text-thamani-pewter"
                  >
                    Reference
                    <span class="font-medium">{line.resolution_reference}</span>
                  </p>
                  <div
                    :if={line.resolvable}
                    id={"discrepancy-actions-#{line.discrepancy_id}"}
                    class="mt-3 flex flex-wrap gap-2"
                  >
                    <button
                      :for={status <- ["found", "lost", "stolen"]}
                      type="button"
                      id={"discrepancy-#{line.discrepancy_id}-#{status}"}
                      phx-click="open_resolve"
                      phx-value-id={line.discrepancy_id}
                      phx-value-status={status}
                      class="td-chip"
                    >
                      {condition_label(String.to_existing_atom(status))}
                    </button>
                  </div>
                </li>
              </ul>
            </div>
          </section>

          <section class="mt-6">
            <.td_card_header
              title="Documents"
              subtitle="GRN, invoice, and any other documents attached to this delivery."
            />
            <p :if={@receipt.attachments == []} class="td-muted mt-3">No documents attached.</p>
            <ul
              :if={@receipt.attachments != []}
              id="goods-receipt-documents"
              class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-3"
            >
              <li
                :for={attachment <- @receipt.attachments}
                id={"goods-receipt-document-#{attachment.id}"}
                class="td-doc-card"
              >
                <p class="td-doc-name" title={attachment.filename}>{attachment.filename}</p>
                <p class="td-muted">
                  {doc_type_label(attachment.doc_type)} · {document_kind(attachment)} · {format_file_size(
                    attachment.byte_size
                  )}
                </p>
                <div class="td-doc-actions">
                  <a
                    href={attachment.path}
                    target="_blank"
                    rel="noopener"
                    aria-label={"Preview #{attachment.filename}"}
                    class="td-btn is-secondary"
                  >
                    Preview
                  </a>
                  <a
                    href={attachment.path}
                    download={attachment.filename}
                    aria-label={"Download #{attachment.filename}"}
                    class="td-btn is-primary"
                  >
                    Download
                  </a>
                </div>
              </li>
            </ul>
          </section>
        </div>
      <% else %>
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

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-td-surface p-5 sm:p-6">
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
        <div class="mb-3">
          <h2 class="text-base font-semibold text-thamani-evergreen">Received items</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Confirmed units sit with their case. Anything still missing is listed under them.
          </p>
        </div>

        <.blank_state
          :if={@receipt_groups == []}
          icon="hero-archive-box"
          title="Nothing on this receipt"
        >
          Received batches and missing lines will show here.
        </.blank_state>

        <div id="goods-receipt-items" class="space-y-4">
          <article
            :for={{group, group_index} <- Enum.with_index(@receipt_groups)}
            id={"goods-receipt-case-#{group_index}"}
            class="overflow-hidden rounded-2xl ff-surface-card"
          >
            <header class="flex flex-wrap items-center justify-between gap-3 border-b border-thamani-stone px-4 py-3 sm:px-5">
              <div class="flex items-center gap-3">
                <span class="flex size-8 items-center justify-center rounded-lg bg-thamani-canvas text-sm font-semibold text-thamani-forest">
                  {group_index + 1}
                </span>
                <div>
                  <p class="font-medium text-thamani-evergreen">
                    {if group.sscc, do: "Case", else: "No case label"}
                  </p>
                  <p class="text-xs tabular-nums text-thamani-pewter">
                    {case_units(group)} {if case_units(group) == 1, do: "unit", else: "units"}
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span
                  :if={group.sscc}
                  class="rounded-lg bg-td-accent-tint px-3 py-1 text-xs font-semibold tabular-nums tracking-tight text-thamani-forest"
                >
                  SSCC {group.sscc}
                </span>
              </div>
            </header>

            <.receipt_batch :for={batch <- group.batches} batch={batch} />
          </article>
        </div>
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
            class="group flex min-w-0 flex-col rounded-2xl border border-thamani-stone bg-td-surface p-4 shadow-[0_1px_2px_rgba(23,48,42,0.04)] transition-all duration-200 hover:-translate-y-0.5 hover:border-[color-mix(in_srgb,var(--thamani-forest)_28%,white)] hover:shadow-md"
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
                class="inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg px-3 text-xs font-semibold text-thamani-forest transition-colors hover:bg-thamani-canvas focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-td-focus"
              >
                <.icon name="hero-eye" class="size-4" /> Preview
              </a>
              <a
                href={attachment.path}
                download={attachment.filename}
                aria-label={"Download #{attachment.filename}"}
                class="inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg bg-thamani-forest px-3 text-xs font-semibold text-td-on-accent transition-all hover:-translate-y-px hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-td-focus focus-visible:ring-offset-2"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Download
              </a>
            </div>
          </li>
        </ul>
      </section>
      <% end %>

      <.modal
        :if={@resolving_id}
        id="resolve-discrepancy-modal"
        show
        on_cancel={JS.push("close_resolve")}
      >
        <h2 class="mb-2 text-2xl font-medium tracking-tight text-thamani-forest">
          Close this line as {condition_label(String.to_existing_atom(@resolving_status))}
        </h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          Found means the goods turned up. Lost and stolen are conclusions, and each needs an investigation reference before the line can close.
        </p>
        <.form for={%{}} as={:resolve} id="resolve-discrepancy-form" phx-submit="confirm_resolve">
          <.input
            :if={@resolving_status in ["lost", "stolen"]}
            name="resolution_reference"
            value={@resolution_reference}
            label="Investigation reference"
            placeholder="Incident report or case number"
            required
          />
          <input
            :if={@resolving_status == "found"}
            type="hidden"
            name="resolution_reference"
            value=""
          />
          <.button variant="primary" class="mt-3 w-full">Confirm</.button>
        </.form>
      </.modal>
    </.receipt_shell>
    """
  end

  defp doc_type_label(:delivery_note), do: "Delivery note"
  defp doc_type_label(:invoice), do: "Invoice"
  defp doc_type_label(:po), do: "Purchase order"
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
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@current_path}
      back_label="Back to Receiving"
    >
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
