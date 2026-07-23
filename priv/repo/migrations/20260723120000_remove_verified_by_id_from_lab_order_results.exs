defmodule ThamaniDawa.Repo.Migrations.RemoveVerifiedByIdFromLabOrderResults do
  use Ecto.Migration

  def change do
    alter table(:lab_order_results) do
      remove :verified_by_id, references(:users, on_delete: :nothing), null: true
    end
  end
end
