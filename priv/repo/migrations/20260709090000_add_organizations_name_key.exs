defmodule ThamaniDawa.Repo.Migrations.AddOrganizationsNameKey do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    alter table(:organizations) do
      add :name_key, :string
    end

    flush()

    backfill_name_keys()

    flush()

    case duplicate_name_keys() do
      [] ->
        :ok

      duplicates ->
        raise Ecto.MigrationError,
          message: """
          Cannot add a unique index on organizations.name_key: these \
          normalized names are shared by more than one organization and \
          must be resolved (e.g. by renaming one of them) before this \
          migration can proceed: #{inspect(duplicates)}
          """
    end

    execute "CREATE UNIQUE INDEX CONCURRENTLY organizations_name_key_index ON organizations (name_key)"
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS organizations_name_key_index"

    alter table(:organizations) do
      remove :name_key
    end
  end

  defp backfill_name_keys do
    %{rows: rows} = repo().query!("SELECT id, slug FROM organizations")

    Enum.each(rows, fn [id, slug] ->
      repo().query!("UPDATE organizations SET name_key = $1 WHERE id = $2", [
        normalize_name_key(slug),
        id
      ])
    end)
  end

  defp normalize_name_key(nil), do: nil

  defp normalize_name_key(text) do
    case text
         |> String.downcase()
         |> String.normalize(:nfd)
         |> String.replace(~r/[^a-z0-9]/u, "") do
      "" -> nil
      name_key -> name_key
    end
  end

  defp duplicate_name_keys do
    %{rows: rows} =
      repo().query!("""
      SELECT name_key FROM organizations
      WHERE name_key IS NOT NULL
      GROUP BY name_key HAVING count(*) > 1
      """)

    List.flatten(rows)
  end
end
