defmodule ThamaniDawa.Repo.Migrations.AddVerifiedByIdToLabOrderResults do
  use Ecto.Migration

  def change do
    alter table(:lab_order_results) do
      add :verified_by_id, references(:users, on_delete: :nothing), null: true
    end
  end
end
