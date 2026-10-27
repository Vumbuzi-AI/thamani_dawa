defmodule ThamaniDawa.Repo.Migrations.CreateDistributorCustomers do
  use Ecto.Migration

  def change do
    create table(:distributor_customers) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :contact_name, :string
      add :phone, :string
      add :email, :string
      add :address, :string
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:distributor_customers, [:organization_id])
    create unique_index(:distributor_customers, [:organization_id, :name])
  end
end
