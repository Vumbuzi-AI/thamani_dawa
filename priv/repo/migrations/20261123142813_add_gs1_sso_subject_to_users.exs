defmodule ThamaniDawa.Repo.Migrations.AddGs1SsoSubjectToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :gs1_sso_sub, :string
    end

    create unique_index(:users, [:gs1_sso_sub])
  end
end
