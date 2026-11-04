defmodule ThamaniDawa.Repo.Migrations.CreateLabOrderResultAmendments do
  use Ecto.Migration

  def change do
    create table(:lab_order_result_amendments) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      add :lab_order_result_id, references(:lab_order_results, on_delete: :delete_all),
        null: false

      add :previous_results, :map, null: false
      add :previous_test_performed_on, :date
      add :previous_performed_by_id, references(:users, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :amended_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:lab_order_result_amendments, [:organization_id])
    create index(:lab_order_result_amendments, [:lab_order_result_id])
  end
end
