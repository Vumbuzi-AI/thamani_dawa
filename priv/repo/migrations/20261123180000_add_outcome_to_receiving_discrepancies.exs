defmodule ThamaniDawa.Repo.Migrations.AddOutcomeToReceivingDiscrepancies do
  use Ecto.Migration

  def change do
    alter table(:receiving_discrepancies) do
      add :outcome, :string
      add :resolution_note, :text
    end
  end
end
