defmodule ThamaniDawaWeb.TimeFormat do
  @moduledoc """
  The one place the UI turns timestamps into text. Every screen shows
  East Africa Time (Africa/Nairobi, UTC+3, no daylight saving), formatted
  like `18 Nov 2026, 10:44`. Stored timestamps are UTC.
  """

  @eat_offset 3 * 3600

  @doc "`18 Nov 2026, 10:44` in EAT, or an em dash."
  def datetime(nil), do: "—"
  def datetime(value), do: value |> to_eat() |> Calendar.strftime("%-d %b %Y, %H:%M")

  @doc "`18 Nov, 10:44` in EAT, for dense tables within the current year."
  def short_datetime(nil), do: "—"
  def short_datetime(value), do: value |> to_eat() |> Calendar.strftime("%-d %b, %H:%M")

  @doc "`18 Nov 2026`; timestamps are converted to EAT first."
  def date(nil), do: "—"
  def date(%Date{} = date), do: Calendar.strftime(date, "%-d %b %Y")

  def date(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> date(date)
      _ -> iso
    end
  end

  def date(value), do: value |> to_eat() |> Calendar.strftime("%-d %b %Y")

  @doc "`18 Nov`, for a chart axis. Timestamps are converted to EAT first."
  def month_day(nil), do: "—"
  def month_day(%Date{} = date), do: Calendar.strftime(date, "%-d %b")
  def month_day(value), do: value |> to_eat() |> Calendar.strftime("%-d %b")

  @doc "`Tue 18 Nov`, for a chart tooltip."
  def weekday_day(nil), do: "—"
  def weekday_day(%Date{} = date), do: Calendar.strftime(date, "%a %-d %b")
  def weekday_day(value), do: value |> to_eat() |> Calendar.strftime("%a %-d %b")

  @doc "`Nov 2026`, for a chart axis. Timestamps are converted to EAT first."
  def month_year(nil), do: "—"
  def month_year(%Date{} = date), do: Calendar.strftime(date, "%b %Y")
  def month_year(value), do: value |> to_eat() |> Calendar.strftime("%b %Y")

  def month_short(nil), do: "—"
  def month_short(%Date{} = date), do: Calendar.strftime(date, "%b")
  def month_short(value), do: value |> to_eat() |> Calendar.strftime("%b")

  @doc "Shifts a UTC timestamp to EAT wall-clock time."
  def to_eat(%DateTime{} = dt),
    do:
      dt
      |> DateTime.shift_zone!("Etc/UTC")
      |> DateTime.to_naive()
      |> NaiveDateTime.add(@eat_offset)

  def to_eat(%NaiveDateTime{} = dt), do: NaiveDateTime.add(dt, @eat_offset)
end
