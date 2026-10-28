defmodule ThamaniDawa.AuditLogs do
  @moduledoc "Read-only queries for an organization's audit trail."

  import Ecto.Query

  alias ThamaniDawa.AuditLog
  alias ThamaniDawa.Repo

  def list_audit_logs(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(log in AuditLog,
      where: log.organization_id == ^organization_id,
      order_by: [desc: log.inserted_at, desc: log.id],
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
  end

  def list_record_audit_logs(organization_id, table_name, record_id) do
    from(log in AuditLog,
      where:
        log.organization_id == ^organization_id and log.table_name == ^table_name and
          log.record_id == ^record_id,
      order_by: [desc: log.inserted_at, desc: log.id],
      preload: [:user]
    )
    |> Repo.all()
  end
end
