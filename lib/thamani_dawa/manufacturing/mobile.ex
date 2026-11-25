defmodule ThamaniDawa.Manufacturing.Mobile do
  @moduledoc """
  Manufacturer packer-app operations: lot list, parties, draft boxes,
  exclusive serial claims, and Save that mints a shipper SSCC.
  """

  import Ecto.Query, warn: false

  require Logger

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Distributor.MobileUser
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Manufacturing.Batch
  alias ThamaniDawa.Manufacturing.PackBox
  alias ThamaniDawa.Manufacturing.PackBoxScan
  alias ThamaniDawa.Manufacturing.Product
  alias ThamaniDawa.Manufacturing.Serial
  alias ThamaniDawa.Repo

  def list_batches(organization_id, %MobileUser{} = mobile_user) do
    drafts = drafts_by_batch_id(organization_id, mobile_user.id)

    organization_id
    |> local_batches()
    |> Enum.map(&batch_payload(&1, drafts, nil, :summary))
  end

  def get_batch(organization_id, id, %MobileUser{} = mobile_user) do
    with {:ok, batch} <- fetch_batch(organization_id, id) do
      batch = repair_issued(organization_id, batch)
      drafts = drafts_by_batch_id(organization_id, mobile_user.id)
      {:ok, batch_payload(batch, drafts, mobile_user, :full)}
    end
  end

  def resolve_line(organization_id, raw, %MobileUser{} = mobile_user) when is_binary(raw) do
    raw = String.trim(raw)

    result =
      if raw == "" do
        {:error, :unreadable}
      else
        do_resolve_line(organization_id, raw, mobile_user)
      end

    Logger.info("pack-line resolve org=#{organization_id} raw=#{inspect(String.slice(raw, 0, 48))} result=#{inspect(pack_line_result(result))}")
    result
  end

  def resolve_line(_organization_id, _raw, _mobile_user), do: {:error, :bad_request}

  def search_glns(organization_id, query) do
    term = query |> to_string() |> String.trim()

    origins =
      organization_id
      |> GlnLookup.search_origin(term, 8)
      |> Enum.map(&%{gln: &1.gln, name: &1.name, address: &1.address})

    destinations =
      if String.length(term) < 2 do
        []
      else
        case GlnLookup.search_destination(Organizations.gs1_api_key(organization_id), term, 25) do
          {:ok, rows} ->
            Enum.map(rows, &%{gln: &1.gln, name: &1.company || &1.gln, address: &1.address})

          {:error, _} ->
            []
        end
      end

    (origins ++ destinations)
    |> Enum.reject(&(&1.gln in [nil, ""]))
    |> Enum.uniq_by(& &1.gln)
  end

  def save_parties(organization_id, id, from_gln, to_gln, %MobileUser{} = mobile_user) do
    from_gln = trim(from_gln)
    to_gln = trim(to_gln)

    cond do
      not gln?(from_gln) or not gln?(to_gln) ->
        {:error, :invalid_gln}

      from_gln == to_gln ->
        {:error, :same_party}

      true ->
        with {:ok, batch} <- fetch_batch(organization_id, id) do
          attrs = %{
            from_gln: from_gln,
            from_name: party_name(organization_id, from_gln, :from),
            to_gln: to_gln,
            to_name: party_name(organization_id, to_gln, :to)
          }

          case batch |> Batch.parties_changeset(attrs) |> Repo.update() do
            {:ok, batch} ->
              get_batch(organization_id, batch.id, mobile_user)

            {:error, %Ecto.Changeset{} = changeset} ->
              parties_changeset_error(changeset)
          end
        end
    end
  end

  def open_box(organization_id, id, %MobileUser{} = mobile_user) do
    result =
      with {:ok, batch} <- fetch_batch(organization_id, id),
           :ok <- parties_present(batch, mobile_user),
           batch <- repair_issued(organization_id, batch),
           :ok <- ensure_loose_serials(batch, mobile_user) do
        case existing_draft(organization_id, mobile_user.id, batch.id) do
          %PackBox{} = box ->
            {:ok, :existing, box_payload(preload_box(box))}

          nil ->
            insert_draft(organization_id, mobile_user, batch)
        end
      end

    Logger.info("pack-line open_box org=#{organization_id} batch=#{id} result=#{inspect(pack_line_result(result))}")
    result
  end

  def get_box(organization_id, box_id, %MobileUser{} = mobile_user) do
    with {:ok, box} <- fetch_owned_box(organization_id, mobile_user.id, box_id) do
      {:ok, box_payload(box)}
    end
  end

  def claim_scan(organization_id, box_id, raw, %MobileUser{} = mobile_user) do
    result =
      with {:ok, box} <- fetch_owned_draft(organization_id, mobile_user.id, box_id),
           {:ok, serial, parsed} <- resolve_serial(box, raw),
           :ok <- match_batch(box, parsed) do
        Logger.info(
          "pack-line claim box=#{box_id} box_batch=#{box.batch.id}/#{box.batch.batch_no} serial=#{inspect(serial)} parsed_gtin=#{inspect(parsed[:gtin])} parsed_batch=#{inspect(parsed[:batch_no])}"
        )

        case Enum.find(box.scans, &(&1.serial == serial)) do
          %PackBoxScan{} ->
            {:ok, :repeat, scan_payload(box, serial)}

          nil ->
            with :ok <- ensure_unpacked(organization_id, box, serial) do
              insert_claim(box, serial)
            end
        end
      end

    Logger.info("pack-line claim_scan org=#{organization_id} box=#{box_id} result=#{inspect(pack_line_result(result))}")
    result
  end

  def release_scan(organization_id, box_id, serial, %MobileUser{} = mobile_user) do
    serial = trim(serial)

    with {:ok, box} <- fetch_owned_box(organization_id, mobile_user.id, box_id) do
      cond do
        box.status != "draft" ->
          {:error, :not_editable}

        true ->
          {count, _} =
            Repo.delete_all(
              from s in PackBoxScan,
                where: s.box_id == ^box.id and s.serial == ^serial
            )

          if count == 1, do: :ok, else: {:error, :not_found}
      end
    end
  end

  def save_box(organization_id, box_id, idempotency_key, %MobileUser{} = mobile_user) do
    idempotency_key = trim(idempotency_key)

    cond do
      idempotency_key == "" ->
        {:error, :bad_request}

      true ->
        Repo.transaction(fn ->
          with {:ok, box} <- lock_owned_box(organization_id, mobile_user.id, box_id) do
            case do_save_box(organization_id, box, idempotency_key, mobile_user) do
              {:ok, payload} -> payload
              {:error, reason} -> Repo.rollback(reason)
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
    end
  end

  def claimed_serials(organization_id, gtin, batch_no)
      when is_binary(gtin) and is_binary(batch_no) do
    Repo.all(
      from s in PackBoxScan,
        join: b in PackBox,
        on: b.id == s.box_id,
        join: batch in Batch,
        on: batch.id == b.manufacturer_batch_id,
        join: p in Product,
        on: p.id == batch.manufacturer_product_id,
        where: s.organization_id == ^organization_id,
        where: p.gtin == ^gtin and batch.batch_no == ^batch_no,
        select: s.serial
    )
  end

  defp do_save_box(_organization_id, %PackBox{status: "saved"} = box, _key, _mobile_user) do
    {:ok, box_payload(preload_box(box))}
  end

  defp do_save_box(organization_id, %PackBox{status: "draft"} = box, key, mobile_user) do
    serials = Enum.map(box.scans, & &1.serial)

    cond do
      serials == [] ->
        {:error, :empty_box}

      box.idempotency_key not in [nil, key] ->
        {:error, :idempotency_conflict}

      true ->
        mint_shipper(organization_id, box, serials, key, mobile_user)
    end
  end

  defp mint_shipper(organization_id, box, serials, key, mobile_user) do
    box =
      if box.idempotency_key == key do
        box
      else
        box
        |> PackBox.changeset(%{idempotency_key: key})
        |> Repo.update!()
      end

    product = box.batch.product
    batch = box.batch
    site_gln = mobile_user.site && mobile_user.site.gln

    attrs = %{
      "from_gln" => box.from_gln,
      "from_company_name" => box.from_name,
      "to_gln" => box.to_gln,
      "to_company_name" => box.to_name
    }

    case Manufacturing.pack_serials_into_shipper(
           organization_id,
           product,
           batch,
           serials,
           attrs,
           site_gln: site_gln,
           dispatch: false
         ) do
      {:ok, shipper} ->
        box
        |> PackBox.changeset(%{
          status: "saved",
          manufacturer_shipper_sscc_id: shipper.id
        })
        |> Repo.update!()
        |> preload_box()
        |> box_payload()
        |> then(&{:ok, &1})

      {:error, {:invalid, _message}} ->
        {:error, :not_unpacked}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_resolve_line(organization_id, raw, mobile_user) do
    parsed =
      case GS1Decoder.parse(raw) do
        {:ok, map} -> map
        _ -> %{gtin: nil, batch_no: nil, serial: nil}
      end

    cond do
      present?(parsed[:serial]) ->
        lookup_unit(organization_id, parsed.serial, parsed[:gtin], mobile_user)

      present?(parsed[:batch_no]) or present?(parsed[:gtin]) ->
        match_lot_label(organization_id, parsed, mobile_user)

      true ->
        lookup_unit(organization_id, raw, nil, mobile_user)
    end
  end

  defp lookup_unit(organization_id, serial, gtin, mobile_user) do
    serial = String.trim(to_string(serial))
    needle = if present?(gtin), do: gtin_key(gtin)

    rows =
      Repo.all(
        from s in Serial,
          where: s.organization_id == ^organization_id and s.serial == ^serial,
          preload: [:product, :batch]
      )
      |> Enum.filter(fn row ->
        is_nil(needle) or gtin_key(row.product.gtin) == needle
      end)

    case rows do
      [%Serial{manufacturer_shipper_sscc_id: packed_id} | _] when not is_nil(packed_id) ->
        {:error, :not_unpacked}

      [%Serial{} = row] ->
        with {:ok, batch} <- get_batch(organization_id, row.manufacturer_batch_id, mobile_user) do
          {:ok, %{batch: batch, serial: row.serial}}
        end

      [] ->
        {:error, :unknown_lot}

      many ->
        case Enum.filter(many, &is_nil(&1.manufacturer_shipper_sscc_id)) do
          [%Serial{} = row] ->
            with {:ok, batch} <- get_batch(organization_id, row.manufacturer_batch_id, mobile_user) do
              {:ok, %{batch: batch, serial: row.serial}}
            end

          [] ->
            {:error, :not_unpacked}

          _rest ->
            {:error, :unknown_lot}
        end
    end
  end

  defp match_lot_label(organization_id, parsed, mobile_user) do
    hits =
      organization_id
      |> list_batches(mobile_user)
      |> Enum.filter(&lot_hit?(&1, parsed))
      |> Enum.sort_by(&{&1.unpacked_count, &1.packed_count}, :desc)

    case hits do
      [] ->
        {:error, :unknown_lot}

      [hit | _] ->
        with {:ok, batch} <- get_batch(organization_id, hit.id, mobile_user) do
          {:ok, %{batch: batch, serial: nil}}
        end
    end
  end

  defp lot_hit?(row, parsed) do
    batch_ok =
      not present?(parsed[:batch_no]) or
        String.downcase(row.batch_no) == String.downcase(parsed.batch_no)

    gtin_ok = not present?(parsed[:gtin]) or gtin_key(row.gtin) == gtin_key(parsed.gtin)
    batch_ok and gtin_ok
  end

  defp gtin_key(value) when is_binary(value) do
    value |> String.replace(~r/\D/, "") |> String.pad_leading(14, "0")
  end

  defp gtin_key(_), do: ""

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp local_batches(organization_id) do
    Repo.all(
      from b in Batch,
        join: p in assoc(b, :product),
        where: b.organization_id == ^organization_id,
        order_by: [desc: b.inserted_at, desc: b.id],
        preload: [product: p]
    )
  end

  defp batch_payload(batch, drafts, mobile_user, detail) do
    product = batch.product
    open_box_id = drafts |> Map.get(batch.id) |> then(&(&1 && &1.id))
    packed = batch.packed_count
    unpacked = max(batch.issued_count - packed, 0)

    summary = %{
      id: to_string(batch.id),
      product_name: product.name,
      gtin: product.gtin,
      batch_no: batch.batch_no,
      expiry_date: expiry(batch.expiry_date),
      unpacked_count: unpacked,
      packed_count: packed,
      open_box_id: open_box_id && to_string(open_box_id)
    }

    if detail == :full do
      {from_gln, from_name} = from_party(batch, mobile_user)

      Map.merge(summary, %{
        from_gln: from_gln,
        from_name: from_name,
        to_gln: batch.to_gln,
        to_name: batch.to_name
      })
    else
      summary
    end
  end

  defp from_party(%Batch{from_gln: from_gln} = batch, _mobile_user)
       when is_binary(from_gln) and from_gln != "" do
    {batch.from_gln, batch.from_name}
  end

  defp from_party(_batch, %MobileUser{site: %{gln: gln, name: name}})
       when is_binary(gln) and gln != "" do
    {gln, name}
  end

  defp from_party(_batch, _mobile_user), do: {nil, nil}

  defp drafts_by_batch_id(organization_id, mobile_user_id) do
    Repo.all(
      from b in PackBox,
        where:
          b.organization_id == ^organization_id and b.mobile_user_id == ^mobile_user_id and
            b.status == "draft"
    )
    |> Map.new(&{&1.manufacturer_batch_id, &1})
  end

  defp repair_issued(organization_id, batch) do
    batch = Repo.preload(batch, :product)

    if batch.issued_count > 0 do
      batch
    else
      _ = Manufacturing.sync_issued_serials(organization_id, batch.product, batch)
      Repo.get!(Batch, batch.id) |> Repo.preload(:product)
    end
  end

  defp ensure_loose_serials(batch, mobile_user) do
    if existing_draft(batch.organization_id, mobile_user.id, batch.id) do
      :ok
    else
      if batch.issued_count > batch.packed_count, do: :ok, else: {:error, :no_unpacked}
    end
  end

  defp parties_present(%Batch{from_gln: from, to_gln: to}, _mobile_user)
       when is_binary(from) and from != "" and is_binary(to) and to != "" do
    :ok
  end

  defp parties_present(%Batch{to_gln: to} = batch, %MobileUser{} = mobile_user)
       when is_binary(to) and to != "" do
    {from_gln, _} = from_party(batch, mobile_user)
    if gln?(from_gln), do: :ok, else: {:error, :parties_required}
  end

  defp parties_present(_batch, _mobile_user), do: {:error, :parties_required}

  defp existing_draft(organization_id, mobile_user_id, batch_id) do
    Repo.one(
      from b in PackBox,
        where:
          b.organization_id == ^organization_id and b.mobile_user_id == ^mobile_user_id and
            b.manufacturer_batch_id == ^batch_id and b.status == "draft",
        preload: [scans: [], batch: :product, shipper_sscc: []]
    )
  end

  defp insert_draft(organization_id, mobile_user, batch) do
    {from_gln, from_name} = from_party(batch, mobile_user)

    attrs = %{
      from_gln: from_gln,
      from_name: from_name,
      to_gln: batch.to_gln,
      to_name: batch.to_name
    }

    result =
      %PackBox{
        organization_id: organization_id,
        mobile_user_id: mobile_user.id,
        manufacturer_batch_id: batch.id
      }
      |> PackBox.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, box} ->
        {:ok, :created, box_payload(preload_box(box))}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :mobile_user_id) do
          box = existing_draft(organization_id, mobile_user.id, batch.id)
          {:ok, :existing, box_payload(preload_box(box))}
        else
          {:error, changeset}
        end
    end
  end

  defp fetch_batch(organization_id, id) do
    case parse_int(id) do
      {:ok, parsed} ->
        case Repo.get_by(Batch, id: parsed, organization_id: organization_id) do
          %Batch{} = batch -> {:ok, Repo.preload(batch, :product)}
          nil -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp fetch_owned_box(organization_id, mobile_user_id, box_id) do
    case parse_uuid(box_id) do
      {:ok, id} ->
        query =
          from b in PackBox,
            where:
              b.id == ^id and b.organization_id == ^organization_id and
                b.mobile_user_id == ^mobile_user_id,
            preload: [scans: [], batch: :product, shipper_sscc: []]

        case Repo.one(query) do
          %PackBox{} = box -> {:ok, box}
          nil -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp fetch_owned_draft(organization_id, mobile_user_id, box_id) do
    with {:ok, box} <- fetch_owned_box(organization_id, mobile_user_id, box_id) do
      if box.status == "draft", do: {:ok, box}, else: {:error, :not_editable}
    end
  end

  defp lock_owned_box(organization_id, mobile_user_id, box_id) do
    case parse_uuid(box_id) do
      {:ok, id} ->
        query =
          from b in PackBox,
            where:
              b.id == ^id and b.organization_id == ^organization_id and
                b.mobile_user_id == ^mobile_user_id,
            lock: "FOR UPDATE",
            preload: [scans: [], batch: :product, shipper_sscc: []]

        case Repo.one(query) do
          %PackBox{} = box -> {:ok, box}
          nil -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp preload_box(%PackBox{} = box) do
    Repo.preload(box, [:scans, :shipper_sscc, batch: :product], force: true)
  end

  defp resolve_serial(box, raw) do
    raw = trim(raw)

    case GS1Decoder.parse(raw) do
      {:ok, parsed} when is_binary(parsed.serial) and parsed.serial != "" ->
        {:ok, parsed.serial, parsed}

      _ ->
        if typed_serial?(box, raw) do
          {:ok, raw, %{serial: raw, gtin: nil, batch_no: nil}}
        else
          {:error, :unreadable}
        end
    end
  end

  defp match_batch(box, parsed) do
    product = box.batch.product

    cond do
      present?(parsed[:gtin]) and gtin_key(parsed.gtin) != gtin_key(product.gtin) ->
        Logger.warning(
          "pack-line match_batch gtin box=#{product.gtin} scanned=#{inspect(parsed.gtin)}"
        )

        {:error, :wrong_batch}

      present?(parsed[:batch_no]) and not same_batch_no?(parsed.batch_no, box.batch.batch_no) ->
        Logger.warning(
          "pack-line match_batch lot box=#{box.batch.batch_no} scanned=#{inspect(parsed.batch_no)}"
        )

        {:error, :wrong_batch}

      true ->
        :ok
    end
  end

  defp same_batch_no?(left, right) do
    String.downcase(String.trim(to_string(left))) == String.downcase(String.trim(to_string(right)))
  end

  defp pack_line_result({:error, reason}), do: {:error, reason}
  defp pack_line_result({:ok, :existing, _}), do: {:ok, :existing}
  defp pack_line_result({:ok, :created, _}), do: {:ok, :created}
  defp pack_line_result({:ok, :repeat, _}), do: {:ok, :repeat}

  defp pack_line_result({:ok, %{batch: batch, serial: serial}}),
    do: {:ok, %{batch_id: batch[:id], serial: serial}}

  defp ensure_unpacked(_organization_id, box, serial) do
    product = box.batch.product

    case Repo.get_by(Serial, manufacturer_product_id: product.id, serial: serial) do
      %Serial{manufacturer_batch_id: batch_id, manufacturer_shipper_sscc_id: nil} ->
        if batch_id == box.batch.id, do: :ok, else: {:error, :wrong_batch}

      %Serial{manufacturer_shipper_sscc_id: packed_id} when not is_nil(packed_id) ->
        {:error, :not_unpacked}

      nil ->
        ensure_unpacked_gs1(box, serial)
    end
  end

  defp ensure_unpacked_gs1(box, serial) do
    product = box.batch.product

    case Manufacturing.fetch_unpacked_serials(
           box.organization_id,
           product.gtin,
           box.batch.batch_no,
           exclude_draft_claims: false
         ) do
      {:ok, serials} ->
        if serial in serials, do: :ok, else: {:error, :not_unpacked}

      {:error, _} ->
        {:error, :not_unpacked}
    end
  end

  defp typed_serial?(box, raw) do
    local =
      Repo.exists?(
        from s in Serial,
          where:
            s.manufacturer_batch_id == ^box.batch.id and s.serial == ^raw and
              is_nil(s.manufacturer_shipper_sscc_id)
      )

    local or
      case Manufacturing.fetch_unpacked_serials(
             box.organization_id,
             box.batch.product.gtin,
             box.batch.batch_no,
             exclude_draft_claims: false
           ) do
        {:ok, serials} -> raw in serials
        {:error, _} -> false
      end
  end

  defp insert_claim(box, serial) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      %PackBoxScan{}
      |> PackBoxScan.changeset(%{
        box_id: box.id,
        organization_id: box.organization_id,
        manufacturer_product_id: box.batch.manufacturer_product_id,
        serial: serial,
        claimed_at: now
      })
      |> Repo.insert()

    case result do
      {:ok, _scan} ->
        {:ok, :created, scan_payload(box, serial)}

      {:error, %Ecto.Changeset{} = changeset} ->
        if Keyword.has_key?(changeset.errors, :organization_id) or
             Keyword.has_key?(changeset.errors, :serial) do
          {:error, :already_claimed}
        else
          {:error, changeset}
        end
    end
  end

  defp scan_payload(box, serial) do
    %{
      serial: serial,
      gtin: box.batch.product.gtin,
      batch_no: box.batch.batch_no
    }
  end

  defp box_payload(%PackBox{status: "saved"} = box) do
    shipper = box.shipper_sscc
    product = box.batch.product

    %{
      id: box.id,
      status: "saved",
      sscc: shipper && shipper.code,
      count: (shipper && shipper.count_of_trade_items) || length(box.scans),
      product_name: product.name,
      gtin: product.gtin,
      batch_no: box.batch.batch_no,
      expiry_date: expiry(box.batch.expiry_date),
      from_gln: box.from_gln,
      from_name: box.from_name,
      to_gln: box.to_gln,
      to_name: box.to_name
    }
  end

  defp box_payload(%PackBox{} = box) do
    %{
      id: box.id,
      batch_id: to_string(box.manufacturer_batch_id),
      status: "draft",
      serials:
        box.scans
        |> Enum.sort_by(& &1.claimed_at, {:asc, DateTime})
        |> Enum.map(&%{serial: &1.serial, claimed_at: DateTime.to_iso8601(&1.claimed_at)})
    }
  end

  defp party_name(organization_id, gln, :from) do
    case GlnLookup.resolve_origin(organization_id, gln) do
      {:ok, party} -> party.company
      _ -> party_name(organization_id, gln, :to)
    end
  end

  defp party_name(_organization_id, gln, :to) do
    case GlnLookup.resolve_party(gln) do
      {:ok, party} -> party.company
      _ -> nil
    end
  end

  defp parties_changeset_error(changeset) do
    cond do
      Keyword.has_key?(changeset.errors, :from_gln) or Keyword.has_key?(changeset.errors, :to_gln) ->
        if same_party_error?(changeset), do: {:error, :same_party}, else: {:error, :invalid_gln}

      true ->
        {:error, changeset}
    end
  end

  defp same_party_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {message, _}} ->
      is_binary(message) and String.contains?(message, "different")
    end)
  end

  defp gln?(value), do: is_binary(value) and Regex.match?(~r/^\d{13}$/, value)

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: ""

  defp expiry(%Date{} = date), do: Date.to_iso8601(date)
  defp expiry(_), do: nil

  defp parse_int(id) when is_integer(id), do: {:ok, id}

  defp parse_int(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_int(_id), do: :error

  defp parse_uuid(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :error
    end
  end

  defp parse_uuid(_id), do: :error
end
