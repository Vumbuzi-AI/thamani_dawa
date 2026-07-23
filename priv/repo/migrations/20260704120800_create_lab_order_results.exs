defmodule ThamaniDawa.Repo.Migrations.CreateLabOrderResults do
  use Ecto.Migration

  def change do
    create table(:lab_order_results) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :lab_order_id, references(:lab_orders, on_delete: :delete_all), null: false
      add :template_id, :integer
      add :results, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :sample_collected_on, :date
      add :test_performed_on, :date
      add :performed_by_id, references(:users, on_delete: :nilify_all)
      add :lab_test_id, references(:lab_tests, on_delete: :restrict), null: false
      add :sample_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lab_order_results, [:organization_id])
    create index(:lab_order_results, [:lab_order_id])
    create index(:lab_order_results, [:performed_by_id])
    create index(:lab_order_results, [:lab_test_id])

    create unique_index(:lab_order_results, [:lab_order_id, :lab_test_id],
             name: :lab_order_results_unique_test_per_order
           )
  end
end
