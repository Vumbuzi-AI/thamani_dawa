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
  alias ThamaniDawa.Serialisation.Label
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

  @doc """
  Lists the batches (SSCC generation runs) recorded for one GTIN, paginated —
  Screen B in ui.md §5.

  Each entry is the shipment plus the counts the batch card shows: how many
  labels were issued for this GTIN, and how many of them are pallets. Counts
  come from two grouped queries over the page, not one query per card.

  Options: `:search` (batch, GTIN, customer part number or order number),
  `:page_size`.
  """
  def list_batches_for_gtin(organization_id, gtin, page \\ 1, opts \\ []) do
    page_result =
      from(s in Shipment, as: :shipment)
      |> where([shipment: s], s.organization_id == ^organization_id and s.type == :sscc)
      |> where(
        [shipment: s],
        exists(
          from i in SsccItem,
            join: c in Sscc,
            on: c.id == i.sscc_id,
            where: c.shipment_id == parent_as(:shipment).id and i.gtin == ^gtin,
            select: 1
        )
      )
      |> filter_shipments(Keyword.get(opts, :search), gtin)
      |> order_by([shipment: s], desc: s.inserted_at, desc: s.id)
      |> Repo.paginate(page: page, page_size: Keyword.get(opts, :page_size, 9))

    counts = label_counts(Enum.map(page_result.entries, & &1.id), gtin)

    entries =
      Enum.map(page_result.entries, fn shipment ->
        %{
          shipment: shipment,
          labels: get_in(counts, [shipment.id, :labels]) || 0,
          pallets: get_in(counts, [shipment.id, :pallets]) || 0
        }
      end)

    %{page_result | entries: entries}
  end

  defp filter_shipments(query, search, gtin) do
    case search && String.trim(search) do
      blank when blank in [nil, ""] ->
        query

      trimmed ->
        pattern = "%#{trimmed}%"

        # A search for the GTIN itself matches every batch on the screen: the
        # list is already scoped to that GTIN, so it must not come back empty.
        if String.contains?(gtin, trimmed) do
          query
        else
          where(
            query,
            [shipment: s],
            ilike(s.batch, ^pattern) or ilike(s.order_number, ^pattern) or
              ilike(s.customer_part_number, ^pattern)
          )
        end
    end
  end

  defp label_counts([], _gtin), do: %{}

  defp label_counts(shipment_ids, gtin) do
    Repo.all(
      from s in Sscc,
        join: i in SsccItem,
        on: i.sscc_id == s.id,
        where: s.shipment_id in ^shipment_ids and i.gtin == ^gtin,
        group_by: s.shipment_id,
        select:
          {s.shipment_id,
           %{
             labels: count(s.id, :distinct),
             pallets: filter(count(s.id, :distinct), s.level == :pallet)
           }}
    )
    |> Map.new()
  end

  @doc """
  The pallet SSCCs issued on one batch, for the pallet-label modal (Screen C).

  Returns `{labels, shipment}`: each label is a `Label` struct already built
  against the shipment, so the modal never assembles artwork itself.
  """
  def list_pallet_labels(organization_id, shipment_id, gtin, opts \\ []) do
    shipment = get_shipment!(organization_id, shipment_id)

    ssccs =
      from(s in Sscc, as: :sscc)
      |> where([sscc: s], s.organization_id == ^organization_id and s.shipment_id == ^shipment_id)
      |> where([sscc: s], s.level == :pallet)
      |> where(
        [sscc: s],
        exists(
          from i in SsccItem,
            where: i.sscc_id == parent_as(:sscc).id and i.gtin == ^gtin,
            select: 1
        )
      )
      |> filter_by_code(Keyword.get(opts, :search))
      |> order_by([sscc: s], asc: s.id)
      |> preload(:items)
      |> Repo.all()

    total = length(ssccs)

    labels =
      ssccs
      |> Enum.with_index(1)
      |> Enum.map(fn {sscc, index} ->
        Label.pallet(sscc, shipment, gtin: gtin, sequence: {index, total})
      end)

    {labels, shipment}
  end

  defp filter_by_code(query, search) do
    case search && String.trim(search) do
      blank when blank in [nil, ""] -> query
      trimmed -> where(query, [sscc: s], ilike(s.code, ^"%#{trimmed}%"))
    end
  end

  @doc """
  Lists serialised-generation results for a GTIN grouped by pallet SSCC —
  Screen D in ui.md §7 — paginated, newest first.

  Each entry carries the shipper and primary-serial counts the card shows.
  Those same numbers back the modal tabs (§7: "card counts and modal counts
  must derive from the same loaded data"), which is why they are counted from
  the stored rows rather than from what GS1 was asked for.
  """
  def list_groups_for_gtin(organization_id, gtin, page \\ 1, opts \\ []) do
    page_result =
      from(s in Sscc, as: :group)
      |> join(:inner, [group: s], sh in Shipment, on: sh.id == s.shipment_id, as: :shipment)
      |> where([group: s], s.organization_id == ^organization_id and s.level == :pallet)
      |> where([shipment: sh], sh.type == :serialised)
      |> where(
        [group: s],
        exists(
          from i in SsccItem,
            where: i.sscc_id == parent_as(:group).id and i.gtin == ^gtin,
            select: 1
        )
      )
      |> filter_groups(Keyword.get(opts, :search), gtin)
      |> order_by([group: s], desc: s.id)
      |> preload([:shipment, :items])
      |> Repo.paginate(page: page, page_size: Keyword.get(opts, :page_size, 9))

    counts = group_counts(Enum.map(page_result.entries, & &1.id))

    entries =
      Enum.map(page_result.entries, fn group ->
        %{
          group: group,
          shippers: get_in(counts, [group.id, :shippers]) || 0,
          primaries: get_in(counts, [group.id, :primaries]) || 0
        }
      end)

    %{page_result | entries: entries}
  end

  defp filter_groups(query, search, gtin) do
    case search && String.trim(search) do
      blank when blank in [nil, ""] ->
        query

      trimmed ->
        if String.contains?(gtin, trimmed) do
          query
        else
          pattern = "%#{trimmed}%"

          where(
            query,
            [group: s, shipment: sh],
            ilike(s.code, ^pattern) or ilike(sh.batch, ^pattern) or
              ilike(sh.order_number, ^pattern)
          )
        end
    end
  end

  defp group_counts([]), do: %{}

  defp group_counts(group_ids) do
    shippers =
      Repo.all(
        from s in Sscc,
          where: s.parent_sscc_id in ^group_ids,
          group_by: s.parent_sscc_id,
          select: {s.parent_sscc_id, count(s.id)}
      )
      |> Map.new()

    # A primary serial hangs off the shipper it was packed into, so it is
    # counted through that shipper's parent rather than off the pallet.
    primaries =
      Repo.all(
        from c in SerialisedCode,
          join: s in Sscc,
          on: s.id == c.sscc_id,
          where: s.parent_sscc_id in ^group_ids,
          group_by: s.parent_sscc_id,
          select: {s.parent_sscc_id, count(c.id)}
      )
      |> Map.new()

    Map.new(group_ids, fn id ->
      {id, %{shippers: Map.get(shippers, id, 0), primaries: Map.get(primaries, id, 0)}}
    end)
  end

  @doc "Gets one pallet SSCC group scoped to an organization, with what it needs to render."
  def get_group!(organization_id, id) do
    Sscc
    |> Repo.get_by!(id: id, organization_id: organization_id, level: :pallet)
    |> Repo.preload([:shipment, :items, children: [:items]])
  end

  @doc """
  Counts one group's shippers and primary serials directly.

  The list screen carries these numbers on the card already; this is the
  fallback for a deep link that opened a modal without loading the list.
  """
  def group_totals(%Sscc{} = group) do
    shipper_ids =
      Repo.all(from s in Sscc, where: s.parent_sscc_id == ^group.id, select: s.id)

    %{
      shippers: length(shipper_ids),
      primaries:
        Repo.aggregate(from(c in SerialisedCode, where: c.sscc_id in ^shipper_ids), :count)
    }
  end

  @doc """
  The shipper labels inside a group, each with the count of primary serials
  assigned to it (ui.md §8, `Serials (N)`).
  """
  def list_shipper_labels(%Sscc{} = group, gtin) do
    shippers =
      Repo.all(
        from s in Sscc,
          where: s.parent_sscc_id == ^group.id,
          order_by: [asc: s.id],
          preload: [:items]
      )

    counts =
      case Enum.map(shippers, & &1.id) do
        [] ->
          %{}

        ids ->
          Repo.all(
            from c in SerialisedCode,
              where: c.sscc_id in ^ids,
              group_by: c.sscc_id,
              select: {c.sscc_id, count(c.id)}
          )
          |> Map.new()
      end

    Enum.map(shippers, fn shipper ->
      %{
        sscc: shipper,
        label: Label.shipper(shipper, group.shipment, gtin: gtin, serial: shipper.serial),
        serials: Map.get(counts, shipper.id, 0)
      }
    end)
  end

  @doc """
  The primary serial labels in a group, or in one shipper of it when
  `:shipper_id` is given.

  Paginated at the query, never in the browser: a serialised run can hold
  millions of rows (ui.md §12).
  """
  def list_primary_labels(organization_id, %Sscc{} = group, opts \\ []) do
    shipper_ids =
      case Keyword.get(opts, :shipper_id) do
        nil -> Enum.map(group.children, & &1.id)
        shipper_id -> [shipper_id]
      end

    page_result =
      SerialisedCode
      |> where([c], c.organization_id == ^organization_id and c.sscc_id in ^shipper_ids)
      |> filter_by_serial(Keyword.get(opts, :search))
      |> order_by([c], asc: c.id)
      |> Repo.paginate(page: Keyword.get(opts, :page, 1), page_size: Keyword.get(opts, :page_size, 25))

    labels = Enum.map(page_result.entries, &Label.primary(&1, group.shipment))

    %{page_result | entries: labels}
  end

  defp filter_by_serial(query, search) do
    case search && String.trim(search) do
      blank when blank in [nil, ""] -> query
      trimmed -> where(query, [c], ilike(c.serial, ^"%#{trimmed}%"))
    end
  end

  @doc """
  Every serialised code in a group, as rows for CSV export (ui.md §13).

  Streams from the database inside a transaction rather than loading the run
  into memory.
  """
  def stream_group_rows(organization_id, %Sscc{} = group) do
    shipper_codes =
      Repo.all(
        from s in Sscc,
          where: s.parent_sscc_id == ^group.id,
          select: {s.id, {s.code, s.serial}}
      )
      |> Map.new()

    from(c in SerialisedCode,
      where: c.organization_id == ^organization_id and c.sscc_id in ^Map.keys(shipper_codes),
      order_by: [asc: c.id]
    )
    |> Repo.stream(max_rows: 500)
    |> Stream.map(fn code ->
      {shipper_sscc, shipper_serial} = Map.get(shipper_codes, code.sscc_id, {nil, nil})

      %{
        pallet_sscc: group.code,
        shipper_sscc: shipper_sscc,
        shipper_serial: shipper_serial,
        gtin: code.gtin,
        serial: code.serial,
        batch: group.shipment.batch,
        production_date: group.shipment.production_date,
        expiry_date: group.shipment.expiry_date,
        order_number: group.shipment.order_number
      }
    end)
  end

  @doc """
  Generates one SSCC through GS1 and records it (ui.md §11).

  Delegated to `ThamaniDawa.Serialisation.Generator`; see there for the
  submit-then-settle sequence that makes an ambiguous timeout recoverable.
  """
  defdelegate generate_sscc(scope, request), to: ThamaniDawa.Serialisation.Generator

  @doc "Generates serialised Data Matrix codes through GS1 and records them (ui.md §11)."
  defdelegate generate_serialised(scope, request), to: ThamaniDawa.Serialisation.Generator

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
