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
  def date(value), do: value |> to_eat() |> Calendar.strftime("%-d %b %Y")

  @doc "Shifts a UTC timestamp to EAT wall-clock time."
  def to_eat(%DateTime{} = dt),
    do:
      dt
      |> DateTime.shift_zone!("Etc/UTC")
      |> DateTime.to_naive()
      |> NaiveDateTime.add(@eat_offset)

  def to_eat(%NaiveDateTime{} = dt), do: NaiveDateTime.add(dt, @eat_offset)
end
