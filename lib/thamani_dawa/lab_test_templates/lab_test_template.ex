defmodule ThamaniDawa.LabTestTemplates.LabTestTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.LabTestTemplates.FieldDefinition

  schema "lab_test_templates" do
    field :organization_id, :id
    field :name, :string
    field :short_name, :string
    field :is_active, :boolean, default: true
    field :display_order, :integer
    embeds_many :field_definitions, FieldDefinition, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_test_template, attrs) do
    lab_test_template
    |> cast(attrs, [:name, :short_name, :is_active, :display_order])
    |> cast_embed(:field_definitions, with: &FieldDefinition.changeset/2)
    |> validate_required([:name])
    |> unique_constraint(:name, name: :lab_test_templates_organization_id_name_index)
  end
end
