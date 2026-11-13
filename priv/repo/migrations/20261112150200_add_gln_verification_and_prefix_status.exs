defmodule ThamaniDawa.Repo.Migrations.AddGlnVerificationAndPrefixStatus do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :gln_verified_at, :utc_datetime
      add :gln_verification_source, :string
      add :gs1_prefix_verification_status, :string, default: "pending"
    end

    alter table(:sites) do
      add :gln_verified_at, :utc_datetime
      add :gln_verification_source, :string
    end

    alter table(:suppliers) do
      add :gln_verified_at, :utc_datetime
      add :gln_verification_source, :string
    end

    alter table(:distributor_customers) do
      add :gln_verified_at, :utc_datetime
      add :gln_verification_source, :string
    end
  end
end
