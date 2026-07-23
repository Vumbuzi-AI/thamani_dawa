defmodule ThamaniDawa.Repo.Migrations.CreateSuppliers do
  use Ecto.Migration

  def change do
    create table(:suppliers) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :contact, :string
      add :phone, :string
      add :email, :string
      add :gln, :string
      add :location, :string
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:suppliers, [:organization_id])
  end
end
