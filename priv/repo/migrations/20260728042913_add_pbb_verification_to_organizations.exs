defmodule ThamaniDawa.Repo.Migrations.AddPbbVerificationToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :pbb_status, :string, default: "unverified", null: false
      add :pbb_verified_at, :utc_datetime
      add :pbb_meta, :map, default: "{}"
    end
  end
end
