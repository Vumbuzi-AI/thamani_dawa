defmodule ThamaniDawa.LabTests.LabTest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_tests" do
    field :organization_id, :id
    field :name, :string
    field :price, :decimal
    field :subsidized_price, :decimal
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:name, :price, :subsidized_price, :is_active])
    |> validate_required([:name])
  end
end
