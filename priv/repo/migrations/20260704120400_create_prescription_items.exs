defmodule ThamaniDawa.Repo.Migrations.CreatePrescriptionItems do
  use Ecto.Migration

  def change do
    create table(:prescription_items) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :prescription_id, references(:prescriptions, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :quantity_prescribed, :integer, null: false
      add :dosage_instructions, :string
      add :frequency, :string
      add :duration_in_days, :integer
      add :route_of_administration, :string
      add :quantity_dispensed, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:prescription_items, [:organization_id])
    create index(:prescription_items, [:prescription_id])
    create index(:prescription_items, [:product_id])
  end
end
