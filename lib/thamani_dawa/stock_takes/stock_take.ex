defmodule ThamaniDawa.StockTakes.StockTake do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:draft, :completed]

  schema "stock_takes" do
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :notes, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :started_by, ThamaniDawa.Accounts.User
    belongs_to :completed_by, ThamaniDawa.Accounts.User

    has_many :entries, ThamaniDawa.StockTakes.StockTakeEntry

    timestamps(type: :utc_datetime)
  end

  @doc "The valid stock take statuses."
  def statuses, do: @statuses

  @doc """
  Changeset for starting a new stock take. Only `:notes` is cast from caller attrs —
  `site_id`, `status`, `started_at`, `started_by_id`, and `organization_id` are
  system-controlled and must be `put_change/3`'d by the caller before `finish_changeset/1`
  validates them.
  """
  def changeset(stock_take, attrs) do
    cast(stock_take, attrs, [:notes])
  end

  @doc "Validates the system-controlled fields once the caller has put_change/3'd them."
  def finish_changeset(changeset) do
    changeset
    |> validate_required([:site_id, :status, :started_at, :started_by_id])
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:started_by_id)
    |> unique_constraint([:organization_id, :site_id],
      name: :stock_takes_one_draft_per_site_index,
      message: "already has a stock take in progress"
    )
  end

  @doc """
  Changeset for finalizing a stock take. Takes no attrs — `completed_by_id`/`completed_at`
  must already be set via `put_change/3` by the caller before this runs.
  """
  def complete_changeset(stock_take) do
    stock_take
    |> change(status: :completed)
    |> validate_required([:completed_by_id, :completed_at])
    |> foreign_key_constraint(:completed_by_id)
  end
end
