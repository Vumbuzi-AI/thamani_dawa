defmodule ThamaniDawaWeb.DateRangeFilter do
  @moduledoc """
  The presets behind the one shared date-range filter chip
  (`TDComponents.td_date_filter/1`): Any time, Today, Last 7 days, Last 30
  days, This month, or a custom range. Days are counted in EAT.
  """

  alias ThamaniDawaWeb.TimeFormat

  @presets [
    {"", "Any time"},
    {"today", "Today"},
    {"7d", "Last 7 days"},
    {"30d", "Last 30 days"},
    {"month", "This month"}
  ]

  def presets, do: @presets

  @doc "A preset string, or \"custom\" when only explicit dates are given."
  def valid_preset(preset) when preset in ["today", "7d", "30d", "month", "custom"], do: preset
  def valid_preset(_preset), do: ""

  @doc "Resolves a preset or custom range to `{from, to}` dates (either may be nil)."
  def resolve(preset, from, to, today \\ today_eat())
  def resolve("today", _from, _to, today), do: {today, today}
  def resolve("7d", _from, _to, today), do: {Date.add(today, -6), today}
  def resolve("30d", _from, _to, today), do: {Date.add(today, -29), today}
  def resolve("month", _from, _to, today), do: {Date.beginning_of_month(today), today}
  def resolve("custom", from, to, _today), do: {parse(from), parse(to)}
  def resolve(_preset, _from, _to, _today), do: {nil, nil}

  def label("custom", from, to), do: range_caption(from, to, false)

  def label(preset, _from, _to),
    do: Enum.find_value(@presets, "Any time", fn {v, l} -> v == preset && l end)

  def range_caption(from, to, eat? \\ true) do
    text =
      case {parse(from), parse(to)} do
        {nil, nil} -> "Any time"
        {%Date{} = f, nil} -> "From #{TimeFormat.date(f)}"
        {nil, %Date{} = t} -> "Until #{TimeFormat.date(t)}"
        {f, t} -> "#{Calendar.strftime(f, "%-d %b")} to #{TimeFormat.date(t)}"
      end

    if eat? and text != "Any time", do: text <> " · EAT", else: text
  end

  def today_eat, do: DateTime.utc_now() |> TimeFormat.to_eat() |> NaiveDateTime.to_date()

  defp parse(%Date{} = date), do: date

  defp parse(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse(_value), do: nil
end
