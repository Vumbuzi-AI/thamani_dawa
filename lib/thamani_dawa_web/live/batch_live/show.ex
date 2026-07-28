defmodule ThamaniDawaWeb.BatchLive.Show do
  use ThamaniDawaWeb, :live_view

  import ThamaniDawaWeb.BatchLabelComponent

  alias ThamaniDawa.Batches

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    batch = Batches.get_batch_with_details!(organization_id, id)

    {:ok,
     socket
     |> assign(:batch, batch)
     |> assign(:timeline, build_timeline(batch))}
  end

  defp user_display(nil), do: "—"
  defp user_display(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_display(%{email: email}), do: email

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp patient_name(%{patient_visit: %{patient: %{full_name: full_name}}}), do: full_name
  defp patient_name(_), do: "(unknown patient)"

  defp build_timeline(batch) do
    received =
      if batch.received_at do
        [
          %{
            at: batch.received_at,
            label: "Received",
            detail: "By #{user_display(batch.approver)}"
          }
        ]
      else
        []
      end

    dispenses =
      Enum.map(batch.prescription_batch_dispenses, fn dispense ->
        prescription = dispense.prescription_item.prescription

        %{
          at: dispense.dispensed_at,
          label: "Dispensed #{dispense.quantity} units",
          detail:
            "Rx ##{prescription.id} — #{patient_name(prescription)} · by #{user_display(dispense.dispensed_by)}"
        }
      end)

    lab_usages =
      Enum.map(batch.lab_consumable_usages, fn usage ->
        %{
          at: usage.used_at,
          label: "Used #{usage.quantity} units (lab)",
          detail:
            "Lab order ##{usage.lab_order_id} — #{patient_name(usage.lab_order)} · by #{user_display(usage.used_by)}"
        }
      end)

    stock_take_adjustments =
      Enum.map(batch.stock_take_items, fn item ->
        %{
          at: item.counted_at,
          label: "Counted #{item.counted_quantity} (variance #{item.variance})",
          detail: "Stock-take ##{item.stock_take_id} · by #{user_display(item.counted_by)}"
        }
      end)

    (received ++ dispenses ++ lab_usages ++ stock_take_adjustments)
    |> Enum.filter(& &1.at)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/products"}>
      <.header>
        Batch {@batch.batch_no}
        <:subtitle>{product_name(@batch.product)} · {@batch.site.name}</:subtitle>
        <:actions>
          <.button
            type="button"
            variant="primary"
            onclick="window.print()"
            class="no-print flex items-center gap-1.5"
          >
            <.icon name="hero-printer" class="w-4 h-4" /> Print Data Matrix
          </.button>
        </:actions>
      </.header>

      <.batch_label_card batch={@batch} class="my-6" />

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 py-4 border-b border-base-200 text-sm mb-6">
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">GTIN</div>
          <div class="font-medium font-mono">{@batch.gtin || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Serial</div>
          <div class="font-medium">{@batch.serial || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Manufacture date</div>
          <div class="font-medium">{@batch.manufacture_date || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Expiry</div>
          <div class="font-medium">{@batch.expiry_date}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Supplier</div>
          <div class="font-medium">{(@batch.supplier && @batch.supplier.name) || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Cost per unit</div>
          <div class="font-medium">{@batch.cost_per_unit || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Stock</div>
          <div class="font-medium">{@batch.remaining_quantity} / {@batch.quantity}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Received by</div>
          <div class="font-medium">{user_display(@batch.approver)}</div>
        </div>
      </div>

      <.header variant="plain" class="mt-6">
        History
        <:subtitle>Everything that has touched this batch's stock, newest first</:subtitle>
      </.header>
      <.table id="batch-timeline" rows={@timeline}>
        <:col :let={event} label="Event">{event.label}</:col>
        <:col :let={event} label="Detail">{event.detail}</:col>
        <:col :let={event} label="When">{event.at}</:col>
        <:empty_state>
          <.blank_state icon="hero-clock" title="No activity recorded yet">
            Receiving, dispensing, lab usage, and stock-take adjustments will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.org_shell>
    """
  end
end
