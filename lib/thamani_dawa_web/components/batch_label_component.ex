defmodule ThamaniDawaWeb.BatchLabelComponent do
  @moduledoc """
  Components for displaying and printing GS1 Data Matrix labels for batches.
  """
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.GS1Encoder

  @doc """
  Renders a printable GS1 Data Matrix label card.
  """
  attr :batch, :map, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: ""

  def batch_label_card(assigns) do
    assigns = assign_new(assigns, :id, fn -> "batch-label-#{assigns.batch.id}" end)
    assigns = assign(assigns, :bwip_text, GS1Encoder.bwipjs_text(assigns.batch))
    assigns = assign(assigns, :human_text, GS1Encoder.human_readable(assigns.batch))

    ~H"""
    <div
      id={@id}
      class={[
        "printable-batch-label border border-base-300 rounded-xl p-5 bg-base-100 shadow-sm",
        @class
      ]}
    >
      <div class="flex flex-col sm:flex-row items-center gap-6">
        <div class="flex flex-col items-center shrink-0">
          <canvas
            id={"datamatrix-canvas-#{@batch.id}"}
            phx-hook="DataMatrix"
            data-gs1-text={@bwip_text}
            class="w-32 h-32 bg-white p-1 rounded border border-base-200 shadow-inner"
          ></canvas>
          <span class="text-[10px] text-base-content/60 font-mono mt-1">GS1 DataMatrix</span>
        </div>

        <div class="flex-1 min-w-0 space-y-2 w-full">
          <div>
            <div class="text-xs uppercase tracking-wider text-base-content/50 font-semibold">
              Product
            </div>
            <div class="font-semibold text-base truncate">
              {product_name(@batch.product)}
            </div>
          </div>

          <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
            <div>
              <span class="text-base-content/60">GTIN:</span>
              <span class="font-mono font-medium ml-1">{@batch.gtin}</span>
            </div>
            <div>
              <span class="text-base-content/60">Batch/Lot:</span>
              <span class="font-mono font-medium ml-1">{@batch.batch_no}</span>
            </div>
            <div>
              <span class="text-base-content/60">Mfg Date:</span>
              <span class="font-medium ml-1">{@batch.manufacture_date || "—"}</span>
            </div>
            <div>
              <span class="text-base-content/60">Expiry:</span>
              <span class="font-medium ml-1">{@batch.expiry_date}</span>
            </div>
            <%= if @batch.serial do %>
              <div class="col-span-2">
                <span class="text-base-content/60">Serial:</span>
                <span class="font-mono font-medium ml-1">{@batch.serial}</span>
              </div>
            <% end %>
            <%= if @batch.site do %>
              <div class="col-span-2">
                <span class="text-base-content/60">Site:</span>
                <span class="font-medium ml-1">{@batch.site.name}</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal dialog containing the GS1 Data Matrix label and print controls.
  """
  attr :batch, :map, required: true
  attr :on_close, :any, required: true

  def batch_label_modal(assigns) do
    ~H"""
    <.modal id="batch-label-modal" show on_cancel={@on_close}>
      <div class="no-print mb-4">
        <h2 class="text-lg font-semibold text-base-content">Batch GS1 Data Matrix Label</h2>
        <p class="text-xs text-base-content/60">
          Ready to scan & print for batch {@batch.batch_no}
        </p>
      </div>

      <.batch_label_card batch={@batch} />

      <div class="no-print mt-6 flex justify-end gap-2">
        <.button
          type="button"
          variant="primary"
          onclick="window.print()"
          class="flex items-center gap-1.5"
        >
          <.icon name="hero-printer" class="w-4 h-4" /> Print Label
        </.button>
        <.button type="button" phx-click={@on_close}>Close</.button>
      </div>
    </.modal>
    """
  end

  defp product_name(nil), do: "(Product)"
  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"
end
