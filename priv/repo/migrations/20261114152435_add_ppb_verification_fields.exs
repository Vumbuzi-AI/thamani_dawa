defmodule ThamaniDawa.Repo.Migrations.AddPpbVerificationFields do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :ppb_facility_name, :string
      add :ppb_verification_status, :string, default: "pending"
      add :ppb_verified_at, :utc_datetime
      add :ppb_license_valid_till, :date
      add :ppb_verification_source, :string
    end
  end
end
