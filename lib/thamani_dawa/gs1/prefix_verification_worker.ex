defmodule ThamaniDawa.Grp.PrefixVerificationWorker do
  @moduledoc """
  Oban worker verifying an organization's GS1 company prefix against the GS1
  GRP licences API after signup (docs/PPB_TNT_INTEGRATION.md §9). Signup never
  waits on this call — account creation proceeds while the job runs, and a
  registry outage only delays the verdict (transient errors retry via Oban).
  """

  use Oban.Worker, queue: :gs1, max_attempts: 10

  import Ecto.Query, warn: false

  alias ThamaniDawa.Grp
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}}) do
    organization = Repo.get!(Organization, organization_id)

    if blank?(organization.gs1_company_prefix) do
      :ok
    else
      case Grp.verify_prefix(organization.gs1_company_prefix) do
        {:ok, :verified, _licence} ->
          update_status(organization, :verified)

        {:ok, :not_verified} ->
          update_status(organization, :failed)

        {:error, _reason} ->
          {:error, :grp_unavailable}
      end
    end
  end

  defp update_status(%Organization{} = organization, status) do
    organization
    |> Ecto.Changeset.change(gs1_prefix_verification_status: status)
    |> Repo.update()
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_prefix), do: false
end
