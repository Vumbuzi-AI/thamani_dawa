defmodule ThamaniDawa.Repo.Migrations.CreateInventoryDisposals do
  use Ecto.Migration

  def change do
    create table(:inventory_disposals) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :site_id, references(:sites, on_delete: :restrict), null: false
      add :kind, :string, null: false
      add :inventory_type, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :reason, :text
      add :notes, :text
      add :admin_id, references(:users, on_delete: :nilify_all)
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :approved_at, :utc_datetime
      add :rejection_reason, :text

      timestamps(type: :utc_datetime)
    end

    create index(:inventory_disposals, [:organization_id])
    create index(:inventory_disposals, [:organization_id, :site_id])
    create index(:inventory_disposals, [:organization_id, :status])
    create index(:inventory_disposals, [:organization_id, :kind])
  end
end
