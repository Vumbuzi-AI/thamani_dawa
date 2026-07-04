defmodule ThamaniDawa.Repo.Migrations.CreateDangerousDrugRegisters do
  use Ecto.Migration

  def change do
    create table(:dangerous_drug_registers) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :month, :integer, null: false
      add :year, :integer, null: false
      add :entries, :map, null: false
      add :last_entry_number, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:dangerous_drug_registers, [:organization_id])
    create index(:dangerous_drug_registers, [:site_id])
    create index(:dangerous_drug_registers, [:product_id])
    create unique_index(:dangerous_drug_registers, [:organization_id, :product_id, :month, :year])
  end
end
