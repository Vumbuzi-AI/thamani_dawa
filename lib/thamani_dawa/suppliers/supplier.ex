defmodule ThamaniDawa.Suppliers.Supplier do
  use Ecto.Schema
  import Ecto.Changeset

  schema "suppliers" do
    field :organization_id, :id
    field :name, :string
    field :contact, :string
    field :phone, :string
    field :email, :string
    field :gln, :string
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, [:name, :contact, :phone, :email, :gln, :is_active])
    |> validate_required([:name])
  end
end
