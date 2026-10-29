defmodule ThamaniDawa.Repo.Migrations.RemoveUrgencyFromRequisitions do
  use Ecto.Migration

  def change do
    alter table(:requisitions) do
      remove :urgency, :string, default: "routine"
    end
  end
end
