defmodule ThamaniDawa.Repo.Migrations.CreateReceivingDiscrepancies do
  use Ecto.Migration

  def change do
    create table(:receiving_discrepancies) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :goods_receipt_id, references(:goods_receipts, on_delete: :delete_all), null: false
      add :sscc, :string
      add :gtin, :string
      add :batch_no, :string
      add :serial, :string
      add :quantity, :integer, null: false
      add :reason, :string, null: false, default: "missing"
      add :status, :string, null: false, default: "open"
      add :resolution_reference, :string
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:receiving_discrepancies, [:organization_id])
    create index(:receiving_discrepancies, [:goods_receipt_id])
    create index(:receiving_discrepancies, [:status])
  end
end
