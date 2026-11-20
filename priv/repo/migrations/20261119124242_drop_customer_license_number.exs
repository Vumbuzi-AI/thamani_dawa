defmodule ThamaniDawa.Repo.Migrations.DropCustomerLicenseNumber do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      remove :license_number
      remove :verification_status
      remove :verified_at
      remove :verified_by_id
    end
  end
end
