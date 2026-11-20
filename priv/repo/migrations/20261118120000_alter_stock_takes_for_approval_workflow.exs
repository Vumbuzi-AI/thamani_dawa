defmodule ThamaniDawa.Repo.Migrations.AlterStockTakesForApprovalWorkflow do
  use Ecto.Migration

  def change do
    alter table(:stock_takes) do
      add :inventory_type, :string, null: false, default: "medicine"
      add :rejection_reason, :text
      add :admin_id, references(:users, on_delete: :nilify_all)
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :approved_at, :utc_datetime
    end

    create index(:stock_takes, [:organization_id, :status])
  end
end
