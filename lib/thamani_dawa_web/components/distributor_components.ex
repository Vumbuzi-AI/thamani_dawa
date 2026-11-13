defmodule ThamaniDawaWeb.DistributorComponents do
  @moduledoc """
  Shared UI for the distributor shipment workflow and serialisation billing:
  status badges for string-typed statuses, and money/date formatters.
  """

  use Phoenix.Component

  import ThamaniDawaWeb.CoreComponents, only: [status_badge: 1]

  @shipment_statuses %{
    "draft" => :draft,
    "submitted" => :submitted,
    "approved" => :approved,
    "rejected" => :rejected
  }

  @validation_statuses %{
    "ok" => :ok,
    "unknown_serial" => :unknown_serial,
    "data_mismatch" => :data_mismatch
  }

  @payment_statuses %{"pending" => :pending, "paid" => :paid, "failed" => :failed}

  @doc "Badge for a shipment status (`draft`, `submitted`, `approved`, `rejected`)."
  attr :status, :string, required: true
  attr :class, :any, default: nil

  def shipment_status_badge(assigns) do
    assigns = assign(assigns, :atom, Map.get(@shipment_statuses, assigns.status, :unknown))

    ~H"""
    <.status_badge status={@atom} class={@class} />
    """
  end

  @doc "Badge for a scanned unit's validation status."
  attr :status, :string, required: true
  attr :class, :any, default: nil

  def validation_badge(assigns) do
    assigns = assign(assigns, :atom, Map.get(@validation_statuses, assigns.status, :unknown))

    ~H"""
    <.status_badge status={@atom} class={@class} />
    """
  end

  @doc "Badge for a serialisation payment status."
  attr :status, :string, required: true
  attr :class, :any, default: nil

  def payment_status_badge(assigns) do
    assigns = assign(assigns, :atom, Map.get(@payment_statuses, assigns.status, :unknown))

    ~H"""
    <.status_badge status={@atom} class={@class} />
    """
  end

  @doc "Formats a KES amount with thousands separators and two decimals."
  def kes(nil), do: "KES 0.00"

  def kes(%Decimal{} = amount) do
    [whole, fraction] =
      amount
      |> Decimal.round(2)
      |> Decimal.to_string(:normal)
      |> String.split(".")
      |> case do
        [whole] -> [whole, "00"]
        parts -> parts
      end

    "KES " <> delimit(whole) <> "." <> String.pad_trailing(fraction, 2, "0")
  end

  def kes(amount) when is_integer(amount), do: kes(Decimal.new(amount))

  @doc "Formats an integer with thousands separators."
  def number(nil), do: "0"
  def number(value) when is_integer(value), do: value |> Integer.to_string() |> delimit()

  defp delimit("-" <> digits), do: "-" <> delimit(digits)

  defp delimit(digits) do
    digits
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  @doc "Formats a date as `04 Nov 2026`, or an em dash."
  def short_date(nil), do: "—"
  def short_date(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")
  def short_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%d %b %Y")

  @doc "Formats a timestamp as `04 Nov 2026, 14:05`, or an em dash."
  def date_time(nil), do: "—"
  def date_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%d %b %Y, %H:%M")
end
