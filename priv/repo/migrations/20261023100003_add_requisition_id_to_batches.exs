defmodule ThamaniDawa.Repo.Migrations.AddRequisitionIdToBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      add :requisition_id, references(:requisitions, on_delete: :nilify_all)
    end

    create index(:batches, [:requisition_id])
  end
end
