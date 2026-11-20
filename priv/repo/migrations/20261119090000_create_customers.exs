defmodule ThamaniDawa.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :gln, :string
      add :address, :string
      add :customer_type, :string, null: false
      add :license_number, :string
      add :verification_status, :string, null: false, default: "pending"
      add :verified_at, :utc_datetime
      add :verified_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:customers, [:organization_id])
    create unique_index(:customers, [:organization_id, :gln], where: "gln IS NOT NULL")
  end
end
