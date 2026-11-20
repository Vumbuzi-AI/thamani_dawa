defmodule ThamaniDawa.StockTakes.StockTake do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.StockTakes.StockTakeItem

  schema "stock_takes" do
    field :inventory_type, Ecto.Enum, values: [:medicine, :lab_consumable]
    field :status, Ecto.Enum, values: [:draft, :pending, :approved, :rejected], default: :draft
    field :notes, :string
    field :rejection_reason, :string
    field :approved_at, :utc_datetime

    belongs_to :organization, Organization
    belongs_to :site, Site
    belongs_to :admin, User, foreign_key: :admin_id
    belongs_to :requested_by, User, foreign_key: :requested_by_id
    belongs_to :approved_by, User, foreign_key: :approved_by_id
    has_many :items, StockTakeItem, foreign_key: :stock_take_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for opening a new draft stock take. Either `admin_id` (an admin
  counting directly) or `requested_by_id` (a requester submitting for
  approval) must be present, but not both.
  """
  def create_changeset(stock_take, attrs) do
    stock_take
    |> cast(attrs, [:site_id, :inventory_type, :notes, :admin_id, :requested_by_id])
    |> validate_required([:site_id, :inventory_type])
    |> validate_requester_or_admin()
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:admin_id)
    |> foreign_key_constraint(:requested_by_id)
  end

  defp validate_requester_or_admin(changeset) do
    admin_id = get_field(changeset, :admin_id)
    requested_by_id = get_field(changeset, :requested_by_id)

    case {admin_id, requested_by_id} do
      {nil, nil} ->
        add_error(changeset, :requested_by_id, "either admin_id or requested_by_id is required")

      {a, r} when not is_nil(a) and not is_nil(r) ->
        add_error(changeset, :admin_id, "only one of admin_id or requested_by_id may be set")

      _ ->
        changeset
    end
  end

  @doc "Changeset applied when a requester submits their draft for approval."
  def submit_changeset(stock_take) do
    change(stock_take, status: :pending)
  end

  @doc "Changeset applied when an admin approves a draft or pending stock take."
  def approve_changeset(stock_take, attrs) do
    stock_take
    |> cast(attrs, [:approved_by_id, :approved_at])
    |> validate_required([:approved_by_id, :approved_at])
    |> foreign_key_constraint(:approved_by_id)
    |> put_change(:status, :approved)
  end

  @doc "Changeset applied when an admin rejects a pending stock take. `rejection_reason` is required."
  def reject_changeset(stock_take, attrs) do
    stock_take
    |> cast(attrs, [:approved_by_id, :approved_at, :rejection_reason])
    |> validate_required([:approved_by_id, :approved_at, :rejection_reason])
    |> foreign_key_constraint(:approved_by_id)
    |> put_change(:status, :rejected)
  end

  @doc "Changeset applied when a requester reopens a pending stock take back to draft."
  def reopen_changeset(stock_take) do
    change(stock_take, status: :draft)
  end
end
