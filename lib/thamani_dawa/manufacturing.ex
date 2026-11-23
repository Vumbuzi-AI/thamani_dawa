defmodule ThamaniDawa.Manufacturing do
  @moduledoc """
  Manufacturer operations: GTIN product catalogue, batches, serialised
  DataMatrix codes, and the pallet/shipper SSCC hierarchy packed around
  them. Mirrors the shape of `gs1_admin`'s `ErpLive.Mo` context but every
  table carries `organization_id` directly, matching this app's tenancy
  convention, rather than only the top-level GTIN/pallet/SSCC rows.

  Serial and SSCC codes are minted by the real GS1 member API
  (`ThamaniDawa.GS1.MemberApi`) and persisted here — this context never
  generates a GS1 identifier itself.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Epcis
  alias ThamaniDawa.GS1.MemberApi
  alias ThamaniDawa.Manufacturing.Aggregation
  alias ThamaniDawa.Manufacturing.AggregationItem
  alias ThamaniDawa.Manufacturing.Batch
  alias ThamaniDawa.Manufacturing.Pallet
  alias ThamaniDawa.Manufacturing.Product
  alias ThamaniDawa.Manufacturing.Serial
  alias ThamaniDawa.Manufacturing.Shipment
  alias ThamaniDawa.Manufacturing.ShipmentItem
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Manufacturing.SsccBatch
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo

  @product_page_size 10

  # Products

  @doc "Lists an organization's manufactured products, most recently added first."
  def list_products(organization_id) do
    Repo.all(
      from p in Product,
        where: p.organization_id == ^organization_id,
        order_by: [desc: p.inserted_at, desc: p.id]
    )
  end

  @doc """
  Lists an organization's products with their SSCC and serial counts, for
  the Products page's stats table.
  """
  def list_products_with_counts(organization_id) do
    sscc_counts =
      from s in ShipperSscc,
        where: s.gtin == parent_as(:product).gtin and s.organization_id == ^organization_id,
        select: count(s.id)

    serial_counts =
      from s in Serial,
        where: s.manufacturer_product_id == parent_as(:product).id,
        select: count(s.id)

    Repo.all(
      from p in Product,
        as: :product,
        where: p.organization_id == ^organization_id,
        order_by: [desc: p.inserted_at, desc: p.id],
        select: %{
          product: p,
          sscc_count: subquery(sscc_counts),
          serial_count: subquery(serial_counts)
        }
    )
  end

  def paginate_products_with_counts(organization_id, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, @product_page_size)
    search = opts |> Keyword.get(:search, "") |> to_string() |> String.trim()

    base_query = from p in Product, where: p.organization_id == ^organization_id

    base_query =
      if search == "" do
        base_query
      else
        pattern = "%#{search}%"

        where(
          base_query,
          [p],
          ilike(p.gtin, ^pattern) or ilike(p.name, ^pattern) or
            ilike(coalesce(p.brand_owner, ""), ^pattern) or
            ilike(coalesce(p.description, ""), ^pattern)
        )
      end

    total_entries = Repo.aggregate(base_query, :count)
    total_pages = max(ceil(total_entries / page_size), 1)
    page = min(page, total_pages)

    sscc_counts =
      from s in ShipperSscc,
        where: s.gtin == parent_as(:product).gtin and s.organization_id == ^organization_id,
        select: count(s.id)

    serial_counts =
      from s in Serial,
        where: s.manufacturer_product_id == parent_as(:product).id,
        select: count(s.id)

    entries =
      Repo.all(
        from p in base_query,
          as: :product,
          order_by: [desc: p.inserted_at, desc: p.id],
          limit: ^page_size,
          offset: ^((page - 1) * page_size),
          select: %{
            product: p,
            sscc_count: subquery(sscc_counts),
            serial_count: subquery(serial_counts)
          }
      )

    %{
      entries: entries,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @doc "Fetches a product scoped to the organization."
  def get_product!(organization_id, id) do
    Repo.get_by!(Product, id: id, organization_id: organization_id)
  end

  @doc "Fetches a product by its GTIN, scoped to the organization."
  def get_product_by_gtin!(organization_id, gtin) do
    Repo.get_by!(Product, gtin: gtin, organization_id: organization_id)
  end

  @doc "Total serials and SSCCs generated across an organization's products."
  def generation_counts(organization_id) do
    %{
      serials: count(Serial, organization_id),
      ssccs: count(ShipperSscc, organization_id)
    }
  end

  @doc """
  Returns GS1's current serial and SSCC counts keyed by GTIN.

  These totals include identifiers issued outside this application, so callers
  should prefer them over local counts whenever the member API is available.
  """
  def remote_product_counts(organization_id, opts \\ []) do
    opts = Keyword.put_new(opts, :api_token, Organizations.gs1_api_key(organization_id))

    with {:ok, products} <- MemberApi.list_products(%{}, opts) do
      counts =
        products
        |> Enum.reduce(%{}, fn product, acc ->
          case Map.get(product, "gtin") do
            gtin when is_binary(gtin) and gtin != "" ->
              Map.put(acc, gtin, %{
                serial_count: api_count(product["serial_count"]),
                sscc_count: api_count(product["sscc_count"])
              })

            _other ->
              acc
          end
        end)

      {:ok, counts}
    end
  end

  defp api_count(value) when is_integer(value) and value >= 0, do: value

  defp api_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp api_count(_value), do: 0

  @doc "Changeset for building or editing a product form."
  def change_product(product \\ %Product{}, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  @doc "Creates a manufactured product."
  def create_product(organization_id, attrs) do
    %Product{organization_id: organization_id}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a manufactured product."
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Syncs this organization's product catalogue from the GS1 member API
  (`GET /HBS/products`), upserting by GTIN. Manual add + bulk import still
  work alongside this — a product created by hand is simply adopted (its
  name/description/status refreshed) the first time a sync sees its GTIN.
  """
  def sync_products(organization_id, opts \\ []) do
    opts = Keyword.put_new(opts, :api_token, Organizations.gs1_api_key(organization_id))

    case MemberApi.list_products(%{}, opts) do
      {:ok, products} when is_list(products) ->
        Enum.each(products, &upsert_synced_product(organization_id, &1))
        {:ok, length(products)}

      {:error, _reason} = error ->
        error
    end
  end

  defp upsert_synced_product(organization_id, %{"gtin" => gtin} = attrs) do
    case Repo.get_by(Product, organization_id: organization_id, gtin: gtin) do
      nil -> create_product(organization_id, attrs)
      product -> update_product(product, attrs)
    end
  end

  defp upsert_synced_product(_organization_id, _attrs), do: :ok

  # Batches

  @doc "Lists a product's batches with their serial counts, most recent first."
  def list_batches(organization_id, product_id) do
    serial_counts =
      from s in Serial,
        where: s.manufacturer_batch_id == parent_as(:batch).id,
        select: count(s.id)

    Repo.all(
      from b in Batch,
        as: :batch,
        where: b.organization_id == ^organization_id and b.manufacturer_product_id == ^product_id,
        order_by: [desc: b.inserted_at, desc: b.id],
        select: {b, subquery(serial_counts)}
    )
  end

  @doc "Fetches a batch scoped to the organization."
  def get_batch!(organization_id, id) do
    Repo.get_by!(Batch, id: id, organization_id: organization_id)
  end

  @doc "Changeset for building or editing a batch form."
  def change_batch(batch \\ %Batch{}, attrs \\ %{}) do
    Batch.changeset(batch, attrs)
  end

  @doc "Creates a batch for a product."
  def create_batch(organization_id, product_id, attrs) do
    %Batch{organization_id: organization_id, manufacturer_product_id: product_id}
    |> Batch.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds the product's existing batch by batch number, or creates one — the
  "+ Serial" wizard's step 2 doesn't force picking an existing batch from a
  dropdown, so typing in a batch number that already exists reuses it
  instead of failing the unique constraint.
  """
  def find_or_create_batch(organization_id, product_id, attrs) do
    batch_no = attrs["batch_no"] || attrs[:batch_no]

    case Repo.get_by(Batch,
           organization_id: organization_id,
           manufacturer_product_id: product_id,
           batch_no: batch_no
         ) do
      nil ->
        create_batch(organization_id, product_id, attrs)

      batch ->
        production_date = parse_date(attrs["production_date"] || attrs[:production_date])
        expiry_date = parse_date(attrs["expiry_date"] || attrs[:expiry_date])

        if batch.production_date == production_date and batch.expiry_date == expiry_date do
          {:ok, batch}
        else
          {:error,
           batch
           |> Batch.changeset(attrs)
           |> Ecto.Changeset.add_error(
             :batch_no,
             "already exists with different production or expiry dates"
           )}
        end
    end
  end

  def list_batches_for_serials(organization_id, product_id, search \\ "") do
    search = String.trim(search)

    query =
      from b in Batch,
        left_join: s in Serial,
        on: s.manufacturer_batch_id == b.id,
        where: b.organization_id == ^organization_id,
        where: b.manufacturer_product_id == ^product_id,
        group_by: b.id,
        order_by: [desc: b.inserted_at, desc: b.id],
        select: {b, count(s.id)}

    query =
      if search == "" do
        query
      else
        pattern = "%#{search}%"
        where(query, [b, s], ilike(b.batch_no, ^pattern) or ilike(s.serial, ^pattern))
      end

    Repo.all(query)
  end

  # Serials

  @per_page 50

  @doc """
  One page of a batch's serials, optionally filtered by a serial substring
  — queried and counted in SQL rather than loaded in full, since a batch
  can carry thousands of serials over repeated generation runs.
  """
  def paginate_serials(organization_id, batch_id, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, @per_page)
    search = opts |> Keyword.get(:search, "") |> to_string() |> String.trim()

    base_query =
      from s in Serial,
        where: s.organization_id == ^organization_id and s.manufacturer_batch_id == ^batch_id

    base_query =
      if search == "",
        do: base_query,
        else: where(base_query, [s], ilike(s.serial, ^"%#{search}%"))

    total_entries = Repo.aggregate(base_query, :count)
    total_pages = max(ceil(total_entries / page_size), 1)
    page = min(page, total_pages)

    entries =
      Repo.all(
        from s in base_query,
          order_by: [asc: s.serial],
          limit: ^page_size,
          offset: ^((page - 1) * page_size)
      )

    %{
      entries: entries,
      page_number: page,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  @doc """
  Lists the primary serials packed under a shipper SSCC, read from the GS1
  member API (`POST /get_sscc_contents`) rather than the local database, so
  the list reflects what GS1 has actually recorded for the case — including
  serials issued outside this application.

  Each entry carries its own GTIN, batch, and dates (a case may span several
  batches). Returns `{:ok, serials}` or `{:error, reason}` where reason is
  `:not_found`, `:unconfigured`, `:unauthorized`, `:forbidden`, or
  `:unavailable`.
  """
  def fetch_sscc_serials(organization_id, sscc_code, opts \\ []) when is_binary(sscc_code) do
    opts = Keyword.put_new(opts, :api_token, Organizations.gs1_api_key(organization_id))

    with {:ok, body} <- MemberApi.sscc_contents(sscc_code, opts) do
      serials =
        body
        |> Map.get("products", [])
        |> List.wrap()
        |> Enum.flat_map(&sscc_content_serials/1)
        |> Enum.sort_by(& &1.serial)

      {:ok, serials}
    end
  end

  @doc """
  A product's batches as GS1 records them (`POST /getbarcode_batches`),
  one entry per batch number with its dates and serial count, newest
  production first. Read from the member API, not the local database, so
  serials issued outside this application are included.
  """
  def fetch_product_batches(organization_id, gtin, opts \\ []) when is_binary(gtin) do
    opts = Keyword.put_new(opts, :api_token, Organizations.gs1_api_key(organization_id))

    local_batches =
      Repo.all(
        from b in Batch,
          join: p in assoc(b, :product),
          where: b.organization_id == ^organization_id and p.gtin == ^gtin,
          select: {b.batch_no, %{created_at: b.inserted_at, local_id: b.id}}
      )
      |> Map.new()

    with {:ok, rows} <- MemberApi.barcode_batches(gtin, opts) do
      batches =
        rows
        |> Enum.filter(&(is_binary(&1["batch"]) and &1["batch"] != ""))
        |> Enum.group_by(& &1["batch"])
        |> Enum.map(fn {batch_no, [first | _] = batch_rows} ->
          local = Map.get(local_batches, batch_no, %{created_at: nil, local_id: nil})

          %{
            batch_no: batch_no,
            production_date: parse_api_date(first["production"]),
            expiry_date: parse_api_date(first["expiry"]),
            created_at: local.created_at,
            local_id: local.local_id,
            serial_count: batch_serial_count(batch_rows)
          }
        end)
        |> Enum.sort_by(
          &{
            not is_nil(&1.created_at),
            batch_created_sort_value(&1.created_at),
            &1.local_id || 0,
            &1.production_date || ~D[0000-01-01],
            &1.batch_no
          },
          :desc
        )

      {:ok, batches}
    end
  end

  # GS1 now sends one row per batch with `serial_count`. Older responses sent
  # one row per serial, so count those when the field is missing.
  defp batch_serial_count(rows) do
    if Enum.any?(rows, &is_integer(&1["serial_count"])) do
      rows |> Enum.map(&(&1["serial_count"] || 0)) |> Enum.sum()
    else
      rows
      |> Enum.map(& &1["serial"])
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()
      |> length()
    end
  end

  defp batch_created_sort_value(nil), do: 0
  defp batch_created_sort_value(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)

  defp batch_created_sort_value(%NaiveDateTime{} = value) do
    value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)
  end

  @doc """
  Every serial GS1 has issued for `gtin` + `batch_no`
  (`POST /get_batch_serials`), sorted by serial.
  """
  def fetch_batch_serials(organization_id, gtin, batch_no, opts \\ [])
      when is_binary(gtin) and is_binary(batch_no) do
    opts = Keyword.put_new(opts, :api_token, Organizations.gs1_api_key(organization_id))

    with {:ok, results} <- MemberApi.batch_serials(gtin, batch_no, opts) do
      serials =
        for %{"serial" => serial} = row <- results, is_binary(serial) and serial != "" do
          %{serial: serial, payload: row["payload"], human_readable: row["human_readable"]}
        end

      {:ok, serials |> Enum.uniq_by(& &1.serial) |> Enum.sort_by(& &1.serial)}
    end
  end

  @doc """
  A batch's primary serials that GS1 reports as not yet packed into a
  shipper (`POST /list_unpacked_serials`) — the candidates for
  `pack_serials_into_shipper/5`. Sorted by serial.
  """
  def fetch_unpacked_serials(organization_id, gtin, batch_no, opts \\ [])
      when is_binary(gtin) and is_binary(batch_no) do
    opts = Keyword.put_new(opts, :api_token, Organizations.gs1_api_key(organization_id))

    with {:ok, rows} <- MemberApi.unpacked_serials(gtin, batch_no, opts) do
      serials =
        rows
        |> Enum.filter(
          &(&1["batch"] == batch_no and is_binary(&1["serial"]) and &1["serial"] != "")
        )
        |> Enum.map(& &1["serial"])
        |> Enum.uniq()
        |> Enum.sort()

      {:ok, serials}
    end
  end

  @doc """
  Aggregation-later: packs already-issued, unpacked primary `serials` of one
  batch into a new shipper SSCC minted by GS1 (`POST /create_shipper_sscc`),
  then records the shipper locally and enqueues the EPCIS packing event.

  `batch` is a GS1 batch map (`fetch_product_batches/2`). `attrs` carries
  `"from_gln"` (one of the organization's GLNs), `"to_gln"`, and an optional
  `"order_number"`. `opts[:site_gln]` is the EPCIS business location.
  """
  def pack_serials_into_shipper(organization_id, product, batch, serials, attrs, opts \\ [])

  def pack_serials_into_shipper(_organization_id, _product, _batch, [], _attrs, _opts),
    do: {:error, {:invalid, "Select at least one serial to pack."}}

  def pack_serials_into_shipper(
        organization_id,
        %Product{} = product,
        batch,
        serials,
        attrs,
        opts
      )
      when is_list(serials) do
    from_gln = attrs |> Map.get("from_gln", "") |> String.trim()
    to_gln = attrs |> Map.get("to_gln", "") |> String.trim()
    order_number = attrs |> Map.get("order_number", "") |> String.trim()

    cond do
      not Regex.match?(~r/^\d{13}$/, from_gln) ->
        {:error, {:invalid, "Choose the facility the shipper leaves from."}}

      not Regex.match?(~r/^\d{13}$/, to_gln) ->
        {:error, {:invalid, "Enter the 13-digit GLN the shipper is going to."}}

      true ->
        params =
          %{
            # `barcode` is ignored by GS1; it scopes the request for clarity.
            "barcode" => product.gtin,
            "material_description" => shipper_material_description(product),
            "serials" => serials,
            "from" => %{"gln" => from_gln},
            "to" => %{"gln" => to_gln}
          }
          |> then(
            &if(order_number == "", do: &1, else: Map.put(&1, "order_number", order_number))
          )

        with {:ok, code} <-
               MemberApi.create_shipper_sscc(params,
                 api_token: Organizations.gs1_api_key(organization_id)
               ) do
          record_packed_shipper(
            organization_id,
            product,
            batch,
            serials,
            code,
            packed_party_fields(attrs, from_gln, to_gln, order_number),
            opts
          )
        end
    end
  end

  # From/To details printed on the shipper label. Company and address come
  # from the caller (the chosen facility and GS1 directory result); blanks
  # are stored as nil.
  defp packed_party_fields(attrs, from_gln, to_gln, order_number) do
    blank = fn key ->
      case attrs |> Map.get(key, "") |> to_string() |> String.trim() do
        "" -> nil
        value -> value
      end
    end

    %{
      from_gln: from_gln,
      from_company_name: blank.("from_company_name"),
      from_address: blank.("from_address"),
      to_gln: to_gln,
      to_company_name: blank.("to_company_name"),
      to_address: blank.("to_address"),
      order_number: if(order_number == "", do: nil, else: order_number)
    }
  end

  defp record_packed_shipper(
         organization_id,
         product,
         batch,
         serials,
         code,
         party_fields,
         opts
       ) do
    Repo.transaction(fn ->
      shipper_sscc =
        %ShipperSscc{organization_id: organization_id}
        |> ShipperSscc.changeset(%{
          "code" => code,
          "gtin" => product.gtin,
          "batch" => batch.batch_no,
          "production_date" => batch.production_date,
          "expiry_date" => batch.expiry_date,
          "count_of_trade_items" => length(serials),
          "packed_serials" => serials
        })
        |> Ecto.Changeset.change(party_fields)
        |> Repo.insert!()

      # Mirror onto local rows when this app also holds the batch/serials.
      case Repo.get_by(Batch,
             organization_id: organization_id,
             manufacturer_product_id: product.id,
             batch_no: batch.batch_no
           ) do
        %Batch{} = local_batch ->
          %SsccBatch{}
          |> SsccBatch.changeset(%{
            manufacturer_shipper_sscc_id: shipper_sscc.id,
            manufacturer_batch_id: local_batch.id
          })
          |> Repo.insert!(on_conflict: :nothing)

          from(s in Serial,
            where: s.manufacturer_batch_id == ^local_batch.id and s.serial in ^serials
          )
          |> Repo.update_all(set: [manufacturer_shipper_sscc_id: shipper_sscc.id])

        nil ->
          :ok
      end

      Epcis.record_manufacturer_serial_pack(
        organization_id,
        product,
        shipper_sscc,
        Enum.map(serials, &%{serial: &1}),
        opts[:site_gln]
      )

      record_dispatch_shipment!(organization_id, [shipper_sscc])

      shipper_sscc
    end)
  end

  defp sscc_content_serials(%{} = product) do
    gtin = product["gtin"]
    name = product["name"]

    Enum.flat_map(List.wrap(product["batches"]), fn batch ->
      production_date = parse_api_date(batch["production_date"])
      expiry_date = parse_api_date(batch["expiry_date"])

      for %{"serial" => serial} <- List.wrap(batch["serials"]),
          is_binary(serial) and serial != "" do
        %{
          serial: serial,
          gtin: gtin,
          product_name: name,
          batch: batch["batch"],
          production_date: production_date,
          expiry_date: expiry_date
        }
      end
    end)
  end

  defp sscc_content_serials(_product), do: []

  # GS1 dates arrive as ISO strings ("2026-01-15", optionally with a time)
  # or as the GS1 AI form ("260115").
  defp parse_api_date(<<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2)>>) do
    case Date.from_iso8601("20#{yy}-#{mm}-#{dd}") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_api_date(value) when is_binary(value) do
    case Date.from_iso8601(String.slice(value, 0, 10)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_api_date(_value), do: nil

  @doc "Lists the serials generated for a batch."
  def list_serials(organization_id, batch_id) do
    Repo.all(
      from s in Serial,
        where: s.organization_id == ^organization_id and s.manufacturer_batch_id == ^batch_id,
        order_by: [asc: s.serial]
    )
  end

  @doc """
  Generates serialised DataMatrix codes for `batch` via the GS1 member API,
  persists them locally, optionally persists any shipper SSCCs the call
  minted alongside them, and enqueues the Commission EPCIS event.
  `member_params` extends the call (`trade_item_qty`, `shipper_qty`,
  `from`/`to` GLNs, `create_shippers`); GTIN/batch/dates are taken from
  `product`/`batch`.
  """
  def generate_serials(organization_id, %Product{} = product, %Batch{} = batch, member_params) do
    params =
      member_params
      |> Map.merge(%{
        "barcode" => product.gtin,
        "batch" => batch.batch_no,
        "production" => Date.to_iso8601(batch.production_date),
        "expiry" => Date.to_iso8601(batch.expiry_date)
      })

    api_token = Organizations.gs1_api_key(organization_id)

    with {:ok, result} <- MemberApi.create_serials(params, api_token: api_token) do
      Repo.transaction(fn ->
        serials = persist_serials(organization_id, product, batch, result)
        Epcis.record_manufacturer_commission(organization_id, product, batch, serials)
        {:ok, result}
      end)
      |> case do
        {:ok, {:ok, result}} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def generate_primary_serials(
        organization_id,
        %Product{} = product,
        batch_attrs,
        quantity,
        site_gln
      )
      when is_integer(quantity) and quantity > 0 and is_binary(site_gln) do
    params = %{
      "barcode" => product.gtin,
      "batch" => batch_attrs["batch_no"],
      "production" => batch_attrs["production_date"],
      "expiry" => batch_attrs["expiry_date"],
      "trade_item_qty" => quantity,
      "create_shippers" => false
    }

    api_token = Organizations.gs1_api_key(organization_id)

    with {:ok, result} <- MemberApi.create_serials(params, api_token: api_token) do
      Repo.transaction(fn ->
        with {:ok, batch} <- find_or_create_batch(organization_id, product.id, batch_attrs) do
          serials = persist_serials(organization_id, product, batch, result)
          Epcis.record_manufacturer_commission(organization_id, product, batch, serials, site_gln)
          %{batch: batch, serials: serials, result: result}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def generate_primary_serials(_organization_id, _product, _batch_attrs, _quantity, _site_gln),
    do: {:error, :invalid_quantity}

  @doc """
  Make-to-order path of the "+ Serial" wizard. It generates the primary
  serials first, then packs them into shipper SSCCs through GS1's
  `/create_shipper_sscc` (so GS1 records each shipper's contents) and
  assigns the primary serials locally. `shipper_quantity` is the
  number of primary units in each shipper.
  `parties` carries the From/To GLN/company/address fields printed on the
  shipper labels (string keys: `from_gln`, `from_company_name`,
  `from_address`, `to_gln`, `to_company_name`, `to_address`).
  """
  def generate_order_serials(
        organization_id,
        %Product{} = product,
        batch_attrs,
        primary_quantity,
        shipper_quantity,
        site_gln,
        parties
      )
      when is_integer(primary_quantity) and primary_quantity > 0 and
             is_integer(shipper_quantity) and shipper_quantity > 0 and
             shipper_quantity <= primary_quantity and
             rem(primary_quantity, shipper_quantity) == 0 and is_binary(site_gln) do
    api_token = Organizations.gs1_api_key(organization_id)

    serials_params = %{
      "barcode" => product.gtin,
      "batch" => batch_attrs["batch_no"],
      "production" => batch_attrs["production_date"],
      "expiry" => batch_attrs["expiry_date"],
      "trade_item_qty" => primary_quantity,
      # Keep this request primary-only. The serialisation endpoint does not
      # return enough information to persist shipper-to-serial assignments;
      # shippers are packed below through /create_shipper_sscc.
      "shipper_qty" => primary_quantity + 1,
      "from" => %{"gln" => blank_default(parties["from_gln"], site_gln)},
      "to" => %{"gln" => blank_default(parties["to_gln"], site_gln)}
    }

    with {:ok, result} <- MemberApi.create_serials(serials_params, api_token: api_token) do
      Repo.transaction(fn ->
        with {:ok, batch} <- find_or_create_batch(organization_id, product.id, batch_attrs),
             serials = persist_serials(organization_id, product, batch, result),
             _commission =
               Epcis.record_manufacturer_commission(
                 organization_id,
                 product,
                 batch,
                 serials,
                 site_gln
               ),
             {:ok, pallet} <- create_order_pallet(organization_id, parties),
             {:ok, shippers} <-
               mint_shipper_ssccs(
                 organization_id,
                 product,
                 batch,
                 pallet,
                 serials,
                 shipper_quantity,
                 parties,
                 site_gln,
                 api_token
               ) do
          shipment = record_dispatch_shipment!(organization_id, shippers)

          %{
            batch: batch,
            serials: serials,
            pallet: pallet,
            shippers: shippers,
            shipment: shipment
          }
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def generate_order_serials(
        _organization_id,
        _product,
        _batch_attrs,
        _primary_quantity,
        _shipper_quantity,
        _site_gln,
        _parties
      ),
      do: {:error, :invalid_quantity}

  defp blank_default(value, default) when value in [nil, ""], do: default
  defp blank_default(value, _default), do: value

  defp put_order_number(params, order_number) when is_binary(order_number) do
    case String.trim(order_number) do
      "" -> params
      value -> Map.put(params, "order_number", value)
    end
  end

  defp put_order_number(params, _order_number), do: params

  defp create_order_pallet(organization_id, parties) do
    code = "PAL-" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false)

    %Pallet{organization_id: organization_id}
    |> Pallet.changeset(Map.put(parties, "code", code))
    |> Repo.insert()
  end

  defp mint_shipper_ssccs(
         organization_id,
         product,
         batch,
         pallet,
         serials,
         shipper_quantity,
         parties,
         site_gln,
         api_token
       ) do
    serials
    |> Enum.chunk_every(shipper_quantity)
    |> Enum.reduce_while({:ok, []}, fn group, {:ok, acc} ->
      case mint_shipper_sscc(
             organization_id,
             product,
             batch,
             pallet,
             group,
             parties,
             site_gln,
             api_token
           ) do
        {:ok, shipper} -> {:cont, {:ok, [shipper | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, shippers} -> {:ok, Enum.reverse(shippers)}
      error -> error
    end
  end

  defp mint_shipper_sscc(
         organization_id,
         product,
         batch,
         pallet,
         serials,
         parties,
         site_gln,
         api_token
       ) do
    # Packs these already-issued primary serials into a new shipper, so
    # GS1 knows the shipper's contents (and stops listing them as unpacked).
    shipper_params =
      %{
        "barcode" => product.gtin,
        "material_description" => shipper_material_description(product),
        "serials" => Enum.map(serials, & &1.serial),
        "from" => %{"gln" => parties["from_gln"]},
        "to" => %{"gln" => parties["to_gln"]}
      }
      |> put_order_number(parties["order_number"])

    with {:ok, code} <- MemberApi.create_shipper_sscc(shipper_params, api_token: api_token),
         {:ok, shipper_sscc} <-
           %ShipperSscc{organization_id: organization_id, manufacturer_pallet_id: pallet.id}
           |> ShipperSscc.changeset(
             Map.merge(parties, %{
               "code" => code,
               "gtin" => product.gtin,
               "batch" => batch.batch_no,
               "production_date" => batch.production_date,
               "expiry_date" => batch.expiry_date,
               "count_of_trade_items" => length(serials),
               "packed_serials" => Enum.map(serials, & &1.serial)
             })
           )
           |> Repo.insert(),
         {:ok, _sscc_batch} <-
           %SsccBatch{}
           |> SsccBatch.changeset(%{
             manufacturer_shipper_sscc_id: shipper_sscc.id,
             manufacturer_batch_id: batch.id
           })
           |> Repo.insert() do
      from(s in Serial, where: s.id in ^Enum.map(serials, & &1.id))
      |> Repo.update_all(set: [manufacturer_shipper_sscc_id: shipper_sscc.id])

      Epcis.record_manufacturer_serial_pack(
        organization_id,
        product,
        shipper_sscc,
        serials,
        site_gln
      )

      {:ok, shipper_sscc}
    else
      [] -> {:error, :invalid_shipper_response}
      false -> {:error, :invalid_shipper_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @insert_chunk 1_000

  defp persist_serials(organization_id, product, batch, %{"primary_datamatrices" => codes}) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entries =
      Enum.map(codes, fn %{"serial" => serial} ->
        %{
          organization_id: organization_id,
          manufacturer_product_id: product.id,
          manufacturer_batch_id: batch.id,
          serial: serial,
          inserted_at: now,
          updated_at: now
        }
      end)

    entries
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.flat_map(fn chunk ->
      {_count, inserted} =
        Repo.insert_all(Serial, chunk,
          on_conflict: :nothing,
          conflict_target: [:manufacturer_product_id, :serial],
          returning: true
        )

      inserted
    end)
  end

  defp persist_serials(_organization_id, _product, _batch, _result), do: []

  # Pallets

  @doc "Changeset for building or editing a pallet form."
  def change_pallet(pallet \\ %Pallet{}, attrs \\ %{}) do
    Pallet.changeset(pallet, attrs)
  end

  @doc "Creates a pallet (a free-standing GS1 identifier grouping shipper SSCCs)."
  def create_pallet(organization_id, attrs) do
    %Pallet{organization_id: organization_id}
    |> Pallet.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Fetches a pallet scoped to the organization."
  def get_pallet!(organization_id, id) do
    Pallet
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(shipper_ssccs: [:batches])
  end

  @doc "Lists an organization's manually assembled pallets and their shippers."
  def list_pallets(organization_id) do
    Repo.all(
      from p in Pallet,
        where: p.organization_id == ^organization_id,
        order_by: [desc: p.inserted_at, desc: p.id],
        preload: [shipper_ssccs: [:batches]]
    )
  end

  @doc """
  Creates a pallet SSCC grouping the given shipper SSCCs, which may span
  products and batches. Shippers already on a shipment can't be moved.
  The pallet inherits its parties from the first selected shipper.
  """
  def create_pallet_from_shippers(organization_id, shipper_ids) when is_list(shipper_ids) do
    wanted = MapSet.new(shipper_ids, &to_string/1)

    shippers =
      organization_id
      |> list_available_ssccs()
      |> Enum.filter(&MapSet.member?(wanted, to_string(&1.id)))

    case shippers do
      [] ->
        {:error, :no_shippers}

      [first | _] ->
        parties =
          first
          |> Map.take([
            :from_gln,
            :from_company_name,
            :from_address,
            :to_gln,
            :to_company_name,
            :to_address
          ])
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

        Repo.transaction(fn ->
          case create_order_pallet(organization_id, parties) do
            {:ok, pallet} ->
              from(s in ShipperSscc, where: s.id in ^Enum.map(shippers, & &1.id))
              |> Repo.update_all(set: [manufacturer_pallet_id: pallet.id])

              pallet

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  # Shipper SSCCs

  # A shipper's material description defaults to the product's description,
  # falling back to its name when GS1 has no description for the GTIN.
  defp shipper_material_description(%Product{description: description, name: name}) do
    if is_binary(description) and String.trim(description) != "",
      do: String.trim(description),
      else: name
  end

  @doc "Creates a manually supplied shipper SSCC, inheriting pallet parties when present."
  def create_manual_sscc(organization_id, pallet, attrs) do
    attrs = inherit_pallet_parties(attrs, pallet)

    %ShipperSscc{
      organization_id: organization_id,
      manufacturer_pallet_id: pallet && pallet.id
    }
    |> ShipperSscc.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Mints a shipper SSCC through the GS1 member API, then persists its party details."
  def mint_empty_shipper_sscc(organization_id, pallet, attrs) do
    attrs = inherit_pallet_parties(attrs, pallet)

    params = %{
      "serials" => [],
      "from" => %{"gln" => attrs["from_gln"]},
      "to" => %{"gln" => attrs["to_gln"]}
    }

    with {:ok, code} <-
           MemberApi.create_shipper_sscc(params,
             api_token: Organizations.gs1_api_key(organization_id)
           ) do
      create_manual_sscc(organization_id, pallet, Map.put(attrs, "code", code))
    end
  end

  defp inherit_pallet_parties(attrs, nil), do: attrs

  defp inherit_pallet_parties(attrs, pallet) do
    Map.merge(attrs, %{
      "from_gln" => pallet.from_gln,
      "from_company_name" => pallet.from_company_name,
      "from_address" => pallet.from_address,
      "to_gln" => pallet.to_gln,
      "to_company_name" => pallet.to_company_name,
      "to_address" => pallet.to_address
    })
  end

  @doc "Links an existing organization batch to a manually assembled shipper."
  def add_batch_to_sscc(organization_id, sscc_id, batch_id) do
    with %ShipperSscc{} = sscc <-
           Repo.get_by(ShipperSscc, id: sscc_id, organization_id: organization_id),
         %Batch{} = batch <-
           Repo.get_by(Batch, id: batch_id, organization_id: organization_id) do
      Repo.transaction(fn ->
        %SsccBatch{}
        |> SsccBatch.changeset(%{
          manufacturer_shipper_sscc_id: sscc.id,
          manufacturer_batch_id: batch.id
        })
        |> Repo.insert(on_conflict: :nothing)

        sscc
        |> Ecto.Changeset.change(
          gtin: sscc.gtin || Repo.get!(Product, batch.manufacturer_product_id).gtin,
          count_of_trade_items: count_sscc_serials(sscc.id)
        )
        |> Repo.update!()

        batch
      end)
    else
      nil -> {:error, :not_found}
    end
  end

  @doc "Adds one manually supplied serial to a batch and packs it in the shipper."
  def create_manual_serial(organization_id, batch, sscc, attrs) do
    %Serial{
      organization_id: organization_id,
      manufacturer_product_id: batch.manufacturer_product_id,
      manufacturer_batch_id: batch.id,
      manufacturer_shipper_sscc_id: sscc && sscc.id
    }
    |> Serial.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, serial} ->
        if sscc do
          sscc
          |> Ecto.Changeset.change(count_of_trade_items: count_sscc_serials(sscc.id))
          |> Repo.update!()
        end

        {:ok, serial}

      error ->
        error
    end
  end

  defp count_sscc_serials(sscc_id) do
    Repo.aggregate(
      from(s in Serial, where: s.manufacturer_shipper_sscc_id == ^sscc_id),
      :count,
      :id
    )
  end

  @doc """
  Mints a shipper SSCC via the GS1 member API, persists it (optionally
  under `pallet`), links the given `batches`, and enqueues the Pack
  AggregationEvent.
  """
  def create_sscc(organization_id, product, batches, member_params, opts \\ [])
      when is_list(batches) do
    pallet = Keyword.get(opts, :pallet)

    params =
      Map.merge(member_params, %{
        "material_description" => product.name
      })

    api_token = Organizations.gs1_api_key(organization_id)

    with {:ok, code} <- MemberApi.create_sscc(params, api_token: api_token) do
      Repo.transaction(fn ->
        {:ok, shipper_sscc} =
          %ShipperSscc{
            organization_id: organization_id,
            manufacturer_pallet_id: pallet && pallet.id
          }
          |> ShipperSscc.changeset(
            Map.merge(member_params, %{"code" => code, "gtin" => product.gtin})
          )
          |> Repo.insert()

        Enum.each(batches, fn batch ->
          %SsccBatch{}
          |> SsccBatch.changeset(%{
            manufacturer_shipper_sscc_id: shipper_sscc.id,
            manufacturer_batch_id: batch.id
          })
          |> Repo.insert!()
        end)

        Epcis.record_manufacturer_pack(organization_id, product, shipper_sscc, batches)

        shipper_sscc
      end)
    end
  end

  @doc """
  Per-GTIN pallet-SSCC groups for a product: every shipper SSCC minted for
  this GTIN, with the primary-serial count packed inside it, preloaded with
  its pallet. The product-detail page groups these by pallet into cards —
  "Pallet SSCC code · Batch · GTIN · Produced · Expires · N Shippers · N
  Primary serials" — mirroring `ErpLive.Mo.list_ssccs_with_gtins/3`'s shape,
  scoped by `organization_id` instead of `member_id`.
  """
  def list_sscc_groups(organization_id, product_id) do
    %Product{gtin: gtin} = get_product!(organization_id, product_id)

    from(sscc in ShipperSscc,
      where: sscc.organization_id == ^organization_id and sscc.gtin == ^gtin,
      order_by: [desc: sscc.inserted_at],
      preload: [:pallet, :batches, :serials]
    )
    |> Repo.all()
    |> Enum.map(fn sscc ->
      serials =
        (sscc.packed_serials ++ Enum.map(sscc.serials, & &1.serial))
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.uniq()

      %{sscc: sscc, serials: serials, serial_count: length(serials)}
    end)
  end

  @doc """
  Shipper SSCCs packed from one GTIN + batch, newest first, with a
  `serial => shipper` map covering every primary serial packed into them
  (from the recorded pack list and any mirrored local serial rows).
  """
  def list_batch_shippers(organization_id, gtin, batch_no) do
    shippers =
      Repo.all(
        from s in ShipperSscc,
          where:
            s.organization_id == ^organization_id and s.gtin == ^gtin and
              s.batch == ^batch_no,
          order_by: [desc: s.inserted_at, desc: s.id],
          preload: [
            serials: ^from(se in Serial, select: [:id, :serial, :manufacturer_shipper_sscc_id])
          ]
      )

    by_serial =
      for shipper <- Enum.reverse(shippers),
          serial <- Enum.uniq(shipper.packed_serials ++ Enum.map(shipper.serials, & &1.serial)),
          into: %{},
          do: {serial, shipper}

    {shippers, by_serial}
  end

  @doc """
  Fills in a shipper's missing From/To company and address from its GLNs —
  From from the organization's own sites, To from the GS1 GLN directory —
  and saves them, so shippers packed before parties were recorded get a
  readable label. Shippers inside a pallet print the pallet's parties and
  are returned unchanged, as are GLNs that cannot be resolved.
  """
  def ensure_shipper_parties(organization_id, %ShipperSscc{pallet: nil} = shipper) do
    from_changes =
      with true <- shipper.from_company_name in [nil, ""],
           {:ok, party} <- GlnLookup.resolve_origin(organization_id, shipper.from_gln) do
        %{from_company_name: party.company, from_address: party.address}
      else
        _ -> %{}
      end

    to_changes =
      with true <- shipper.to_company_name in [nil, ""] and is_binary(shipper.to_gln),
           {:ok, party} <-
             GlnLookup.resolve_destination(
               Organizations.gs1_api_key(organization_id),
               shipper.to_gln
             ) do
        %{to_company_name: party.company, to_address: party.address}
      else
        _ -> %{}
      end

    case Map.merge(from_changes, to_changes) do
      changes when changes == %{} ->
        shipper

      changes ->
        case shipper |> Ecto.Changeset.change(changes) |> Repo.update() do
          {:ok, updated} -> updated
          {:error, _changeset} -> shipper
        end
    end
  end

  def ensure_shipper_parties(_organization_id, shipper), do: shipper

  @doc "Fetches a shipper SSCC scoped to the organization, with its pallet preloaded."
  def get_sscc_group!(organization_id, id) do
    ShipperSscc
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload([:pallet, batches: [:product, :serials]])
  end

  # Shipments

  def list_shipments(organization_id) do
    Repo.all(
      from s in Shipment,
        where: s.organization_id == ^organization_id,
        order_by: [desc: s.inserted_at, desc: s.id],
        preload: [:created_by, :shipped_by, shipper_ssccs: :pallet]
    )
  end

  def list_shipments_page(organization_id, opts \\ %{}) do
    query =
      from(s in Shipment, where: s.organization_id == ^organization_id)
      |> filter_shipment_status(opts[:status])
      |> search_shipments(opts[:search])
      |> filter_shipment_date_from(opts[:date_from])
      |> filter_shipment_date_to(opts[:date_to])

    total_entries = Repo.aggregate(query, :count, :id)
    total_pages = max(ceil(total_entries / 20), 1)
    page_number = min(max(opts[:page] || 1, 1), total_pages)

    entries =
      Repo.all(
        from s in query,
          order_by: [desc: s.updated_at, desc: s.id],
          limit: 20,
          offset: ^((page_number - 1) * 20),
          preload: [:created_by, :shipped_by, shipper_ssccs: :pallet]
      )

    %{
      entries: entries,
      page_number: page_number,
      page_size: 20,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  defp filter_shipment_status(query, status) when status in ~w(draft submitted approved rejected),
    do: where(query, [s], s.status == ^status)

  defp filter_shipment_status(query, _status), do: query

  defp search_shipments(query, term) when term in [nil, ""], do: query

  defp search_shipments(query, term) do
    pattern = "%#{String.replace(String.trim(term), ["%", "_"], "")}%"

    where(
      query,
      [s],
      ilike(s.reference, ^pattern) or ilike(s.order_number, ^pattern) or
        ilike(s.origin_gln, ^pattern) or ilike(s.destination_gln, ^pattern) or
        ilike(s.origin_company, ^pattern) or ilike(s.destination_company, ^pattern)
    )
  end

  defp filter_shipment_date_from(query, %Date{} = date),
    do: where(query, [s], s.inserted_at >= ^DateTime.new!(date, ~T[00:00:00], "Etc/UTC"))

  defp filter_shipment_date_from(query, _date), do: query

  defp filter_shipment_date_to(query, %Date{} = date),
    do:
      where(
        query,
        [s],
        s.inserted_at < ^DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
      )

  defp filter_shipment_date_to(query, _date), do: query

  def get_shipment!(organization_id, id) do
    Shipment
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload([:created_by, :shipped_by, shipper_ssccs: :pallet])
  end

  def change_shipment(shipment \\ %Shipment{}, attrs \\ %{}),
    do: Shipment.changeset(shipment, attrs)

  def list_available_ssccs(organization_id) do
    used = from i in ShipmentItem, select: i.manufacturer_shipper_sscc_id

    Repo.all(
      from s in ShipperSscc,
        where: s.organization_id == ^organization_id and s.id not in subquery(used),
        order_by: [desc: s.inserted_at, desc: s.id],
        preload: [:pallet, :batches]
    )
  end

  def create_shipment(organization_id, user, attrs, sscc_ids) when is_list(sscc_ids) do
    changeset =
      %Shipment{
        organization_id: organization_id,
        created_by_id: user.id,
        reference: shipment_reference()
      }
      |> Shipment.changeset(attrs)
      |> resolve_shipment_parties(organization_id)

    Repo.transaction(fn ->
      with false <- sscc_ids == [],
           {:ok, shipment} <- Repo.insert(changeset),
           {:ok, ssccs} <- available_ssccs(organization_id, sscc_ids) do
        Enum.each(ssccs, fn sscc ->
          %ShipmentItem{}
          |> ShipmentItem.changeset(%{
            manufacturer_shipment_id: shipment.id,
            manufacturer_shipper_sscc_id: sscc.id
          })
          |> Repo.insert!()
        end)

        get_shipment!(organization_id, shipment.id)
      else
        true -> Repo.rollback(:no_ssccs)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def submit_shipment(organization_id, id),
    do: transition_shipment(organization_id, id, "draft", status: "submitted")

  def approve_shipment(organization_id, user, id) do
    Repo.transaction(fn ->
      shipment =
        Repo.one!(
          from s in Shipment,
            where: s.id == ^id and s.organization_id == ^organization_id,
            lock: "FOR UPDATE",
            preload: [:shipper_ssccs]
        )

      if shipment.status != "submitted", do: Repo.rollback({:invalid_state, shipment.status})
      if shipment.shipper_ssccs == [], do: Repo.rollback(:no_ssccs)
      shipped_at = DateTime.utc_now() |> DateTime.truncate(:second)

      shipment =
        shipment
        |> Ecto.Changeset.change(
          status: "approved",
          shipped_at: shipped_at,
          shipped_by_id: user.id
        )
        |> Repo.update!()

      Epcis.record_manufacturer_ship(
        organization_id,
        shipment.id,
        Enum.map(shipment.shipper_ssccs, & &1.code),
        shipment.origin_gln,
        shipment.destination_gln,
        shipment.order_number,
        shipped_at
      )

      get_shipment!(organization_id, shipment.id)
    end)
  end

  defp transition_shipment(organization_id, id, expected_status, changes) do
    Repo.transaction(fn ->
      shipment =
        Repo.one!(
          from s in Shipment,
            where: s.id == ^id and s.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      if shipment.status != expected_status,
        do: Repo.rollback({:invalid_state, shipment.status})

      shipment
      |> Ecto.Changeset.change(changes)
      |> Repo.update!()
      |> then(&get_shipment!(organization_id, &1.id))
    end)
  end

  defp available_ssccs(organization_id, ids) do
    ids = ids |> Enum.uniq() |> Enum.map(&parse_id/1)

    taken = from i in ShipmentItem, select: i.manufacturer_shipper_sscc_id

    ssccs =
      Repo.all(
        from s in ShipperSscc,
          where: s.organization_id == ^organization_id and s.id in ^ids,
          where: s.id not in subquery(taken)
      )

    if length(ssccs) == length(ids), do: {:ok, ssccs}, else: {:error, :sscc_unavailable}
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(id) when is_binary(id), do: String.to_integer(id)

  defp resolve_shipment_parties(changeset, organization_id) do
    origin_gln = Ecto.Changeset.get_field(changeset, :origin_gln)
    destination_gln = Ecto.Changeset.get_field(changeset, :destination_gln)

    changeset
    |> resolve_party(
      :origin,
      ThamaniDawa.Distributor.GlnLookup.resolve_origin(organization_id, origin_gln)
    )
    |> resolve_party(
      :destination,
      ThamaniDawa.Distributor.GlnLookup.resolve_party(destination_gln)
    )
  end

  defp resolve_party(changeset, side, {:ok, party}) do
    Ecto.Changeset.change(changeset, %{
      :"#{side}_company" => party.company,
      :"#{side}_address" => party.address
    })
  end

  defp resolve_party(changeset, side, {:error, :not_found}),
    do: Ecto.Changeset.add_error(changeset, :"#{side}_gln", "could not be verified")

  # Minting shipper SSCCs for dispatch (make-to-order, or packing stock
  # into a shipper) is itself the shipment: record an already-approved
  # shipment over those shippers and enqueue its EPCIS Ship event. Parties
  # come from the first shipper's label fields, so no GLN lookup is needed.
  defp record_dispatch_shipment!(organization_id, [%ShipperSscc{} = first | _] = shippers) do
    shipped_at = DateTime.utc_now() |> DateTime.truncate(:second)
    reference = shipment_reference()

    shipment =
      %Shipment{organization_id: organization_id}
      |> Ecto.Changeset.change(%{
        reference: reference,
        order_number: blank_default(first.order_number, reference),
        status: "approved",
        shipped_at: shipped_at,
        origin_gln: first.from_gln,
        origin_company: blank_default(first.from_company_name, first.from_gln),
        origin_address: first.from_address,
        destination_gln: first.to_gln,
        destination_company: blank_default(first.to_company_name, first.to_gln),
        destination_address: first.to_address
      })
      |> Repo.insert!()

    Enum.each(shippers, fn sscc ->
      %ShipmentItem{}
      |> ShipmentItem.changeset(%{
        manufacturer_shipment_id: shipment.id,
        manufacturer_shipper_sscc_id: sscc.id
      })
      |> Repo.insert!()
    end)

    Epcis.record_manufacturer_ship(
      organization_id,
      shipment.id,
      Enum.map(shippers, & &1.code),
      shipment.origin_gln,
      shipment.destination_gln,
      shipment.order_number,
      shipped_at
    )

    shipment
  end

  defp shipment_reference,
    do: "MSH-" <> Base.encode32(:crypto.strong_rand_bytes(5), padding: false)

  # Aggregations

  @aggregation_page_size 20

  @doc "Lists an organization's shipper SSCCs for the aggregation form's picker."
  def available_ssccs_for_aggregation(organization_id) do
    Repo.all(
      from s in ShipperSscc,
        where: s.organization_id == ^organization_id,
        order_by: [desc: s.inserted_at, desc: s.id],
        preload: [:batches]
    )
  end

  @doc """
  Classifies a scanned serial against an SSCC without writing anything:
  `"unknown_serial"`, `"wrong_batch"`, `"already_aggregated"` or `"ok"`,
  paired with the serial record when one exists.
  """
  def classify_serial(organization_id, %ShipperSscc{} = sscc, serial_string) do
    serial_value = serial_string |> to_string() |> String.trim()

    case Repo.get_by(Serial, organization_id: organization_id, serial: serial_value) do
      nil ->
        {"unknown_serial", nil}

      serial ->
        batch_ids =
          Repo.all(
            from sb in SsccBatch,
              where: sb.manufacturer_shipper_sscc_id == ^sscc.id,
              select: sb.manufacturer_batch_id
          )

        cond do
          serial.manufacturer_batch_id not in batch_ids ->
            {"wrong_batch", serial}

          serial.manufacturer_shipper_sscc_id &&
              serial.manufacturer_shipper_sscc_id != sscc.id ->
            {"already_aggregated", serial}

          true ->
            {"ok", serial}
        end
    end
  end

  @doc "One filtered, searched, paginated page of an organization's aggregations."
  def list_aggregations(organization_id, opts \\ %{}) do
    query =
      from(a in Aggregation, where: a.organization_id == ^organization_id)
      |> filter_aggregation_status(opts[:status])
      |> search_aggregations(opts[:search])

    total_entries = Repo.aggregate(query, :count, :id)
    total_pages = max(ceil(total_entries / @aggregation_page_size), 1)
    page_number = min(max(opts[:page] || 1, 1), total_pages)

    item_counts =
      from i in AggregationItem,
        where: i.manufacturer_aggregation_id == parent_as(:agg).id,
        select: count(i.id)

    entries =
      Repo.all(
        from a in query,
          as: :agg,
          order_by: [desc: a.updated_at, desc: a.id],
          limit: @aggregation_page_size,
          offset: ^((page_number - 1) * @aggregation_page_size),
          select_merge: %{item_count: subquery(item_counts)},
          preload: [:shipper_sscc, :created_by]
      )

    %{
      entries: entries,
      page_number: page_number,
      page_size: @aggregation_page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  defp filter_aggregation_status(query, status)
       when status in ~w(draft submitted approved rejected),
       do: where(query, [a], a.status == ^status)

  defp filter_aggregation_status(query, _status), do: query

  defp search_aggregations(query, term) when term in [nil, ""], do: query

  defp search_aggregations(query, term) do
    pattern = "%#{String.replace(String.trim(term), ["%", "_"], "")}%"
    where(query, [a], ilike(a.reference, ^pattern))
  end

  @doc "Fetches an aggregation scoped to the organization, ready for review."
  def get_aggregation!(organization_id, id) do
    Aggregation
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(
      shipper_sscc: :batches,
      items: [],
      created_by: [],
      approved_by: [],
      rejected_by: []
    )
  end

  def change_aggregation(aggregation \\ %Aggregation{}, attrs \\ %{}),
    do: Aggregation.changeset(aggregation, attrs)

  @doc "Creates a draft aggregation targeting an existing shipper SSCC."
  def create_aggregation(organization_id, user, sscc_id) do
    %Aggregation{organization_id: organization_id, created_by_id: user.id}
    |> Aggregation.changeset(%{
      reference: aggregation_reference(),
      status: "draft",
      manufacturer_shipper_sscc_id: parse_id(sscc_id)
    })
    |> Repo.insert()
  end

  @doc """
  Scans one serial into an aggregation — the seam the mobile API will call.
  The SSCC is resolved from the aggregation, the serial is classified, and
  the resulting item is recorded even when its validation status is not
  `"ok"`, so an operator can see and correct it on review.
  """
  def scan_aggregation_item(organization_id, %Aggregation{} = aggregation, raw_or_serial) do
    sscc =
      Repo.get_by!(ShipperSscc,
        id: aggregation.manufacturer_shipper_sscc_id,
        organization_id: organization_id
      )

    {status, serial_record} = classify_serial(organization_id, sscc, raw_or_serial)
    serial_value = raw_or_serial |> to_string() |> String.trim()

    %AggregationItem{organization_id: organization_id}
    |> AggregationItem.changeset(%{
      manufacturer_aggregation_id: aggregation.id,
      manufacturer_serial_id: serial_record && serial_record.id,
      raw_data_matrix: to_string(raw_or_serial),
      serial: serial_value,
      gtin: sscc.gtin,
      validation_status: status,
      scanned_at: now()
    })
    |> Repo.insert()
  end

  @doc "Creates a draft, scans the given serial strings, then submits it for review."
  def create_submitted_aggregation(organization_id, user, sscc_id, serial_strings) do
    Repo.transaction(fn ->
      case create_aggregation(organization_id, user, sscc_id) do
        {:ok, aggregation} ->
          scan_all!(organization_id, aggregation, serial_strings)
          mark_submitted!(organization_id, aggregation)

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp scan_all!(organization_id, aggregation, serial_strings) do
    Enum.each(serial_strings, &scan_one!(organization_id, aggregation, &1))
  end

  defp scan_one!(organization_id, aggregation, serial) do
    case scan_aggregation_item(organization_id, aggregation, serial) do
      {:ok, _item} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp mark_submitted!(organization_id, aggregation) do
    aggregation
    |> Ecto.Changeset.change(status: "submitted", submitted_at: now())
    |> Repo.update!()
    |> then(&get_aggregation!(organization_id, &1.id))
  end

  @doc "Moves a draft aggregation to submitted under a row lock."
  def submit_aggregation(organization_id, id) do
    Repo.transaction(fn ->
      aggregation =
        Repo.one!(
          from a in Aggregation,
            where: a.id == ^id and a.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      if aggregation.status != "draft",
        do: Repo.rollback({:invalid_state, aggregation.status})

      aggregation
      |> Ecto.Changeset.change(status: "submitted", submitted_at: now())
      |> Repo.update!()
      |> then(&get_aggregation!(organization_id, &1.id))
    end)
  end

  @doc """
  Approves a submitted aggregation: re-classifies every item, checks the
  target SSCC's capacity, commits the serial-to-SSCC linkage, and enqueues
  the manufacturer EPCIS Pack event.
  """
  def approve_aggregation(organization_id, user, id) do
    Repo.transaction(fn ->
      aggregation =
        Repo.one!(
          from a in Aggregation,
            where: a.id == ^id and a.organization_id == ^organization_id,
            lock: "FOR UPDATE",
            preload: [items: [], shipper_sscc: :batches]
        )

      if aggregation.status != "submitted",
        do: Repo.rollback({:invalid_state, aggregation.status})

      sscc = aggregation.shipper_sscc

      classified =
        Enum.map(aggregation.items, fn item ->
          {item, classify_serial(organization_id, sscc, item.serial)}
        end)

      invalid =
        for {item, {status, _serial}} <- classified, status != "ok", do: item

      if invalid != [], do: Repo.rollback({:invalid, invalid})

      serial_records = Enum.map(classified, fn {_item, {_status, serial}} -> serial end)
      adding = length(serial_records)

      linked =
        Repo.aggregate(
          from(s in Serial,
            where:
              s.organization_id == ^organization_id and
                s.manufacturer_shipper_sscc_id == ^sscc.id
          ),
          :count,
          :id
        )

      capacity = sscc.count_of_trade_items || 0

      if linked + adding > capacity do
        Repo.rollback({:over_capacity, %{capacity: capacity, linked: linked, adding: adding}})
      end

      Repo.update_all(
        from(s in Serial, where: s.id in ^Enum.map(serial_records, & &1.id)),
        set: [manufacturer_shipper_sscc_id: sscc.id]
      )

      product = aggregation_product(organization_id, sscc, serial_records)

      if is_nil(product), do: Repo.rollback(:missing_product)

      Epcis.record_manufacturer_serial_pack(
        organization_id,
        product,
        sscc,
        serial_records,
        sscc.from_gln
      )

      aggregation
      |> Ecto.Changeset.change(
        status: "approved",
        approved_at: now(),
        approved_by_id: user.id
      )
      |> Repo.update!()
      |> then(&get_aggregation!(organization_id, &1.id))
    end)
  end

  @doc "Rejects a submitted aggregation with a reason."
  def reject_aggregation(organization_id, user, id, reason) do
    reason = String.trim(reason || "")

    Repo.transaction(fn ->
      aggregation =
        Repo.one!(
          from a in Aggregation,
            where: a.id == ^id and a.organization_id == ^organization_id,
            lock: "FOR UPDATE"
        )

      if aggregation.status != "submitted",
        do: Repo.rollback({:invalid_state, aggregation.status})

      aggregation
      |> Ecto.Changeset.change(
        status: "rejected",
        rejection_reason: reason,
        rejected_at: now(),
        rejected_by_id: user.id
      )
      |> Repo.update!()
      |> then(&get_aggregation!(organization_id, &1.id))
    end)
  end

  defp aggregation_product(organization_id, sscc, serial_records) do
    Repo.get_by(Product, organization_id: organization_id, gtin: sscc.gtin) ||
      Enum.find_value(serial_records, fn serial ->
        Repo.get_by(Product, organization_id: organization_id, id: serial.manufacturer_product_id)
      end)
  end

  defp aggregation_reference,
    do: "MAG-" <> Base.encode32(:crypto.strong_rand_bytes(5), padding: false)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # Dashboard

  @doc "Products/batches/serials/pallets/SSCCs counts for an organization's dashboard."
  def dashboard_counts(organization_id) do
    %{
      products: count(Product, organization_id),
      batches: count(Batch, organization_id),
      serials: count(Serial, organization_id),
      pallets: count(Pallet, organization_id),
      ssccs: count(ShipperSscc, organization_id)
    }
  end

  @doc """
  Data for the manufacturer dashboard (Doop ssU7S65tZF): the latest batches
  with their serial counts ("Recent serial jobs") and the aggregation
  pipeline (open aggregations, SSCCs not yet on a shipment, shipments
  shipped in the last 7 days).
  """
  def dashboard_summary(organization_id, limit \\ 5) do
    serial_counts =
      from s in Serial,
        where: s.organization_id == ^organization_id,
        group_by: s.manufacturer_batch_id,
        select: %{batch_id: s.manufacturer_batch_id, count: count(s.id)}

    recent_jobs =
      Repo.all(
        from b in Batch,
          join: p in assoc(b, :product),
          left_join: c in subquery(serial_counts),
          on: c.batch_id == b.id,
          where: b.organization_id == ^organization_id,
          order_by: [desc: b.inserted_at, desc: b.id],
          limit: ^limit,
          select: %{
            batch_id: b.id,
            batch_no: b.batch_no,
            product_id: p.id,
            product_name: p.name,
            gtin: p.gtin,
            serials: coalesce(c.count, 0)
          }
      )

    used = from i in ShipmentItem, select: i.manufacturer_shipper_sscc_id
    week_ago = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)

    %{
      recent_jobs: recent_jobs,
      open_aggregations:
        Repo.aggregate(
          from(a in Aggregation,
            where: a.organization_id == ^organization_id and a.status in ["draft", "submitted"]
          ),
          :count
        ),
      ready_to_ship:
        Repo.aggregate(
          from(s in ShipperSscc,
            where: s.organization_id == ^organization_id and s.id not in subquery(used)
          ),
          :count
        ),
      shipped_this_week:
        Repo.aggregate(
          from(s in Shipment,
            where:
              s.organization_id == ^organization_id and not is_nil(s.shipped_at) and
                s.shipped_at >= ^week_ago
          ),
          :count
        )
    }
  end

  defp count(schema, organization_id) do
    Repo.aggregate(from(r in schema, where: r.organization_id == ^organization_id), :count)
  end

  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp parse_date(_value), do: nil
end
