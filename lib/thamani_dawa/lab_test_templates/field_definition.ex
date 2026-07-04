defmodule ThamaniDawa.LabTestTemplates.FieldDefinition do
  @moduledoc """
  One structured result field on a `lab_test_templates` row: what to label
  it, what unit it's in, and — for numeric fields — the reference range used
  to auto-compute a result's flag (§9 "Lab order → verified result", step 2).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @data_types [:numeric, :text, :select]

  embedded_schema do
    field :key, :string
    field :label, :string
    field :unit, :string
    field :data_type, Ecto.Enum, values: @data_types, default: :numeric
    field :low, :float
    field :high, :float
  end

  @doc false
  def changeset(field_definition, attrs) do
    field_definition
    |> cast(attrs, [:key, :label, :unit, :data_type, :low, :high])
    |> validate_required([:key, :label])
  end

  @doc "The valid field data types, per §4.4 of project.md."
  def data_types, do: @data_types
end
