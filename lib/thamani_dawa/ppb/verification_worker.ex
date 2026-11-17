defmodule ThamaniDawa.Ppb.VerificationWorker do
  @moduledoc """
  Oban worker re-verifying a site's PPB facility license against the public
  facilities register after signup (or after a branch is added), mirroring
  `ThamaniDawa.Grp.GlnVerificationWorker`'s pattern. The live check in the
  signup wizard already gates progression and autofills the facility name —
  this job is what actually persists `ppb_verified_at`/`ppb_verification_source`,
  independent of that UI session.
  """

  use Oban.Worker, queue: :ppb, max_attempts: 10

  alias ThamaniDawa.Ppb
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @source "PPB Registry"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_id" => site_id}}) do
    site = Repo.get!(Site, site_id)
    ftype = Site.ppb_ftype(site)

    cond do
      is_nil(ftype) ->
        :ok

      blank?(site.ppb_facility_name) or blank?(site.license_number) ->
        :ok

      true ->
        case Ppb.verify_license(site.ppb_facility_name, site.license_number, ftype) do
          {:ok, :verified, detail} -> mark_verified(site, detail)
          {:ok, :license_inactive, _detail} -> mark_failed(site)
          {:ok, :ambiguous, _candidates} -> mark_failed(site)
          {:error, :name_not_found} -> mark_failed(site)
          {:error, :license_mismatch} -> mark_failed(site)
          {:error, _reason} -> {:error, :ppb_unavailable}
        end
    end
  end

  defp mark_verified(site, detail) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    site
    |> Ecto.Changeset.change(
      ppb_verification_status: :verified,
      ppb_verified_at: now,
      ppb_license_valid_till: parse_date(detail[:valid_till]),
      ppb_verification_source: @source
    )
    |> Repo.update()
  end

  defp mark_failed(site) do
    site
    |> Ecto.Changeset.change(ppb_verification_status: :failed)
    |> Repo.update()
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
