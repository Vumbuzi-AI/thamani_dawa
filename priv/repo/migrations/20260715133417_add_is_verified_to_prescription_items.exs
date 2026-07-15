defmodule ThamaniDawa.Repo.Migrations.AddIsVerifiedToPrescriptionItems do
  use Ecto.Migration

  def change do
    alter table(:prescription_items) do
      add :is_verified, :boolean, default: false, null: false
    end
  end
end
