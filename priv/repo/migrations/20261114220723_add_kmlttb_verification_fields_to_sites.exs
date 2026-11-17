defmodule ThamaniDawa.Repo.Migrations.AddKmlttbVerificationFieldsToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :kmlttb_facility_name, :string
      add :kmlttb_license_number, :string
      add :kmlttb_verification_status, :string, default: "pending"
      add :kmlttb_verified_at, :utc_datetime
      add :kmlttb_license_valid_till, :date
      add :kmlttb_verification_source, :string
    end
  end
end
