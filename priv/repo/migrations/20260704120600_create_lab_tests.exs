defmodule ThamaniDawa.Repo.Migrations.CreateLabTests do
  use Ecto.Migration

  def change do
    create table(:lab_tests) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :price, :decimal
      add :subsidized_price, :decimal
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:lab_tests, [:organization_id])
  end
end
