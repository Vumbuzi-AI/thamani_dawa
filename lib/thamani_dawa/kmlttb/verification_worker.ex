defmodule ThamaniDawa.Kmlttb.VerificationWorker do
  @moduledoc """
  Oban worker re-verifying a site's KMLTTB lab license against the public
  facilities register after signup, mirroring `ThamaniDawa.Ppb.VerificationWorker`.
  """

  use Oban.Worker, queue: :kmlttb, max_attempts: 10

  alias ThamaniDawa.Kmlttb
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @source "KMLTTB Registry"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_id" => site_id}}) do
    site = Repo.get!(Site, site_id)

    cond do
      not Site.kmlttb_required?(site) ->
        :ok

      blank?(site.kmlttb_facility_name) or blank?(site.kmlttb_license_number) ->
        :ok

      true ->
        case Kmlttb.verify_license(site.kmlttb_facility_name, site.kmlttb_license_number) do
          {:ok, :verified, detail} -> mark_verified(site, detail)
          {:ok, :license_inactive, _detail} -> mark_failed(site)
          {:ok, :ambiguous, _candidates} -> mark_failed(site)
          {:error, :name_not_found} -> mark_failed(site)
          {:error, :license_mismatch} -> mark_failed(site)
          {:error, _reason} -> {:error, :kmlttb_unavailable}
        end
    end
  end

  defp mark_verified(site, detail) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    site
    |> Ecto.Changeset.change(
      kmlttb_verification_status: :verified,
      kmlttb_verified_at: now,
      kmlttb_license_valid_till: parse_date(detail[:valid_until]),
      kmlttb_verification_source: @source
    )
    |> Repo.update()
  end

  defp mark_failed(site) do
    site
    |> Ecto.Changeset.change(kmlttb_verification_status: :failed)
    |> Repo.update()
  end

  @months %{
    "January" => 1,
    "February" => 2,
    "March" => 3,
    "April" => 4,
    "May" => 5,
    "June" => 6,
    "July" => 7,
    "August" => 8,
    "September" => 9,
    "October" => 10,
    "November" => 11,
    "December" => 12
  }

  # KMLTTB's detail page renders this as e.g. "31 December 2026", not ISO8601.
  defp parse_date(value) when is_binary(value) do
    case String.split(value, " ") do
      [day, month, year] ->
        with {day, ""} <- Integer.parse(day),
             {year, ""} <- Integer.parse(year),
             month when not is_nil(month) <- Map.get(@months, month),
             {:ok, date} <- Date.new(year, month, day) do
          date
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_date(_value), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
