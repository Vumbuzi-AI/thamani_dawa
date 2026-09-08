defmodule ThamaniDawa.Serialisation do
  @moduledoc """
  Generated identifiers: shipments, SSCCs and serialised codes
  (serialisation.md §5).

  This context owns the *local mirror* of what GS1 issued — enough to list,
  print and export codes without a round trip. It never mints an identifier;
  that only ever happens through `ThamaniDawa.Gs1Api`.

  Everything is organization-scoped, in line with the rest of the app: the
  first argument is an `organization_id`.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Repo
  alias ThamaniDawa.Serialisation.SerialisedCode
  alias ThamaniDawa.Serialisation.SerializationLog
  alias ThamaniDawa.Serialisation.Shipment
  alias ThamaniDawa.Serialisation.Sscc
  alias ThamaniDawa.Serialisation.SsccItem

  @doc """
  Counts issued codes per GTIN for an organization, as
  `%{gtin => %{ssccs: integer, serialised: integer}}`.

  Both sides are counted in one query each rather than per row, since the
  catalog screen asks for this on every page render.

  A GTIN's SSCC count is its number of *distinct* logistics units — a mixed
  pallet carrying five GTINs is one SSCC against each of them, not five (§2.4.4).
  """
  @spec code_counts_by_gtin(integer(), [String.t()]) :: %{String.t() => map()}
  def code_counts_by_gtin(_organization_id, []), do: %{}

  def code_counts_by_gtin(organization_id, gtins) when is_list(gtins) do
    sscc_counts =
      Repo.all(
        from i in SsccItem,
          join: s in Sscc,
          on: s.id == i.sscc_id,
          where: s.organization_id == ^organization_id and i.gtin in ^gtins,
          group_by: i.gtin,
          select: {i.gtin, count(i.sscc_id, :distinct)}
      )
      |> Map.new()

    serialised_counts =
      Repo.all(
        from c in SerialisedCode,
          where: c.organization_id == ^organization_id and c.gtin in ^gtins,
          group_by: c.gtin,
          select: {c.gtin, count(c.id)}
      )
      |> Map.new()

    Map.new(gtins, fn gtin ->
      {gtin,
       %{
         ssccs: Map.get(sscc_counts, gtin, 0),
         serialised: Map.get(serialised_counts, gtin, 0)
       }}
    end)
  end

  @doc "Lists an organization's generation runs, newest first."
  def list_shipments(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Repo.all(
      from s in Shipment,
        where: s.organization_id == ^organization_id,
        order_by: [desc: s.inserted_at, desc: s.id],
        limit: ^limit,
        preload: [:lines]
    )
  end

  @doc "Gets one shipment scoped to an organization. Raises if not found."
  def get_shipment!(organization_id, id) do
    Shipment
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload([:lines, :ssccs, :serialised_codes])
  end

  @doc "Lists the serialised codes issued for a GTIN, oldest first."
  def list_serialised_codes(organization_id, gtin, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Repo.all(
      from c in SerialisedCode,
        where: c.organization_id == ^organization_id and c.gtin == ^gtin,
        order_by: [asc: c.id],
        limit: ^limit,
        preload: [:shipment]
    )
  end

  @doc "Lists the SSCC logistics units containing a GTIN, newest first."
  def list_ssccs_for_gtin(organization_id, gtin, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Repo.all(
      from s in Sscc,
        join: i in SsccItem,
        on: i.sscc_id == s.id,
        where: s.organization_id == ^organization_id and i.gtin == ^gtin,
        distinct: true,
        order_by: [desc: s.id],
        limit: ^limit,
        preload: [:shipment]
    )
  end

  @doc "Lists the SSCCs issued for a shipment, pallets before their cases."
  def list_ssccs(organization_id, shipment_id) do
    Repo.all(
      from s in Sscc,
        where: s.organization_id == ^organization_id and s.shipment_id == ^shipment_id,
        order_by: [asc: s.parent_sscc_id, asc: s.id],
        preload: [:items]
    )
  end

  @doc "Records a generation event (§2.4.11)."
  def log_generation(attrs) do
    %SerializationLog{}
    |> SerializationLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists an organization's generation events, newest first."
  def list_generation_logs(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Repo.all(
      from l in SerializationLog,
        where: l.organization_id == ^organization_id,
        order_by: [desc: l.inserted_at, desc: l.id],
        limit: ^limit
    )
  end

  @doc """
  Totals generated codes for an organization, as
  `%{ssccs: integer, serialised: integer}` — the dashboard's headline numbers.
  """
  def totals(organization_id) do
    %{
      ssccs:
        Repo.aggregate(from(s in Sscc, where: s.organization_id == ^organization_id), :count),
      serialised:
        Repo.aggregate(
          from(c in SerialisedCode, where: c.organization_id == ^organization_id),
          :count
        )
    }
  end
end
