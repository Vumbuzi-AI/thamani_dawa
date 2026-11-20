defmodule ThamaniDawa.GoodsReceipts do
  @moduledoc "Distributor goods receipts and their atomically posted batch lines."

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.LogisticUnit
  alias ThamaniDawa.GoodsReceipts.Attachment
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.GoodsReceipts.ReceivingDiscrepancy
  alias ThamaniDawa.GoodsReceipts.ReceivingDraft
  alias ThamaniDawa.GoodsReceipts.ReceivingDraftAttachment
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @uploads_dir "priv/static/uploads/goods_receipts"
  @draft_uploads_dir "priv/static/uploads/receiving_drafts"

  def get_receiving_draft(organization_id, user_id) do
    Repo.one(
      from draft in ReceivingDraft,
        where: draft.organization_id == ^organization_id and draft.user_id == ^user_id,
        preload: [:attachments]
    )
  end

  def ensure_receiving_draft(organization_id, user_id) do
    case get_receiving_draft(organization_id, user_id) do
      %ReceivingDraft{} = draft ->
        draft

      nil ->
        %ReceivingDraft{}
        |> ReceivingDraft.changeset(%{
          organization_id: organization_id,
          user_id: user_id,
          posting_key: Ecto.UUID.generate()
        })
        |> Repo.audited_insert!()
    end
  end

  def save_draft_origin!(%ReceivingDraft{} = draft, origin) do
    draft
    |> ReceivingDraft.changeset(%{origin: origin})
    |> Repo.audited_update!()
    |> Repo.preload(:attachments)
  end

  def store_draft_attachment!(%ReceivingDraft{} = draft, doc_type, tmp_path, entry)
      when doc_type in [:delivery_note, :invoice, :po, :other] do
    dir = Path.join(@draft_uploads_dir, to_string(draft.id))
    File.mkdir_p!(dir)

    stored_filename = "#{Ecto.UUID.generate()}-#{entry.client_name}"
    dest = Path.join(dir, stored_filename)
    File.cp!(tmp_path, dest)

    attachments_to_replace =
      if doc_type == :other do
        []
      else
        Repo.all(
          from attachment in ReceivingDraftAttachment,
            where: attachment.receiving_draft_id == ^draft.id and attachment.doc_type == ^doc_type
        )
      end

    attachment =
      Repo.transaction(fn ->
        if attachments_to_replace != [] do
          attachment_ids = Enum.map(attachments_to_replace, & &1.id)

          from(attachment in ReceivingDraftAttachment, where: attachment.id in ^attachment_ids)
          |> Repo.delete_all()
        end

        %ReceivingDraftAttachment{}
        |> ReceivingDraftAttachment.changeset(%{
          doc_type: doc_type,
          filename: entry.client_name,
          path: dest,
          content_type: entry.client_type,
          byte_size: entry.client_size,
          receiving_draft_id: draft.id
        })
        |> Repo.audited_insert!()
      end)
      |> case do
        {:ok, attachment} ->
          attachment

        {:error, reason} ->
          File.rm(dest)
          raise reason
      end

    Enum.each(attachments_to_replace, &File.rm(&1.path))
    attachment
  end

  def delete_draft_attachment!(%ReceivingDraft{} = draft, attachment_id) do
    case Repo.get_by(ReceivingDraftAttachment,
           id: attachment_id,
           receiving_draft_id: draft.id
         ) do
      nil ->
        :not_found

      attachment ->
        File.rm(attachment.path)
        Repo.delete!(attachment)
        :ok
    end
  end

  def attach_draft_attachments!(
        %ReceivingDraft{} = draft,
        %GoodsReceipt{} = receipt,
        uploaded_by_id
      ) do
    draft = Repo.preload(draft, :attachments)

    Enum.each(draft.attachments, fn attachment ->
      dir = Path.join(@uploads_dir, to_string(receipt.id))
      File.mkdir_p!(dir)
      stored_filename = "#{Ecto.UUID.generate()}-#{attachment.filename}"
      dest = Path.join(dir, stored_filename)
      File.cp!(attachment.path, dest)

      %Attachment{}
      |> Attachment.changeset(%{
        doc_type: attachment.doc_type,
        filename: attachment.filename,
        path: "/uploads/goods_receipts/#{receipt.id}/#{stored_filename}",
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        goods_receipt_id: receipt.id,
        uploaded_by_id: uploaded_by_id
      })
      |> Repo.audited_insert!()
    end)
  end

  def delete_receiving_draft!(%ReceivingDraft{} = draft) do
    File.rm_rf(Path.join(@draft_uploads_dir, to_string(draft.id)))
    Repo.delete!(draft)
  end

  def list_receipts(organization_id) do
    Repo.all(
      from receipt in GoodsReceipt,
        where: receipt.organization_id == ^organization_id,
        order_by: [desc: receipt.received_at, desc: receipt.id],
        preload: [items: [:site, :supplier, :product], discrepancies: [], received_by: []]
    )
  end

  def get_receipt!(organization_id, id) do
    Repo.one!(
      from receipt in GoodsReceipt,
        where: receipt.organization_id == ^organization_id and receipt.id == ^id,
        preload: [
          items: [:product, :site, :supplier],
          discrepancies: [:product],
          received_by: [],
          attachments: []
        ]
    )
  end

  @doc """
  Copies a consumed upload entry's temp file to
  `priv/static/uploads/goods_receipts/<receipt_id>/` and records it as an
  `Attachment`. Called once the `GoodsReceipt` row exists (its id names the
  storage directory).
  """
  def store_attachment!(%GoodsReceipt{} = receipt, doc_type, tmp_path, entry, uploaded_by_id)
      when doc_type in [:delivery_note, :invoice, :po, :other] do
    dir = Path.join(@uploads_dir, to_string(receipt.id))
    File.mkdir_p!(dir)

    stored_filename = "#{Ecto.UUID.generate()}-#{entry.client_name}"
    dest = Path.join(dir, stored_filename)
    File.cp!(tmp_path, dest)

    %Attachment{}
    |> Attachment.changeset(%{
      doc_type: doc_type,
      filename: entry.client_name,
      path: "/uploads/goods_receipts/#{receipt.id}/#{stored_filename}",
      content_type: entry.client_type,
      byte_size: entry.client_size,
      goods_receipt_id: receipt.id,
      uploaded_by_id: uploaded_by_id
    })
    |> Repo.audited_insert!()
  end

  @doc """
  Posts a delivery's staged line items as one goods receipt. `origin` is
  `nil` for the pharmacy/lab org portal (which still records a supplier per
  line, cast directly onto each item's attrs) — or the GLN resolved live
  via `ThamaniDawa.Distributor.GlnLookup.resolve_party/1` for the
  distributor portal, snapshotted once onto the receipt header.
  """
  def receive_delivery(
        organization_id,
        user_id,
        items,
        posting_key,
        origin \\ nil,
        return_opts \\ %{}
      )
      when is_list(items) and is_binary(posting_key) do
    Repo.transaction(fn ->
      case Repo.get_by(GoodsReceipt, organization_id: organization_id, posting_key: posting_key) do
        %GoodsReceipt{} = receipt -> preload_receipt(receipt)
        nil -> create_and_post(organization_id, user_id, items, posting_key, origin, return_opts)
      end
    end)
  end

  defp create_and_post(organization_id, user_id, items, posting_key, origin, return_opts) do
    if items == [], do: Repo.rollback(:empty_delivery)

    changeset =
      %GoodsReceipt{}
      |> GoodsReceipt.changeset(%{
        number: next_number!(organization_id),
        posting_key: posting_key,
        received_at: DateTime.utc_now() |> DateTime.truncate(:second),
        received_by_id: user_id,
        is_return: Map.get(return_opts, :is_return, false)
      })
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> maybe_put_origin(origin)

    items = maybe_tag_return_status(items, return_opts)

    case Repo.audited_insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:organization_id, :posting_key]
         ) do
      {:ok, %GoodsReceipt{id: nil}} ->
        organization_id
        |> receipt_for_posting_key!(posting_key)
        |> preload_receipt()

      {:ok, receipt} ->
        units = create_logistic_units!(organization_id, receipt.id, items)
        Enum.each(items, &post_item!(organization_id, user_id, receipt.id, &1, units))
        ThamaniDawa.Epcis.record_goods_receipt(receipt)
        preload_receipt(receipt)

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp maybe_tag_return_status(items, %{status: status}) when is_binary(status) do
    Enum.map(items, fn item -> %{item | attrs: Map.put(item.attrs, "status", status)} end)
  end

  defp maybe_tag_return_status(items, _return_opts), do: items

  defp maybe_put_origin(changeset, nil), do: changeset

  defp maybe_put_origin(changeset, origin) do
    Ecto.Changeset.change(changeset, %{
      origin_gln: origin.gln,
      origin_company: origin.company,
      origin_address: origin.address,
      origin_po_box: origin.po_box,
      origin_site_id: origin.site_id
    })
  end

  defp next_number!(organization_id) do
    {1, _} =
      Repo.update_all(
        from(o in Organization, where: o.id == ^organization_id),
        inc: [next_goods_receipt_number: 1]
      )

    organization = Repo.get!(Organization, organization_id)

    "GRN-" <>
      String.pad_leading(Integer.to_string(organization.next_goods_receipt_number), 6, "0")
  end

  defp preload_receipt(receipt),
    do:
      Repo.preload(receipt,
        items: [:product, :site, :supplier],
        received_by: [],
        attachments: []
      )

  defp receipt_for_posting_key!(organization_id, posting_key) do
    Repo.get_by!(GoodsReceipt, organization_id: organization_id, posting_key: posting_key)
  end

  # One logistic unit (case) per distinct SSCC in the delivery. A mixed case
  # ends up as one unit owning several batch lines; loose stock (no SSCC) gets
  # no unit. Keyed by the normalized SSCC so `post_item!` can link each batch.
  defp create_logistic_units!(organization_id, receipt_id, items) do
    items
    |> Enum.group_by(&item_sscc/1)
    |> Enum.reject(fn {sscc, _group} -> is_nil(sscc) end)
    |> Map.new(fn {sscc, group} ->
      {sscc, find_or_create_logistic_unit!(organization_id, receipt_id, sscc, group)}
    end)
  end

  # An SSCC uniquely identifies one physical case, so a recurring SSCC resolves
  # to the same unit rather than colliding on the unique index.
  defp find_or_create_logistic_unit!(organization_id, receipt_id, sscc, group) do
    site_id = group |> List.first() |> item_site_id()

    {:ok, _} =
      %LogisticUnit{}
      |> LogisticUnit.changeset(%{
        organization_id: organization_id,
        sscc: sscc,
        kind: :case,
        source: :inbound,
        site_id: site_id,
        goods_receipt_id: receipt_id
      })
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:organization_id, :sscc])

    Repo.get_by!(LogisticUnit, organization_id: organization_id, sscc: sscc).id
  end

  defp item_sscc(%{attrs: attrs}), do: normalize_sscc(Map.get(attrs, "sscc"))

  defp item_site_id(%{attrs: attrs}) do
    case Map.get(attrs, "site_id") do
      id when id in [nil, ""] -> nil
      id -> id
    end
  end

  defp normalize_sscc(sscc) when is_binary(sscc) do
    case String.trim(sscc) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_sscc(_sscc), do: nil

  defp post_item!(organization_id, user_id, receipt_id, %{attrs: attrs} = item, units) do
    attrs = Map.put(attrs, "goods_receipt_id", receipt_id)

    attrs =
      case item_sscc(item) do
        nil -> attrs
        sscc -> Map.put(attrs, "logistic_unit_id", Map.get(units, sscc))
      end

    # site_id is now mandatory for all batches — receiving always requires
    # a destination site
    if attrs["site_id"] in [nil, ""] do
      Repo.rollback(:site_required)
    else
      result =
        case Batches.create_batch(organization_id, attrs) do
          {:ok, batch} -> Batches.receive_batch(batch, user_id)
          error -> error
        end

      case result do
        {:ok, _batch} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
  end

  @doc """
  Records a discrepancy for an expected SSCC/serial that wasn't physically
  confirmed at receiving. Never creates a `Batch` or fires an EPCIS event —
  there's no physical stock behind it, and the receiving org was never
  confirmed to be in possession of it. Investigation later closes it out
  as `found`, `lost`, or `stolen`.
  """
  def create_discrepancy!(organization_id, goods_receipt_id, attrs) do
    %ReceivingDiscrepancy{}
    |> ReceivingDiscrepancy.changeset(
      attrs
      |> Map.put("organization_id", organization_id)
      |> Map.put("goods_receipt_id", goods_receipt_id)
    )
    |> Repo.audited_insert!()
  end

  @doc "Open discrepancies awaiting investigation, newest first."
  def list_open_discrepancies(organization_id) do
    Repo.all(
      from d in ReceivingDiscrepancy,
        where: d.organization_id == ^organization_id and d.status == :open,
        order_by: [desc: d.inserted_at],
        preload: [goods_receipt: []]
    )
  end

  def get_discrepancy!(organization_id, id) do
    Repo.get_by!(ReceivingDiscrepancy, organization_id: organization_id, id: id)
  end

  @doc """
  Closes out a discrepancy as `found` (it turned up, no further action),
  `lost`, or `stolen`. The latter two require a `resolution_reference` — an
  investigation's conclusion, not a receiving clerk's guess — and, only at
  this point, create a minimal `Batch` scoped to exactly the resolved
  quantity/serial so `Batches.mark_lost/3`/`mark_stolen/3` can fire the
  correct EPCIS event. Nothing was ever reported before this; the receiving
  org was never confirmed to be in possession of it until now.
  """
  def resolve_discrepancy(%ReceivingDiscrepancy{} = discrepancy, resolver_id, attrs) do
    discrepancy
    |> ReceivingDiscrepancy.resolve_changeset(Map.put(attrs, "resolved_by_id", resolver_id))
    |> Repo.audited_update()
    |> case do
      {:ok, resolved} = result ->
        escalate_if_needed(resolved, resolver_id)
        result

      error ->
        error
    end
  end

  defp escalate_if_needed(%ReceivingDiscrepancy{status: status} = discrepancy, resolver_id)
       when status in [:lost, :stolen] do
    attrs = %{
      "product_id" => discrepancy.product_id,
      "site_id" => discrepancy.site_id,
      "gtin" => discrepancy.gtin,
      "batch_no" => discrepancy.batch_no,
      "expiry_date" => discrepancy.expiry_date,
      "quantity" => discrepancy.quantity,
      "serials" => if(discrepancy.serial, do: [discrepancy.serial], else: []),
      "status" => "active",
      "received_at" => DateTime.utc_now(),
      "approver_id" => resolver_id
    }

    with {:ok, batch} <- Batches.create_batch(discrepancy.organization_id, attrs) do
      case status do
        :lost -> Batches.mark_lost(batch, discrepancy.resolution_reference, resolver_id)
        :stolen -> Batches.mark_stolen(batch, discrepancy.resolution_reference, resolver_id)
      end
    end
  end

  defp escalate_if_needed(_discrepancy, _resolver_id), do: :ok
end
