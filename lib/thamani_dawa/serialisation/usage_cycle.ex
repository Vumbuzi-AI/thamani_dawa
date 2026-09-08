defmodule ThamaniDawa.Serialisation.UsageCycle do
  @moduledoc """
  A local mirror of one GS1 allowance cycle — a prepay purchase or a postpay
  billing period.

  **Display only.** GS1 is the single enforcer of allowances (§6): it already
  authorizes every generation call against the member's plan, so a second local
  decrement here would only drift. Nothing in this app may treat these counters
  as permission to generate; they exist so the billing screens can show a plan,
  a remaining balance, and an overdue banner without a round trip per render.

  Remaining capacity for a prepay cycle is
  `quantity_limit - running_quantity + (buffer_limit - running_buffer)`:
  draw from the quantity first, spill into the buffer (§2.4.6).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(prepay postpay)a

  schema "serial_usage_cycles" do
    field :gs1_usage_id, :integer
    field :payment_reference, :string
    field :type, Ecto.Enum, values: @types

    field :quantity_limit, :integer, default: 0
    field :buffer_limit, :integer, default: 10_000_000
    field :running_quantity, :integer, default: 0
    field :running_buffer, :integer, default: 0

    field :next_billing_date, :date
    field :overdue, :boolean, default: false
    field :synced_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  @doc "The plan types a cycle can have."
  def types, do: @types

  @doc """
  Serials still available on this cycle, for display.

  A postpay cycle is unbounded until it goes overdue, at which point only the
  buffer remains (§2.4.7) — so it reports `:unlimited` rather than a number.
  """
  def remaining(%__MODULE__{type: :postpay, overdue: false}), do: :unlimited

  def remaining(%__MODULE__{type: :postpay} = cycle), do: buffer_remaining(cycle)

  def remaining(%__MODULE__{} = cycle) do
    max(cycle.quantity_limit - cycle.running_quantity, 0) + buffer_remaining(cycle)
  end

  defp buffer_remaining(cycle), do: max(cycle.buffer_limit - cycle.running_buffer, 0)

  @doc "Whether the cycle has no capacity left at all."
  def exhausted?(%__MODULE__{} = cycle), do: remaining(cycle) == 0

  @doc false
  def changeset(cycle, attrs) do
    cycle
    |> cast(attrs, [
      :gs1_usage_id,
      :payment_reference,
      :type,
      :quantity_limit,
      :buffer_limit,
      :running_quantity,
      :running_buffer,
      :next_billing_date,
      :overdue,
      :synced_at,
      :organization_id
    ])
    |> validate_required([:type, :organization_id])
    |> unique_constraint([:organization_id, :gs1_usage_id],
      name: :serial_usage_cycles_org_gs1_usage_id_index
    )
  end
end
