defmodule ThamaniDawa.Customers.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  @customer_types [:pharmacy, :wholesaler, :hospital, :other]

  schema "customers" do
    field :name, :string
    field :gln, :string
    field :address, :string
    field :customer_type, Ecto.Enum, values: @customer_types
    field :contact_name, :string
    field :contact_email, :string
    field :contact_phone, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def customer_types, do: @customer_types

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :gln, :address, :customer_type, :contact_name, :contact_email, :contact_phone, :organization_id])
    |> validate_required([:name, :customer_type, :organization_id],
      message: "can't be blank"
    )
    |> trim_change(:name)
    |> trim_change(:gln)
    |> validate_gln_format()
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint([:organization_id, :gln])
  end

  defp validate_gln_format(changeset) do
    case get_change(changeset, :gln) do
      nil -> changeset
      "" -> changeset
      _gln -> validate_format(changeset, :gln, ~r/^\d{13}$/, message: "must be a 13-digit GLN")
    end
  end

  defp trim_change(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end
end
