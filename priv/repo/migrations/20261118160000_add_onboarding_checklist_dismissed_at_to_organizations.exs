defmodule ThamaniDawa.Repo.Migrations.AddOnboardingChecklistDismissedAtToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :onboarding_checklist_dismissed_at, :utc_datetime
    end
  end
end
