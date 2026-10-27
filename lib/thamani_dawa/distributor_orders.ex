defmodule ThamaniDawa.DistributorOrders do
  import Ecto.Query, warn: false

  alias ThamaniDawa.DistributorCustomers.Customer
  alias ThamaniDawa.DistributorOrders.Order
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  def get_order!(organization_id, id) do
    Repo.one!(
      from order in Order,
        where: order.organization_id == ^organization_id,
        where: order.id == ^id,
        preload: [:customer, :invoice, items: :product, shipment: [:warehouse, :cartons]]
    )
  end

  def mark_dispatched!(%Order{} = order) do
    order
    |> Order.changeset(%{status: :dispatched})
    |> Repo.update!()
  end

  def list_orders(organization_id) do
    Repo.all(
      from order in Order,
        where: order.organization_id == ^organization_id,
        order_by: [desc: order.ordered_at, desc: order.id],
        preload: [:customer, items: :product]
    )
  end

  def create_order(organization_id, attrs) do
    customer = find_customer(organization_id, Map.get(attrs, "customer_id"))
    items = normalize_items(Map.get(attrs, "items", %{}), organization_id)

    changeset =
      %Order{}
      |> Order.changeset(%{
        customer_id: customer && customer.id,
        status: "pending",
        ordered_at: DateTime.utc_now() |> DateTime.truncate(:second),
        delivery_address: Map.get(attrs, "delivery_address"),
        items: items
      })
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> validate_customer(customer)
      |> validate_items(items)

    case Repo.insert(changeset) do
      {:ok, order} ->
        {:ok, Repo.preload(order, [:customer, items: :product])}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_order(organization_id, %Order{id: id}, attrs) do
    order =
      Repo.one!(
        from order in Order,
          where: order.organization_id == ^organization_id,
          where: order.id == ^id,
          preload: [items: :product]
      )

    if order.status != :pending do
      {:error, :not_editable}
    else
      customer = find_customer(organization_id, Map.get(attrs, "customer_id"))
      items = normalize_items(Map.get(attrs, "items", %{}), organization_id)

      changeset =
        order
        |> Order.changeset(%{
          customer_id: customer && customer.id,
          status: order.status,
          ordered_at: order.ordered_at,
          delivery_address: Map.get(attrs, "delivery_address"),
          items: items
        })
        |> validate_customer(customer)
        |> validate_items(items)

      case Repo.update(changeset) do
        {:ok, order} ->
          {:ok, Repo.preload(order, [:customer, items: :product], force: true)}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp find_customer(organization_id, id) do
    case parse_id(id) do
      nil -> nil
      customer_id -> Repo.get_by(Customer, id: customer_id, organization_id: organization_id)
    end
  end

  defp normalize_items(items, organization_id) when is_map(items) do
    items
    |> Enum.sort_by(fn {index, _attrs} -> parse_id(index) || 0 end)
    |> Enum.map(fn {_index, attrs} -> normalize_item(attrs, organization_id) end)
  end

  defp normalize_items(items, organization_id) when is_list(items),
    do: Enum.map(items, &normalize_item(&1, organization_id))

  defp normalize_items(_items, _organization_id), do: []

  defp normalize_item(attrs, organization_id) when is_map(attrs) do
    product =
      case parse_id(Map.get(attrs, "product_id")) do
        nil ->
          nil

        product_id ->
          Repo.get_by(Product,
            id: product_id,
            organization_id: organization_id,
            is_active: true
          )
      end

    %{
      "product_id" => product && product.id,
      "quantity" => Map.get(attrs, "quantity"),
      "unit_price" => (product && product.price) || 0
    }
  end

  defp normalize_item(_attrs, _organization_id), do: %{"quantity" => nil}

  defp validate_customer(changeset, nil),
    do: Ecto.Changeset.add_error(changeset, :customer_id, "choose an active customer")

  defp validate_customer(changeset, %{is_active: true}), do: changeset

  defp validate_customer(changeset, _customer),
    do: Ecto.Changeset.add_error(changeset, :customer_id, "choose an active customer")

  defp validate_items(changeset, []),
    do: Ecto.Changeset.add_error(changeset, :items, "add at least one product")

  defp validate_items(changeset, items) do
    if Enum.any?(items, &is_nil(&1["product_id"])) do
      Ecto.Changeset.add_error(changeset, :items, "choose a valid product for every line")
    else
      changeset
    end
  end

  defp parse_id(value) when is_integer(value), do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_id(_value), do: nil
end
