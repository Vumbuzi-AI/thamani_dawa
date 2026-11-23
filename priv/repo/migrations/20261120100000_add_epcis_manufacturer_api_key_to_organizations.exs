defmodule ThamaniDawa.Repo.Migrations.AddEpcisManufacturerApiKeyToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :epcis_manufacturer_api_key, :binary
      add :epcis_manufacturer_api_key_last4, :string
    end
  end
end
