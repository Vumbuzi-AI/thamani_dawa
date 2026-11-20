defmodule ThamaniDawa.Repo.Migrations.RemoveLegacyOrganizationVerificationFields do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE organizations
      DROP COLUMN IF EXISTS gln_verification_source,
      DROP COLUMN IF EXISTS kyc_details,
      DROP COLUMN IF EXISTS ppb_facility_name,
      DROP COLUMN IF EXISTS ppb_verification_status,
      DROP COLUMN IF EXISTS ppb_verified_at,
      DROP COLUMN IF EXISTS ppb_license_valid_till,
      DROP COLUMN IF EXISTS ppb_verification_source
    """)
  end

  def down do
    alter table(:organizations) do
      add :gln_verification_source, :string
      add :kyc_details, :map, null: false, default: %{}
      add :ppb_facility_name, :string
      add :ppb_verification_status, :string, default: "pending"
      add :ppb_verified_at, :utc_datetime
      add :ppb_license_valid_till, :date
      add :ppb_verification_source, :string
    end
  end
end
