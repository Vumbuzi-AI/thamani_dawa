defmodule ThamaniDawa.GoodsReceipts do
  @moduledoc "Distributor goods receipts and their atomically posted batch lines."

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GoodsReceipts.Attachment
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @uploads_dir "priv/static/uploads/goods_receipts"

  def list_receipts(organization_id) do
    Repo.all(
      from receipt in GoodsReceipt,
        where: receipt.organization_id == ^organization_id,
        order_by: [desc: receipt.received_at, desc: receipt.id],
        preload: [items: [:site, :supplier, :product], received_by: []]
    )
  end

  def get_receipt!(organization_id, id) do
    Repo.one!(
      from receipt in GoodsReceipt,
        where: receipt.organization_id == ^organization_id and receipt.id == ^id,
        preload: [items: [:product, :site, :supplier], received_by: [], attachments: []]
    )
  end

  @doc """
  Copies a consumed upload entry's temp file to
  `priv/static/uploads/goods_receipts/<receipt_id>/` and records it as an
  `Attachment`. Called once the `GoodsReceipt` row exists (its id names the
  storage directory).
  """
  def store_attachment!(%GoodsReceipt{} = receipt, doc_type, tmp_path, entry, uploaded_by_id)
      when doc_type in [:grn, :invoice, :other] do
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
    |> Repo.insert!()
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

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:organization_id, :posting_key]
         ) do
      {:ok, %GoodsReceipt{id: nil}} ->
        organization_id
        |> receipt_for_posting_key!(posting_key)
        |> preload_receipt()

      {:ok, receipt} ->
        Enum.each(items, &post_item!(organization_id, user_id, receipt.id, &1))
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

  defp post_item!(organization_id, user_id, receipt_id, %{attrs: attrs}) do
    attrs = Map.put(attrs, "goods_receipt_id", receipt_id)

    result =
      if attrs["site_id"] in [nil, ""] do
        Batches.receive_into_org_stock(organization_id, Map.delete(attrs, "site_id"))
      else
        case Batches.create_batch(organization_id, attrs) do
          {:ok, batch} -> Batches.receive_batch(batch, user_id)
          error -> error
        end
      end

    case result do
      {:ok, _batch} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
