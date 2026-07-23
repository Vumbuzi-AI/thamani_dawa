defmodule ThamaniDawa.Repo.Migrations.CreateLabTests do
  use Ecto.Migration

  def change do
    create table(:lab_tests) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :price, :decimal, null: false
      add :is_active, :boolean, null: false, default: true
      add :field_definitions, :map, null: false
      add :category_id, references(:lab_test_categories, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lab_tests, [:organization_id])
    create index(:lab_tests, [:category_id])
  end
end
