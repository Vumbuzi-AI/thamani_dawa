defmodule ThamaniDawa.Sales do
  @moduledoc """
  Counter-sale transactions. Quick sales use this context rather than the
  prescription domain, while retaining the same transactional stock controls.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Epcis
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sales.{Sale, SaleBatchDispense, SaleItem}

  @doc """
  Completes an OTC counter sale atomically. It creates a standalone sale and
  sale lines, allocates approved stock by FEFO (or the scanned lot), records
  traceability, and completes its payment. It never creates a prescription,
  prescription item, patient visit, or patient record.
  """
  def create_quick_sale(organization_id, site_id, user_id, attrs)
      when is_integer(organization_id) and is_integer(site_id) and is_integer(user_id) do
    Repo.transaction(fn ->
      with {:ok, item_specs} <- sale_item_specs(organization_id, attrs["items"] || []),
           {:ok, sale} <-
             create_sale(organization_id, %{
               site_id: site_id,
               user_id: user_id,
               total_amount: total_amount(item_specs)
             }),
           {:ok, sale_items} <- create_sale_items(organization_id, sale.id, item_specs),
           :ok <- dispense_sale_items(organization_id, site_id, user_id, sale_items, item_specs),
           {:ok, payment} <-
             Payments.create_payment(organization_id, %{
               "sale_id" => sale.id,
               "amount" => sale.total_amount,
               "payment_type" => attrs["payment_type"],
               "provider_reference" => attrs["provider_reference"]
             }),
           {:ok, _payment} <- Payments.complete_payment(payment) do
        get_sale!(organization_id, sale.id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_sale!(organization_id, id),
    do: Repo.get_by!(Sale, id: id, organization_id: organization_id)

  def list_sale_items(organization_id, sale_id) do
    Repo.all(
      from i in SaleItem,
        where: i.organization_id == ^organization_id and i.sale_id == ^sale_id,
        order_by: [asc: i.id]
    )
  end

  defp create_sale(organization_id, attrs) do
    %Sale{}
    |> Sale.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  defp sale_item_specs(organization_id, item_attrs)
       when is_list(item_attrs) and item_attrs != [] do
    product_ids = Enum.map(item_attrs, &parse_product_id(Map.get(&1, "product_id")))

    with :ok <- validate_product_ids(product_ids),
         {:ok, products} <- products_for_ids(organization_id, product_ids) do
      build_sale_item_specs(item_attrs, product_ids, products)
    end
  end

  defp sale_item_specs(_organization_id, _item_attrs), do: {:error, :prescription_required}

  defp validate_product_ids(product_ids) do
    if Enum.any?(product_ids, &is_nil/1) or length(Enum.uniq(product_ids)) != length(product_ids),
      do: {:error, :prescription_required},
      else: :ok
  end

  defp products_for_ids(organization_id, product_ids) do
    products =
      Map.new(
        Repo.all(
          from p in Product,
            where: p.organization_id == ^organization_id and p.id in ^product_ids,
            select: {p.id, p}
        )
      )

    if map_size(products) == length(product_ids),
      do: {:ok, products},
      else: {:error, :prescription_required}
  end

  defp build_sale_item_specs(item_attrs, product_ids, products) do
    item_attrs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, index}, {:ok, specs} ->
      product = Map.fetch!(products, Enum.at(product_ids, index))

      case sale_item_spec(product, attrs) do
        {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
        {:error, reason} -> {:halt, {:error, {index, reason}}}
      end
    end)
    |> reverse_specs()
  end

  defp sale_item_spec(
         %Product{is_active: true, is_otc: true, is_dangerous_drug: false} = product,
         attrs
       ) do
    case quantity_from_attrs(attrs) do
      {:ok, quantity} ->
        {:ok,
         %{
           product: product,
           quantity: quantity,
           scanned_gtin: Map.get(attrs, "scanned_gtin"),
           scanned_barcode: Map.get(attrs, "scanned_barcode")
         }}

      :error ->
        {:error, :invalid_quantity}
    end
  end

  defp sale_item_spec(_product, _attrs), do: {:error, :prescription_required}

  defp quantity_from_attrs(attrs) do
    value = Map.get(attrs, "quantity") || Map.get(attrs, "quantity_prescribed")
    if positive_integer?(value), do: {:ok, parse_positive_integer(value)}, else: :error
  end

  defp reverse_specs({:ok, specs}), do: {:ok, Enum.reverse(specs)}
  defp reverse_specs(error), do: error

  defp parse_product_id(id) when is_integer(id), do: id

  defp parse_product_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_product_id(_id), do: nil
  defp positive_integer?(value) when is_integer(value), do: value > 0

  defp positive_integer?(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed > 0
      _ -> false
    end
  end

  defp positive_integer?(_value), do: false

  defp parse_positive_integer(value) when is_integer(value), do: value

  defp parse_positive_integer(value) when is_binary(value) do
    {quantity, ""} = Integer.parse(value)
    quantity
  end

  defp total_amount(specs) do
    Enum.reduce(specs, Decimal.new(0), fn spec, total ->
      Decimal.add(
        total,
        Decimal.mult(Decimal.new(spec.product.price), Decimal.new(spec.quantity))
      )
    end)
  end

  defp create_sale_items(organization_id, sale_id, specs) do
    specs
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, items} ->
      attrs = %{
        sale_id: sale_id,
        product_id: spec.product.id,
        quantity: spec.quantity,
        unit_price: spec.product.price
      }

      case create_sale_item(organization_id, attrs) do
        {:ok, item} -> {:cont, {:ok, [item | items]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp create_sale_item(organization_id, attrs) do
    %SaleItem{}
    |> SaleItem.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  defp dispense_sale_items(organization_id, site_id, user_id, sale_items, specs) do
    sale_items
    |> Enum.zip(specs)
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{item, spec}, index}, :ok ->
      case dispense_sale_item(organization_id, site_id, user_id, item, spec) do
        {:ok, _item} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {index, reason}}}
      end
    end)
  end

  defp dispense_sale_item(organization_id, site_id, user_id, item, spec) do
    with {:ok, allocations} <- allocations_for_spec(organization_id, site_id, spec),
         :ok <- record_sale_batch_dispenses(organization_id, item, user_id, allocations) do
      # The EPCIS outbox records a persisted event struct on success (and a
      # blocked event when its prerequisites are unavailable). The sale itself
      # must continue in either case; event delivery is handled asynchronously.
      Epcis.record_dispense(organization_id, site_id, item.id, allocations, "sale_item")

      maybe_mark_verified(item, spec.scanned_gtin || spec.scanned_barcode, spec.product)
    end
  end

  defp allocations_for_spec(organization_id, site_id, spec) do
    batches = Batches.fefo_batches(organization_id, site_id, spec.product.id)

    case scanned_batch(spec.scanned_barcode) do
      {:ok, gtin, batch_no} ->
        with :ok <- validate_gtin(spec.product.gtin, gtin),
             {:ok, batch} <- find_batch(batches, batch_no),
             :ok <- decrement_exact_batch(batch, spec.quantity) do
          {:ok, [%{batch: batch, quantity: spec.quantity}]}
        end

      :none ->
        consume_fefo(batches, spec.quantity)
    end
  end

  defp scanned_batch(nil), do: :none

  defp scanned_batch(raw_barcode) when is_binary(raw_barcode) do
    case ThamaniDawa.GS1Decoder.parse(raw_barcode) do
      {:ok, %{gtin: gtin, batch_no: batch_no}}
      when is_binary(gtin) and is_binary(batch_no) and batch_no != "" ->
        {:ok, gtin, batch_no}

      _ ->
        :none
    end
  end

  defp scanned_batch(_raw_barcode), do: :none

  defp validate_gtin(expected, scanned) do
    with {:ok, normalized} <- ExGtin.normalize(scanned),
         true <- expected == normalized do
      :ok
    else
      _ -> {:error, :gtin_mismatch}
    end
  end

  defp find_batch(batches, batch_no) do
    case Enum.find(batches, &(&1.batch_no == batch_no)) do
      nil -> {:error, :batch_mismatch}
      batch -> {:ok, batch}
    end
  end

  defp decrement_exact_batch(batch, quantity) do
    if batch.remaining_quantity >= quantity do
      case Batches.decrement_remaining_quantity(batch, quantity) do
        {:ok, _batch} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :out_of_stock}
    end
  end

  defp consume_fefo(batches, quantity), do: consume_fefo(batches, quantity, [])
  defp consume_fefo(_batches, 0, allocations), do: {:ok, Enum.reverse(allocations)}
  defp consume_fefo([], _quantity, _allocations), do: {:error, :out_of_stock}

  defp consume_fefo([batch | rest], quantity, allocations) do
    take = min(batch.remaining_quantity, quantity)

    with {:ok, _batch} <- Batches.decrement_remaining_quantity(batch, take) do
      consume_fefo(rest, quantity - take, [%{batch: batch, quantity: take} | allocations])
    end
  end

  defp record_sale_batch_dispenses(organization_id, item, user_id, allocations) do
    allocations
    |> Enum.reduce_while(:ok, fn allocation, :ok ->
      %SaleBatchDispense{}
      |> SaleBatchDispense.changeset(%{
        sale_item_id: item.id,
        batch_id: allocation.batch.id,
        quantity: allocation.quantity,
        dispensed_by_id: user_id,
        dispensed_at: DateTime.utc_now()
      })
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Repo.audited_insert()
      |> case do
        {:ok, _dispense} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp maybe_mark_verified(item, scanned_code, product) do
    case scanned_code && String.trim(scanned_code) do
      blank when blank in [nil, ""] ->
        {:ok, item}

      scanned when scanned == product.gtin ->
        update_verified(item)

      scanned ->
        verify_scanned_barcode(item, product, scanned)
    end
  end

  defp verify_scanned_barcode(item, product, scanned) do
    with {:ok, %{gtin: gtin}} <- ThamaniDawa.GS1Decoder.parse(scanned),
         :ok <- validate_gtin(product.gtin, gtin) do
      update_verified(item)
    else
      _ -> {:error, :gtin_mismatch}
    end
  end

  defp update_verified(item) do
    item
    |> Ecto.Changeset.change(is_verified: true)
    |> Repo.audited_update()
  end
end
