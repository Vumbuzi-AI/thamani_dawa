defmodule ThamaniDawa.Distributor.SerialPayment do
  @moduledoc """
  A payment for serialisation: a prepay bundle purchase (`kind: "prepay"`)
  or the settlement of a flex cycle (`kind: "postpay"`). Paid via M-Pesa
  STK Push (`method: "mpesa"`, confirmed by the Daraja callback) or a
  manually entered reference (`method: "manual"`). A paid payment carries
  an invoice number and doubles as the invoice record.
  """

  use Ecto.Schema

  schema "distributor_serial_payments" do
    field :kind, :string
    field :method, :string
    field :status, :string, default: "pending"
    field :quantity, :integer
    field :buffer_quantity, :integer, default: 0
    field :unit_price, :decimal
    field :amount_excl_vat, :decimal
    field :vat_amount, :decimal
    field :amount, :decimal
    field :phone, :string
    field :provider_reference, :string
    field :manual_reference, :string
    field :failure_reason, :string
    field :paid_at, :utc_datetime
    field :invoice_number, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :serial_usage, ThamaniDawa.Distributor.SerialUsage
    belongs_to :initiated_by, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "Billed quantity: the purchased/settled serials plus any folded-in buffer."
  def billed_quantity(%__MODULE__{quantity: quantity, buffer_quantity: buffer}),
    do: quantity + (buffer || 0)
end
