defmodule ThamaniDawa.PharmacyLogs do
  @moduledoc """
  Site-scoped cold-chain logs (§4.3): one `pharmacy_logs` row per
  `(site, log_type, month, year)`, holding that month's `daily_entries`.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.PharmacyLogs.PharmacyLog

  @doc "Lists an organization's pharmacy logs."
  def list_pharmacy_logs(organization_id) do
    Repo.all(from l in PharmacyLog, where: l.organization_id == ^organization_id)
  end

  @doc "Gets a single pharmacy log scoped to an organization. Raises if not found."
  def get_pharmacy_log!(organization_id, id) do
    Repo.get_by!(PharmacyLog, id: id, organization_id: organization_id)
  end

  @doc "Creates a pharmacy log under the given organization."
  def create_pharmacy_log(organization_id, attrs) when is_integer(organization_id) do
    %PharmacyLog{}
    |> PharmacyLog.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc """
  Gets-or-creates the log row for `(site_id, log_type, month, year)` and
  merges `entry` into its `daily_entries` map under `day` (cast to a string
  key, since Ecto `:map` fields round-trip through JSON, which only supports
  string keys). Returns `{:ok, log} | {:error, changeset}`.
  """
  def record_daily_entry(organization_id, site_id, log_type, month, year, day, entry)
      when is_integer(organization_id) and is_integer(site_id) and is_binary(log_type) and
             is_integer(month) and is_integer(year) and is_integer(day) and is_map(entry) do
    Repo.transaction(fn ->
      log = get_or_create_log(organization_id, site_id, log_type, month, year)

      log
      |> Ecto.Changeset.change(daily_entries: Map.put(log.daily_entries, to_string(day), entry))
      |> Repo.update()
      |> case do
        {:ok, log} -> log
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp get_or_create_log(organization_id, site_id, log_type, month, year) do
    case Repo.get_by(PharmacyLog,
           organization_id: organization_id,
           log_type: log_type,
           month: month,
           year: year
         ) do
      nil ->
        {:ok, log} =
          create_pharmacy_log(organization_id, %{
            site_id: site_id,
            log_type: log_type,
            month: month,
            year: year,
            daily_entries: %{}
          })

        log

      log ->
        log
    end
  end
end
