defmodule ThamaniDawa.Repo.Migrations.CreateOrganizationGs1Prefixes do
  use Ecto.Migration

  def up do
    create table(:organization_gs1_prefixes) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :prefix, :string, null: false
      add :verification_status, :string, null: false, default: "pending"
      add :is_primary, :boolean, null: false, default: false
      add :verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_gs1_prefixes, [:organization_id, :prefix])

    create unique_index(:organization_gs1_prefixes, [:organization_id],
             where: "is_primary",
             name: :one_primary_prefix_per_organization
           )

    execute """
    INSERT INTO organization_gs1_prefixes
      (organization_id, prefix, verification_status, is_primary, inserted_at, updated_at)
    SELECT id, gs1_company_prefix, gs1_prefix_verification_status, true, now(), now()
    FROM organizations
    WHERE gs1_company_prefix IS NOT NULL AND gs1_company_prefix != ''
    """

    alter table(:organizations) do
      remove :gs1_company_prefix, :string
      remove :gs1_prefix_verification_status, :string
    end
  end

  def down do
    alter table(:organizations) do
      add :gs1_company_prefix, :string
      add :gs1_prefix_verification_status, :string, default: "pending"
    end

    execute """
    UPDATE organizations o
    SET gs1_company_prefix = p.prefix, gs1_prefix_verification_status = p.verification_status
    FROM organization_gs1_prefixes p
    WHERE p.organization_id = o.id AND p.is_primary = true
    """

    drop table(:organization_gs1_prefixes)
  end
end
