defmodule ThamaniDawa.QualityAssuranceCharts do
  @moduledoc """
  Site-scoped monthly QA/QC charts (§4.4, §8.3 "Quality assurance"): one
  `quality_assurance_charts` row per `(organization, chart_type, month, year)`,
  holding that month's `daily_entries`.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.QualityAssuranceCharts.QualityAssuranceChart

  @doc "Lists an organization's quality assurance charts."
  def list_quality_assurance_charts(organization_id) do
    Repo.all(from c in QualityAssuranceChart, where: c.organization_id == ^organization_id)
  end

  @doc "Gets a single quality assurance chart scoped to an organization. Raises if not found."
  def get_quality_assurance_chart!(organization_id, id) do
    Repo.get_by!(QualityAssuranceChart, id: id, organization_id: organization_id)
  end

  @doc "Creates a quality assurance chart under the given organization."
  def create_quality_assurance_chart(organization_id, attrs) when is_integer(organization_id) do
    %QualityAssuranceChart{}
    |> QualityAssuranceChart.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc """
  Gets-or-creates the chart row for `(site_id, chart_type, month, year)` and
  merges `entry` into its `daily_entries` map under `day` (cast to a string
  key, since Ecto `:map` fields round-trip through JSON, which only supports
  string keys). Returns `{:ok, chart} | {:error, changeset}`.
  """
  def record_daily_entry(organization_id, site_id, chart_type, month, year, day, entry)
      when is_integer(organization_id) and is_integer(site_id) and is_binary(chart_type) and
             is_integer(month) and is_integer(year) and is_integer(day) and is_map(entry) do
    Repo.transaction(fn ->
      chart = get_or_create_chart(organization_id, site_id, chart_type, month, year)

      chart
      |> Ecto.Changeset.change(daily_entries: Map.put(chart.daily_entries, to_string(day), entry))
      |> Repo.update()
      |> case do
        {:ok, chart} -> chart
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp get_or_create_chart(organization_id, site_id, chart_type, month, year) do
    case Repo.get_by(QualityAssuranceChart,
           organization_id: organization_id,
           chart_type: chart_type,
           month: month,
           year: year
         ) do
      nil ->
        {:ok, chart} =
          create_quality_assurance_chart(organization_id, %{
            site_id: site_id,
            chart_type: chart_type,
            month: month,
            year: year,
            daily_entries: %{}
          })

        chart

      chart ->
        chart
    end
  end
end
