defmodule ThamaniDawa.GoodsReceipts do
  @moduledoc "Distributor goods receipts and their atomically posted batch lines."

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

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
        preload: [items: [:product, :site, :supplier], received_by: []]
    )
  end

  def receive_delivery(organization_id, user_id, items, posting_key)
      when is_list(items) and is_binary(posting_key) do
    Repo.transaction(fn ->
      case Repo.get_by(GoodsReceipt, organization_id: organization_id, posting_key: posting_key) do
        %GoodsReceipt{} = receipt -> preload_receipt(receipt)
        nil -> create_and_post(organization_id, user_id, items, posting_key)
      end
    end)
  end

  defp create_and_post(organization_id, user_id, items, posting_key) do
    if items == [], do: Repo.rollback(:empty_delivery)

    changeset =
      %GoodsReceipt{}
      |> GoodsReceipt.changeset(%{
        number: next_number!(organization_id),
        posting_key: posting_key,
        received_at: DateTime.utc_now() |> DateTime.truncate(:second),
        received_by_id: user_id
      })
      |> Ecto.Changeset.put_change(:organization_id, organization_id)

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
        preload_receipt(receipt)

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
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
    do: Repo.preload(receipt, items: [:product, :site, :supplier], received_by: [])

  defp receipt_for_posting_key!(organization_id, posting_key) do
    Repo.get_by!(GoodsReceipt, organization_id: organization_id, posting_key: posting_key)
  end

  defp post_item!(organization_id, user_id, receipt_id, %{attrs: attrs}) do
    with {:ok, batch} <-
           Batches.create_batch(organization_id, Map.put(attrs, "goods_receipt_id", receipt_id)),
         {:ok, _received} <- Batches.receive_batch(batch, user_id) do
      :ok
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
