defmodule ThamaniDawaWeb.NoNativeDateInputsTest do
  @moduledoc """
  Guard: the browser's native date, time and month inputs (and their calendar
  popups) are not allowed anywhere in the app. Every date field uses
  `<.date_picker>` (or `<.input>` / `<.td_input>` with the date type, which
  render it).
  """
  use ExUnit.Case, async: true

  @native ~r/type=["'{]\s*"?(date|datetime-local|month|week|time)"?\s*}?["']?/

  test "no template or script renders a native date, time or month input" do
    offenders =
      (Path.wildcard("lib/**/*.{ex,heex}") ++ Path.wildcard("assets/js/**/*.{js,ts}"))
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> Regex.match?(@native, line) end)
        |> Enum.map(fn {line, n} -> "#{path}:#{n}: #{String.trim(line)}" end)
      end)

    assert offenders == [],
           "Use <.date_picker> instead of a native date input:\n" <> Enum.join(offenders, "\n")
  end
end
