defmodule ThamaniDawa.Distributor.SerialUsage do
  @moduledoc """
  A serialisation allowance cycle. An organization has at most one
  `"active"` usage row at a time.

    * `"prepay"` — a purchased bundle: `quantity_limit` serials, of which
      `running_quantity` have been used. Usage beyond the limit (up to the
      configured buffer) accrues in `running_buffer` and is folded into the
      next purchase.
    * `"flex"` — pay-as-you-go: uncapped (`quantity_limit` is nil);
      `running_quantity` counts up until the cycle is settled. Once a cycle
      is past its `billing_date` it is overdue, and further usage is capped
      by the buffer limit (accrued in `running_buffer`) until it is paid.
  """

  use Ecto.Schema

  schema "distributor_serial_usages" do
    field :type, :string
    field :status, :string, default: "active"
    field :quantity_limit, :integer
    field :running_quantity, :integer, default: 0
    field :running_buffer, :integer, default: 0
    field :cycle_started_at, :utc_datetime
    field :billing_date, :utc_datetime
    field :closed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  @doc "Serials still available on a prepay bundle (never negative)."
  def serials_left(%__MODULE__{type: "prepay", quantity_limit: limit, running_quantity: used}),
    do: max((limit || 0) - used, 0)

  def serials_left(_usage), do: nil

  @doc "Total generated in the cycle, including buffer usage."
  def generated(%__MODULE__{running_quantity: quantity, running_buffer: buffer}),
    do: quantity + buffer

  @doc "Whether a flex cycle is past its billing date."
  def overdue?(usage, now \\ DateTime.utc_now())

  def overdue?(%__MODULE__{type: "flex", billing_date: %DateTime{} = billing_date}, now),
    do: DateTime.compare(now, billing_date) == :gt

  def overdue?(_usage, _now), do: false
end
