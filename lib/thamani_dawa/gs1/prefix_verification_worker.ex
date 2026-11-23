defmodule ThamaniDawa.Grp.PrefixVerificationWorker do
  @moduledoc """
  Oban worker verifying one of an organization's GS1 company prefixes
  against the GS1 GRP licences API (docs/PPB_TNT_INTEGRATION.md §9). Enqueued
  whenever a prefix is added from the settings page — adding the prefix
  never waits on this call, a registry outage only delays the verdict
  (transient errors retry via Oban).
  """

  use Oban.Worker, queue: :gs1, max_attempts: 10

  alias ThamaniDawa.Grp
  alias ThamaniDawa.Organizations.OrganizationGs1Prefix
  alias ThamaniDawa.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_gs1_prefix_id" => id}}) do
    case Repo.get(OrganizationGs1Prefix, id) do
      nil ->
        :ok

      prefix ->
        case Grp.verify_prefix(prefix.prefix) do
          {:ok, :verified, _licence} ->
            update_status(prefix, :verified)

          {:ok, :inactive, _licence} ->
            update_status(prefix, :failed)

          {:ok, :not_verified} ->
            update_status(prefix, :failed)

          {:error, _reason} ->
            {:error, :grp_unavailable}
        end
    end
  end

  defp update_status(%OrganizationGs1Prefix{} = prefix, status) do
    now = if status == :verified, do: DateTime.utc_now(:second)

    prefix
    |> Ecto.Changeset.change(verification_status: status, verified_at: now)
    |> Repo.update()
  end
end
