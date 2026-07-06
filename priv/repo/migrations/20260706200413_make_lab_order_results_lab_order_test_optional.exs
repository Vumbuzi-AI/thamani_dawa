defmodule ThamaniDawa.Repo.Migrations.MakeLabOrderResultsLabOrderTestOptional do
  use Ecto.Migration

  def change do
    alter table(:lab_order_results) do
      modify :lab_order_test_id, :integer, null: true
    end
  end
end
