defmodule ThamaniDawa.Repo.Migrations.DefaultEpcisSubmissionModeToAutomatic do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      modify :epcis_submission_mode, :string,
        null: false,
        default: "automatic",
        from: {:string, null: false, default: "manual"}
    end
  end
end
