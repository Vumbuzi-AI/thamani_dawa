defmodule ThamaniDawaWeb.StockTakeComponents do
  @moduledoc """
  Shared function components for the stock-take counting/review screen, used by both
  `ThamaniDawaWeb.PharmacyStockTakeLive` and `ThamaniDawaWeb.LabStockTakeLive` — the counting
  table, its variance pill, and the finalize confirmation modal are identical between portals;
  only the surrounding layout shell and site-capability filter differ per portal.
  """

  use Phoenix.Component
  import ThamaniDawaWeb.CoreComponents

  attr :entries, :list, required: true
  attr :products_by_id, :map, required: true
  attr :batches_by_id, :map, required: true
  attr :editable?, :boolean, required: true

  def counting_table(assigns) do
    ~H"""
    <.table id="stock-take-entries" rows={@entries}>
      <:col :let={entry} label="Product">
        {product_name(@products_by_id, entry.batch_id, @batches_by_id)}
      </:col>
      <:col :let={entry} label="GTIN">
        <span class="font-mono text-xs">{batch_field(@batches_by_id, entry.batch_id, :gtin)}</span>
      </:col>
      <:col :let={entry} label="Batch no.">
        {batch_field(@batches_by_id, entry.batch_id, :batch_no)}
      </:col>
      <:col :let={entry} label="Expected">
        <span class="tabular-nums">{entry.expected_quantity}</span>
      </:col>
      <:col :let={entry} label="Counted">
        <.count_input :if={@editable?} entry={entry} />
        <span :if={!@editable?} class="tabular-nums">{entry.counted_quantity || "—"}</span>
      </:col>
      <:col :let={entry} label="Variance">
        <.variance_badge
          variance={entry.variance}
          conflict={conflict?(entry, @batches_by_id, @editable?)}
          applied={entry.has_been_applied}
        />
      </:col>
      <:empty_state>
        <.blank_state icon="hero-clipboard-document-list" title="No batches to count">
          This site has no active stock to count right now.
        </.blank_state>
      </:empty_state>
    </.table>
    """
  end

  attr :entry, :map, required: true

  defp count_input(assigns) do
    ~H"""
    <form
      id={"count-entry-form-#{@entry.id}"}
      phx-change="record_count"
      class="flex items-center gap-2"
    >
      <input type="hidden" name="entry_id" value={@entry.id} />
      <input
        type="number"
        name="counted_quantity"
        value={@entry.counted_quantity}
        min="0"
        aria-label={"Counted quantity for entry #{@entry.id}"}
        phx-debounce="blur"
        class="h-9 w-24 rounded-lg border border-thamani-stone bg-thamani-snow px-2 text-right text-sm tabular-nums outline-none focus:border-thamani-accent focus:ring-2 focus:ring-thamani-accent/15"
      />
    </form>
    """
  end

  attr :variance, :integer, default: nil
  attr :conflict, :boolean, default: false
  attr :applied, :boolean, default: false

  defp variance_badge(assigns) do
    ~H"""
    <span
      :if={@conflict}
      class="inline-flex items-center gap-1 rounded-full bg-rose-100 px-2.5 py-1 text-xs font-semibold text-rose-700"
    >
      <.icon name="hero-exclamation-triangle" class="size-3.5" />
      {if @applied, do: "Conflict", else: "Conflict — not applied"}
    </span>
    <span
      :if={!@conflict and @variance != nil}
      class={[
        "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold",
        cond do
          @variance == 0 -> "bg-emerald-100 text-emerald-700"
          @variance < 0 -> "bg-rose-100 text-rose-700"
          true -> "bg-amber-100 text-amber-800"
        end
      ]}
    >
      {if @variance > 0, do: "+#{@variance}", else: @variance}
    </span>
    <span :if={!@conflict and @variance == nil} class="text-sm text-thamani-subtle">—</span>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :counted_count, :integer, required: true
  attr :on_cancel, :any, required: true

  def finalize_confirmation_modal(assigns) do
    ~H"""
    <.modal :if={@show} id={@id} show on_cancel={@on_cancel}>
      <h2 class="font-semibold mb-2">Finalize this stock take?</h2>
      <p class="text-sm mb-1" style="color: var(--thamani-pewter);">
        This will update stock quantities for the {@counted_count}
        {if @counted_count == 1, do: "batch", else: "batches"} you've counted, to match what
        you counted. This cannot be undone.
      </p>
      <p class="text-sm mb-4" style="color: var(--thamani-pewter);">
        Any batch whose stock has changed since you started counting will be left uncounted
        for a follow-up recount, instead of being overwritten.
      </p>
      <div class="flex gap-2">
        <.button variant="primary" phx-click="finalize" phx-disable-with="Finalizing...">
          Yes, finalize
        </.button>
        <.button phx-click="cancel_finalize">Cancel</.button>
      </div>
    </.modal>
    """
  end

  defp product_name(products_by_id, batch_id, batches_by_id) do
    with %{product_id: product_id} <- batches_by_id[batch_id],
         %{} = product <- products_by_id[product_id] do
      product.generic_name || product.brand_name || "(unnamed)"
    else
      _ -> "(unknown product)"
    end
  end

  defp batch_field(batches_by_id, batch_id, field) do
    Map.get(batches_by_id[batch_id], field)
  end

  defp conflict?(entry, batches_by_id, true = _editable?) do
    batches_by_id[entry.batch_id].remaining_quantity != entry.expected_quantity
  end

  defp conflict?(entry, _batches_by_id, false = _editable?) do
    entry.counted_quantity != nil and !entry.has_been_applied
  end
end
