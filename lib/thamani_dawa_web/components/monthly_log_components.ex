defmodule ThamaniDawaWeb.MonthlyLogComponents do
  @moduledoc """
  Shared month/year picker + entries-by-key table, used by the three
  "monthly map" screens that share an identical shape: Dangerous drug
  register, Pharmacy logs, and Quality assurance — each resolves one row for
  `(site, some_type, month, year)` and lets staff append dated/numbered
  entries to its `entries`/`daily_entries` map.
  """

  use Phoenix.Component

  attr :month, :integer, required: true
  attr :year, :integer, required: true
  attr :on_change, :string, required: true, doc: "the phx-change event name"
  slot :inner_block, doc: "additional picker fields, e.g. a log_type or product select"

  def month_year_picker(assigns) do
    ~H"""
    <form phx-change={@on_change} class="flex flex-wrap gap-2 items-end mb-4">
      <div>
        <label class="label">Month</label>
        <select name="month" class="select">
          <option :for={m <- 1..12} value={m} selected={m == @month}>{m}</option>
        </select>
      </div>
      <div>
        <label class="label">Year</label>
        <input type="number" name="year" value={@year} class="input w-24" />
      </div>
      {render_slot(@inner_block)}
    </form>
    """
  end

  attr :entries, :map, required: true, doc: "a %{\"1\" => %{...}, \"2\" => %{...}} map, string-keyed"
  attr :key_label, :string, default: "#"

  slot :col, required: true do
    attr :label, :string
  end

  def entries_table(assigns) do
    rows = Enum.sort_by(assigns.entries, fn {key, _entry} -> String.to_integer(key) end)
    assigns = assign(assigns, :rows, rows)

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th>{@key_label}</th>
          <th :for={col <- @col}>{col[:label]}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={{key, entry} <- @rows}>
          <td>{key}</td>
          <td :for={col <- @col}>{render_slot(col, entry)}</td>
        </tr>
      </tbody>
    </table>
    <p :if={@rows == []} class="text-sm text-base-content/70">No entries yet.</p>
    """
  end
end
