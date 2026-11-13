defmodule ThamaniDawa.Grp.GlnVerificationWorker do
  @moduledoc """
  Oban worker verifying a user-entered GLN against the GS1 GRP licences API
  after signup (docs/PPB_TNT_INTEGRATION.md §9). A verified GLN records the
  verification timestamp and source; an unregistered GLN simply stays
  unverified — never a hard failure, and registry outages retry via Oban.
  """

  use Oban.Worker, queue: :gs1, max_attempts: 10

  alias ThamaniDawa.Grp
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @source "GS1 GRP"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"record" => "site", "id" => id}}) do
    verify(Repo.get!(Site, id), &verify_record/1)
  end

  def perform(%Oban.Job{args: %{"record" => "organization", "id" => id}}) do
    verify(Repo.get!(Organization, id), &verify_record/1)
  end

  defp verify(record, _update) when record.gln in [nil, ""], do: :ok

  defp verify(record, update) do
    case Grp.verify_gln(record.gln) do
      {:ok, :verified, _licence} -> update.(record)
      {:ok, :not_verified} -> :ok
      {:error, _reason} -> {:error, :grp_unavailable}
    end
  end

  defp verify_record(record) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    record
    |> Ecto.Changeset.change(gln_verified_at: now, gln_verification_source: @source)
    |> Repo.update()
  end
end
