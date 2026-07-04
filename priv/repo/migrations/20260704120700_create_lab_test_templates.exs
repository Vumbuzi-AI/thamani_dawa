defmodule ThamaniDawa.Repo.Migrations.CreateLabTestTemplates do
  use Ecto.Migration

  def change do
    create table(:lab_test_templates) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :short_name, :string
      add :is_active, :boolean, null: false, default: true
      add :display_order, :integer
      add :field_definitions, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:lab_test_templates, [:organization_id])
    create unique_index(:lab_test_templates, [:organization_id, :name])
  end
end
