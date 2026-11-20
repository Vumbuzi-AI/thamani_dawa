defmodule ThamaniDawa.Repo.Migrations.AddEpcisCredentialSettingsToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :epcis_submission_mode, :string, null: false, default: "manual"
      add :epcis_distributor_api_key, :binary
      add :epcis_distributor_api_key_last4, :string
      add :epcis_facility_api_key, :binary
      add :epcis_facility_api_key_last4, :string
    end
  end
end
