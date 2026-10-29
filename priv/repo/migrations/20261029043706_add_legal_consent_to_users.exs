defmodule ThamaniDawa.Repo.Migrations.AddLegalConsentToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :legal_terms_accepted_at, :utc_datetime
      add :legal_policy_version, :string
    end
  end
end
