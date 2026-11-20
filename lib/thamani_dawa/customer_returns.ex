defmodule ThamaniDawa.CustomerReturns do
  @moduledoc """
  Customer returns — stock physically coming back into the warehouse from
  a customer (wrong item, damage in transit, overstock), the inbound
  counterpart to `ThamaniDawa.InventoryDisposals`' outbound supplier
  return. A return never decrements anything; completing it always
  creates new `Batch` rows, in a zone/status determined by the
  inspector-assigned `condition` on each item.

  Workflow: `draft` (items added) -> `received` (physically back in the
  warehouse) -> `inspected` (every item given a condition) -> `completed`
  (batches created, EPCIS receiving event fired).
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.CustomerReturns.CustomerReturn
  alias ThamaniDawa.CustomerReturns.CustomerReturnAttachment
  alias ThamaniDawa.CustomerReturns.CustomerReturnItem
  alias ThamaniDawa.Customers
  alias ThamaniDawa.Distributor.Shipment
  alias ThamaniDawa.Epcis
  alias ThamaniDawa.Repo

  @doc "Lists all customer returns for an organization, newest first."
  def list_returns(organization_id) do
    Repo.all(
      from r in CustomerReturn,
        where: r.organization_id == ^organization_id,
        order_by: [desc: r.inserted_at],
        preload: [:customer, :site, :attachments, items: :product, shipment: [items: :product]]
    )
  end

  @doc "Gets a single customer return scoped to an organization, preloaded with customer, site, and items. Raises if not found."
  def get_return!(organization_id, id) do
    CustomerReturn
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> Repo.preload(
      customer: [],
      site: [],
      attachments: [],
      items: :product,
      shipment: [items: :product]
    )
  end

  @doc "Returns a changeset for building or validating a return form."
  def change_return(%CustomerReturn{} = customer_return, attrs \\ %{}) do
    CustomerReturn.changeset(customer_return, attrs)
  end

  @doc """
  The customer a return is credited to. A shipment's destination GLN wins
  when that customer is already on file; otherwise the destination is
  recorded as a customer so the return still has a party.
  """
  def customer_for_shipment(organization_id, %Shipment{} = shipment) do
    case Customers.get_by_gln(organization_id, shipment.destination_gln) do
      %{} = customer ->
        {:ok, customer}

      nil ->
        Customers.create_customer(organization_id, %{
          "name" => shipment.destination_company || "Customer #{shipment.destination_gln}",
          "gln" => shipment.destination_gln,
          "address" => shipment.destination_address,
          "customer_type" => "other"
        })
    end
  end

  @uploads_dir "priv/static/uploads/customer_returns"

  @doc "Stores one uploaded return document on disk and records it against the return."
  def store_attachment!(%CustomerReturn{} = customer_return, tmp_path, entry, uploaded_by_id) do
    dir = Path.join(@uploads_dir, to_string(customer_return.id))
    File.mkdir_p!(dir)

    stored_filename = "#{Ecto.UUID.generate()}-#{entry.client_name}"
    dest = Path.join(dir, stored_filename)
    File.cp!(tmp_path, dest)

    %CustomerReturnAttachment{}
    |> CustomerReturnAttachment.changeset(%{
      doc_type: :document,
      filename: entry.client_name,
      path: "/uploads/customer_returns/#{customer_return.id}/#{stored_filename}",
      content_type: entry.client_type,
      byte_size: entry.client_size,
      customer_return_id: customer_return.id,
      uploaded_by_id: uploaded_by_id
    })
    |> Repo.insert!()
  end

  @doc "Creates a new draft customer return for an organization."
  def create_return(organization_id, attrs) when is_integer(organization_id) do
    %CustomerReturn{}
    |> CustomerReturn.changeset(Map.put(attrs, "organization_id", organization_id))
    |> Repo.insert()
  end

  @doc """
  Adds a line item to a draft return. Returns `{:error, :not_draft}` if
  the return is no longer a draft.
  """
  def add_item(%CustomerReturn{status: :draft} = customer_return, attrs) do
    %CustomerReturnItem{}
    |> CustomerReturnItem.changeset(
      Map.merge(attrs, %{
        "customer_return_id" => customer_return.id,
        "organization_id" => customer_return.organization_id
      })
    )
    |> Repo.insert()
  end

  def add_item(%CustomerReturn{}, _attrs), do: {:error, :not_draft}

  @doc """
  Removes a line item from a draft return. Returns `{:error, :not_draft}`
  if the parent return is no longer a draft.
  """
  def remove_item(%CustomerReturnItem{} = item) do
    parent = Repo.get!(CustomerReturn, item.customer_return_id)

    if parent.status != :draft do
      {:error, :not_draft}
    else
      Repo.delete(item)
    end
  end

  @doc """
  Marks a draft return as physically received. Returns `{:error, :no_items}`
  if it has no items, or `{:error, changeset}` on validation failure.
  """
  def mark_received(%CustomerReturn{} = customer_return, received_by_id) do
    if Repo.exists?(
         from i in CustomerReturnItem, where: i.customer_return_id == ^customer_return.id
       ) do
      customer_return
      |> CustomerReturn.receive_changeset(%{received_by_id: received_by_id})
      |> Repo.update()
    else
      {:error, :no_items}
    end
  end

  @doc """
  Assigns an inspector's condition call to a return item. Returns
  `{:error, changeset}` on validation failure.
  """
  def set_item_condition(%CustomerReturnItem{} = item, condition) do
    item
    |> CustomerReturnItem.condition_changeset(%{condition: condition})
    |> Repo.update()
  end

  @doc """
  Moves a received return to `inspected` once every item has a condition
  assigned. Returns `{:error, :items_not_inspected}` if any item is still
  missing a condition.
  """
  def mark_inspected(%CustomerReturn{} = customer_return) do
    items =
      Repo.all(from i in CustomerReturnItem, where: i.customer_return_id == ^customer_return.id)

    if Enum.all?(items, &(&1.condition != nil)) do
      customer_return
      |> CustomerReturn.inspect_changeset()
      |> Repo.update()
    else
      {:error, :items_not_inspected}
    end
  end

  @doc """
  Completes an inspected return: creates a new `Batch` per item at the
  return's site, in the zone/status matching the item's condition
  (`:sellable` -> `:storage`/`:active`, `:damaged` -> `:storage`/`:damaged`,
  `:quarantine` -> `:quarantine`/`:quarantined`), records the new batch on
  each item, marks the return `completed`, and fires a distributor-tier
  EPCIS receiving event.
  """
  def complete_return(organization_id, return_id, _inspector_id) do
    customer_return = get_return!(organization_id, return_id)

    Repo.transaction(fn ->
      Enum.each(customer_return.items, &create_batch_for_item(&1, customer_return))

      case customer_return |> CustomerReturn.complete_changeset() |> Repo.update() do
        {:ok, completed} ->
          Epcis.record_customer_return(completed)
          completed

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp create_batch_for_item(%CustomerReturnItem{} = item, %CustomerReturn{} = customer_return) do
    {zone, status} = zone_and_status(item.condition)

    attrs = %{
      "product_id" => item.product_id,
      "site_id" => customer_return.site_id,
      "gtin" => item.product.gtin,
      "batch_no" => item.batch_no || "CRET-#{customer_return.id}-#{item.id}",
      "expiry_date" => item.expiry_date,
      "quantity" => item.quantity,
      "remaining_quantity" => item.quantity,
      "serials" => if(is_binary(item.serial) and item.serial != "", do: [item.serial], else: []),
      "zone" => zone,
      "status" => status
    }

    case Batches.create_batch(customer_return.organization_id, attrs) do
      {:ok, batch} ->
        item
        |> ThamaniDawa.CustomerReturns.CustomerReturnItem.assign_batch_changeset(batch.id)
        |> Repo.update!()

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp zone_and_status(:sellable), do: {:storage, :active}
  defp zone_and_status(:damaged), do: {:storage, :damaged}
  defp zone_and_status(:quarantine), do: {:quarantine, :quarantined}
end
