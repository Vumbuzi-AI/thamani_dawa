defmodule ThamaniDawa.Gs1Api.Request do
  @moduledoc """
  An audit row for one attempted GS1 API call (serialisation.md §4.5).

  Written *before* the call goes out, so a request that dies mid-flight leaves
  a `pending` row behind rather than vanishing. A `pending` row is never
  auto-retried: a retried generation call mints a brand-new code, so
  reconciliation has to be operator-visible.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending succeeded failed)a

  schema "gs1_requests" do
    field :endpoint, :string
    field :request_id, :string
    field :payload_digest, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :response_summary, :map, default: %{}
    field :error_message, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :user, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc "The statuses a request row can hold."
  def statuses, do: @statuses

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :endpoint,
      :request_id,
      :payload_digest,
      :status,
      :response_summary,
      :error_message,
      :organization_id,
      :user_id
    ])
    |> validate_required([:endpoint, :request_id, :payload_digest, :organization_id])
    |> unique_constraint(:request_id)
  end
end
