defmodule ThamaniDawa.Repo.Migrations.AddGs1ToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :gs1_company_prefix, :string
      add :next_sscc_serial, :integer, null: false, default: 0
    end
  end
end
