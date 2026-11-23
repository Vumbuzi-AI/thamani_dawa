defmodule ThamaniDawa.PlatformMonitoring do
  @moduledoc """
  Read-only, cross-organization monitoring queries for the platform console.

  This context deliberately exposes organization metadata and operational
  activity only; it does not return patient records or patient identifiers.
  Authorization remains at the platform LiveView boundary.
  """

  import Ecto.Query

  alias ThamaniDawa.{Accounts.User, AuditLog, Organizations.Organization, Repo, Sites.Site}
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Prescriptions.Prescription

  @doc "A small platform health snapshot suitable for the dashboard header."
  def overview do
    now = DateTime.utc_now()
    day_ago = DateTime.add(now, -86_400, :second)
    month_ago = DateTime.add(now, -30 * 86_400, :second)

    %{
      organizations: Repo.aggregate(Organization, :count),
      active_organizations: Repo.aggregate(from(o in Organization, where: o.is_active), :count),
      active_users: Repo.aggregate(from(u in User, where: u.is_active), :count),
      activity_last_24h:
        Repo.aggregate(from(log in AuditLog, where: log.inserted_at >= ^day_ago), :count),
      prescriptions_last_30d:
        Repo.aggregate(from(p in Prescription, where: p.inserted_at >= ^month_ago), :count),
      lab_orders_last_30d:
        Repo.aggregate(from(o in LabOrder, where: o.inserted_at >= ^month_ago), :count),
      payments_last_30d:
        Repo.aggregate(from(p in Payment, where: p.inserted_at >= ^month_ago), :count)
    }
  end

  @doc "Lists organizations with only operational-health metadata."
  def list_organization_summaries do
    organizations = Repo.all(from o in Organization, order_by: [asc: o.name])

    user_counts = grouped_count(User, :organization_id)
    site_counts = grouped_count(Site, :organization_id)
    latest_activity = latest_activity_by_organization()

    Enum.map(organizations, fn organization ->
      %{
        organization: organization,
        users_count: Map.get(user_counts, organization.id, 0),
        sites_count: Map.get(site_counts, organization.id, 0),
        last_activity_at: Map.get(latest_activity, organization.id)
      }
    end)
  end

  @doc "Returns the newest platform activity across all organizations."
  def list_recent_activity(limit \\ 20) when is_integer(limit) and limit > 0 do
    Repo.all(
      from log in AuditLog,
        order_by: [desc: log.inserted_at, desc: log.id],
        limit: ^limit,
        preload: [:organization, :user]
    )
  end

  @audit_page_size 20

  @doc """
  Paginated, filterable audit records across every organization. Options:
  `organization_id`, `action`, `table_name`, `user_id`, `search` (matches
  table name, organization name, or actor name), and `page`.

  Returns `%{entries:, page_number:, page_size:, total_pages:, total_entries:}`.
  """
  def list_audit_activity(opts \\ []) do
    query =
      from(log in AuditLog, order_by: [desc: log.inserted_at, desc: log.id])
      |> maybe_filter_organization(Keyword.get(opts, :organization_id))
      |> maybe_filter_action(Keyword.get(opts, :action))
      |> maybe_filter_table(Keyword.get(opts, :table_name))
      |> maybe_filter_user(Keyword.get(opts, :user_id))
      |> maybe_search(Keyword.get(opts, :search))

    page_size = @audit_page_size
    total_entries = Repo.aggregate(query, :count, :id)
    total_pages = max(ceil(total_entries / page_size), 1)
    page_number = min(max(Keyword.get(opts, :page, 1), 1), total_pages)

    entries =
      Repo.all(
        from log in query,
          limit: ^page_size,
          offset: ^((page_number - 1) * page_size),
          preload: [:organization, :user]
      )

    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  @doc "Counts of every audited action, for the audit activity dashboard tiles."
  def audit_activity_stats do
    counts =
      Repo.all(from log in AuditLog, group_by: log.action, select: {log.action, count(log.id)})
      |> Map.new()

    %{
      total: Enum.sum(Map.values(counts)),
      insert: Map.get(counts, "insert", 0),
      update: Map.get(counts, "update", 0),
      delete: Map.get(counts, "delete", 0)
    }
  end

  @doc "Distinct table names that have audited activity, for a filter dropdown."
  def list_audited_tables do
    Repo.all(
      from log in AuditLog, distinct: true, select: log.table_name, order_by: log.table_name
    )
  end

  @doc "Distinct actors who have audited activity, for a filter dropdown."
  def list_audit_actors do
    Repo.all(
      from log in AuditLog,
        join: u in assoc(log, :user),
        distinct: true,
        select: %{id: u.id, name: u.name},
        order_by: u.name
    )
  end

  @doc "Organizations without audited activity in the supplied number of days."
  def organizations_needing_attention(days \\ 7) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    list_organization_summaries()
    |> Enum.filter(fn summary ->
      is_nil(summary.last_activity_at) or
        DateTime.compare(summary.last_activity_at, cutoff) == :lt
    end)
  end

  defp grouped_count(schema, foreign_key) do
    from(record in schema,
      where: not is_nil(field(record, ^foreign_key)),
      group_by: field(record, ^foreign_key),
      select: {field(record, ^foreign_key), count(record.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp maybe_filter_organization(query, nil), do: query

  defp maybe_filter_organization(query, organization_id),
    do: where(query, [log], log.organization_id == ^organization_id)

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, action), do: where(query, [log], log.action == ^action)

  defp maybe_filter_table(query, nil), do: query

  defp maybe_filter_table(query, table_name),
    do: where(query, [log], log.table_name == ^table_name)

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [log], log.user_id == ^user_id)

  defp maybe_search(query, term) when term in [nil, ""], do: query

  defp maybe_search(query, term) do
    pattern = "%" <> escape_like(String.trim(term)) <> "%"

    from log in query,
      left_join: org in assoc(log, :organization),
      left_join: usr in assoc(log, :user),
      where:
        ilike(log.table_name, ^pattern) or ilike(org.name, ^pattern) or ilike(usr.name, ^pattern)
  end

  defp escape_like(term), do: Regex.replace(~r/[\\%_]/, term, fn char -> "\\" <> char end)

  defp latest_activity_by_organization do
    from(log in AuditLog,
      group_by: log.organization_id,
      select: {log.organization_id, max(log.inserted_at)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
