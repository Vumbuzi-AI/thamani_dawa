defmodule ThamaniDawaWeb.LabStockBatchLive do
  @moduledoc """
  Read-only view of who has drawn stock from a single batch in lab, reached by
  drilling into `LabStockProductLive` or the flat batches view on `LabStockLive`.
  """

  use ThamaniDawaWeb, :live_view

  import ThamaniDawaWeb.BatchLabelComponent

  alias ThamaniDawa.Batches

  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id
    batch = Batches.get_batch_with_details!(org_id, id)

    {:ok,
     socket
     |> assign(:batch, batch)
     |> assign(:history, build_usage_history(batch))}
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp user_display(nil), do: "—"
  defp user_display(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_display(%{email: email}), do: email

  defp patient_name(%{patient_visit: %{patient: %{full_name: full_name}}}), do: full_name
  defp patient_name(_), do: "(unknown patient)"

  defp build_usage_history(batch) do
    dispenses =
      Enum.map(batch.prescription_batch_dispenses, fn dispense ->
        prescription = dispense.prescription_item.prescription

        %{
          at: dispense.dispensed_at,
          who: user_display(dispense.dispensed_by),
          detail: "Dispensed #{dispense.quantity} units to #{patient_name(prescription)}"
        }
      end)

    lab_usages =
      Enum.map(batch.lab_consumable_usages, fn usage ->
        %{
          at: usage.used_at,
          who: user_display(usage.used_by),
          detail: "Used #{usage.quantity} units (lab) for #{patient_name(usage.lab_order)}"
        }
      end)

    (dispenses ++ lab_usages)
    |> Enum.filter(& &1.at)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/lab/stock"
      back={~p"/lab/stock/products/#{@batch.product_id}"}
      back_label="Back to product"
    >
      <.header icon="hero-cube">
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
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Expiry</div>
          <div class="font-medium">{@batch.expiry_date}</div>
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
        Usage history
        <:subtitle>Everyone who has drawn stock from this batch, newest first</:subtitle>
      </.header>
      <.table id="batch-usage" rows={@history}>
        <:col :let={event} label="When">{event.at}</:col>
        <:col :let={event} label="By">{event.who}</:col>
        <:col :let={event} label="Detail">{event.detail}</:col>
        <:empty_state>
          <.blank_state icon="hero-user-group" title="No one has drawn from this batch yet" />
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
