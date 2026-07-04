defmodule ThamaniDawa.Repo.Migrations.CreateLabOrderTests do
  use Ecto.Migration

  def change do
    create table(:lab_order_tests) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :lab_order_id, references(:lab_orders, on_delete: :delete_all), null: false
      add :lab_test_id, references(:lab_tests, on_delete: :delete_all), null: false
      add :template_id, references(:lab_test_templates, on_delete: :nilify_all)
      add :results, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :sample_collected_on, :date
      add :test_performed_on, :date
      add :performed_by_id, references(:users, on_delete: :nilify_all)
      add :verified_by_id, references(:users, on_delete: :nilify_all)
      add :verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:lab_order_tests, [:organization_id])
    create index(:lab_order_tests, [:lab_order_id])
    create index(:lab_order_tests, [:lab_test_id])
    create index(:lab_order_tests, [:template_id])
    create index(:lab_order_tests, [:performed_by_id])
    create index(:lab_order_tests, [:verified_by_id])
  end
end
