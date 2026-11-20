defmodule ThamaniDawa.Repo.Migrations.AddGs1ApiKeyToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :gs1_api_key, :binary
      add :gs1_api_key_last4, :string
    end
  end
end
