defmodule ThamaniDawa.DangerousDrugRegisters.DangerousDrugRegister do
  use Ecto.Schema
  import Ecto.Changeset

  schema "dangerous_drug_registers" do
    field :organization_id, :id
    field :site_id, :id
    field :product_id, :id
    field :month, :integer
    field :year, :integer
    field :entries, :map, default: %{}
    field :last_entry_number, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(dangerous_drug_register, attrs) do
    dangerous_drug_register
    |> cast(attrs, [:site_id, :product_id, :month, :year, :entries, :last_entry_number])
    |> validate_required([:site_id, :product_id, :month, :year])
    |> validate_number(:month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:last_entry_number, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint([:organization_id, :product_id, :month, :year])
  end
end
