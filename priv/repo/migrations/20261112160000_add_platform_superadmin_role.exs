defmodule ThamaniDawa.Repo.Migrations.AddPlatformSuperadminRole do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :organization_id, :bigint, null: true
    end
  end
end
