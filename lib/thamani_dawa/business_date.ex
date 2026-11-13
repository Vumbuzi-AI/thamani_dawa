defmodule ThamaniDawa.BusinessDate do
  @moduledoc """
  Kenya business-calendar helpers.

  Application instants remain UTC. Kenya has a fixed UTC+03:00 offset, so
  business-day decisions use that local calendar date rather than UTC.
  """

  @east_africa_offset_seconds 3 * 60 * 60

  @doc "Returns today's date in East Africa Time."
  def today(now \\ DateTime.utc_now()) do
    now
    |> DateTime.add(@east_africa_offset_seconds, :second)
    |> DateTime.to_date()
  end
end
