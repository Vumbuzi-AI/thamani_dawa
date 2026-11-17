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

  @doc "Returns recent audit records with optional organization/action filters."
  def list_audit_activity(opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    action = Keyword.get(opts, :action)
    limit = Keyword.get(opts, :limit, 100)

    from(log in AuditLog,
      order_by: [desc: log.inserted_at, desc: log.id],
      limit: ^limit,
      preload: [:organization, :user]
    )
    |> maybe_filter_organization(organization_id)
    |> maybe_filter_action(action)
    |> Repo.all()
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

  defp latest_activity_by_organization do
    from(log in AuditLog,
      group_by: log.organization_id,
      select: {log.organization_id, max(log.inserted_at)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
