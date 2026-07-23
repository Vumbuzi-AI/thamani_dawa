defmodule ThamaniDawa.Repo.Migrations.CreateLabTestCategories do
  use Ecto.Migration

  def change do
    create table(:lab_test_categories) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :display_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:lab_test_categories, [:organization_id])
    create unique_index(:lab_test_categories, [:organization_id, :name])
  end
end
