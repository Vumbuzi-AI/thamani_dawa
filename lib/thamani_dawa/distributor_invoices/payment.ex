defmodule ThamaniDawa.DistributorInvoices.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_invoice_payments" do
    field :amount, :integer
    field :method, :string
    field :paid_at, :utc_datetime
    field :note, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :invoice, ThamaniDawa.DistributorInvoices.Invoice

    timestamps(type: :utc_datetime)
  end

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:amount, :method, :paid_at, :note])
    |> validate_required([:amount, :method, :paid_at])
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:invoice_id)
  end
end
