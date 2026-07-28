defmodule ThamaniDawa.Suppliers.Supplier do
  use Ecto.Schema
  import Ecto.Changeset

  schema "suppliers" do
    field :name, :string
    field :contact, :string
    field :phone, :string
    field :email, :string
    field :gln, :string
    field :location, :string
    field :lat, :float
    field :long, :float
    field :is_active, :boolean, default: true

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :batches, ThamaniDawa.Batches.Batch

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, [:name, :contact, :phone, :email, :location, :lat, :long, :is_active])
    |> validate_required([:name, :phone, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[a-zA-Z]{2,}$/,
      message: "Please enter a valid email (e.g. you@example.com)"
    )
  end
end
