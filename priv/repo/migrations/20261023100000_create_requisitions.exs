defmodule ThamaniDawa.Repo.Migrations.CreateRequisitions do
  use Ecto.Migration

  def change do
    create table(:requisitions) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :site_id, references(:sites, on_delete: :restrict), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :requested_by_id, references(:users, on_delete: :restrict), null: false
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :quantity, :integer, null: false
      add :urgency, :string, null: false, default: "routine"
      add :status, :string, null: false, default: "pending"
      add :notes, :text
      add :rejection_reason, :text
      add :needs_reorder, :boolean, null: false, default: false
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:requisitions, [:organization_id])
    create index(:requisitions, [:organization_id, :site_id])
    create index(:requisitions, [:organization_id, :status])
    create index(:requisitions, [:product_id])
  end
end
