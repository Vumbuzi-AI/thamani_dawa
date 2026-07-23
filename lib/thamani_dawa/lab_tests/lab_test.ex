defmodule ThamaniDawa.LabTests.LabTest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_tests" do
    field :name, :string
    field :price, :decimal
    field :is_active, :boolean, default: true
    field :field_definitions, :map

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :category, ThamaniDawa.LabTests.LabTestCategory

    has_many :lab_order_results, ThamaniDawa.LabOrders.LabOrderResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_test, attrs) do
    lab_test
    |> cast(attrs, [:name, :price, :is_active, :field_definitions, :category_id])
    |> validate_required([:name, :price, :field_definitions, :category_id])
    |> foreign_key_constraint(:category_id)
  end
end
