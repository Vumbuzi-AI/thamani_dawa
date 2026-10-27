defmodule ThamaniDawa.DistributorCustomers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_customers" do
    field :name, :string
    field :contact_name, :string
    field :phone, :string
    field :email, :string
    field :address, :string
    field :is_active, :boolean, default: true

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :contact_name, :phone, :email, :address, :is_active])
    |> validate_required([:name])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[a-zA-Z]{2,}$/,
      message: "Please enter a valid email"
    )
    |> unique_constraint(:name, name: :distributor_customers_organization_id_name_index)
  end
end
