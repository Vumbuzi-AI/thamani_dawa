defmodule ThamaniDawa.Sales.Sale do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:completed, :cancelled]

  schema "sales" do
    field :total_amount, :decimal
    field :has_paid, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :completed

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :user, ThamaniDawa.Accounts.User

    has_many :items, ThamaniDawa.Sales.SaleItem
    has_many :payments, ThamaniDawa.Payments.Payment

    timestamps(type: :utc_datetime)
  end

  def changeset(sale, attrs) do
    sale
    |> cast(attrs, [:site_id, :user_id, :total_amount, :has_paid, :status])
    |> validate_required([:site_id, :total_amount])
    |> validate_number(:total_amount, greater_than: 0)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:user_id)
  end
end
