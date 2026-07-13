defmodule ThamaniDawa.Repo.Migrations.MakeApproverIdNullableOnBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      modify :approver_id, references(:users, on_delete: :nilify_all),
        null: true,
        from: {references(:users, on_delete: :restrict), null: false}
    end
  end
end
