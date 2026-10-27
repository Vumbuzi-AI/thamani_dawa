defmodule ThamaniDawa.DistributorFixtures do
  @moduledoc """
  Test helpers for creating distributor domain entities (customers, orders, warehouses).
  """

  alias ThamaniDawa.DistributorCustomers
  alias ThamaniDawa.DistributorOrders
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  def organization_with_gs1(attrs \\ %{}) do
    org = OrganizationsFixtures.organization_fixture(attrs)

    {:ok, org} =
      Organizations.update_organization_gs1_settings(org, %{gs1_company_prefix: "0614141"})

    org
  end

  def warehouse_fixture(organization_id, attrs \\ %{}) do
    {:ok, site} =
      attrs
      |> Enum.into(%{
        name: "Warehouse #{System.unique_integer()}",
        site_type: :warehouse,
        address: "#{System.unique_integer([:positive])} Warehouse Road",
        is_active: true
      })
      |> then(&Sites.create_site(organization_id, &1))

    site
  end

  def customer_fixture(organization_id, attrs \\ %{}) do
    phone_suffix =
      String.pad_leading(
        Integer.to_string(rem(System.unique_integer([:positive]), 1_000_000)),
        6,
        "0"
      )

    customer_attrs =
      Map.merge(
        %{
          name: "Customer #{System.unique_integer()}",
          phone: "+254700#{phone_suffix}",
          is_active: true
        },
        attrs
      )

    {:ok, customer} = DistributorCustomers.create_customer(organization_id, customer_attrs)

    customer
  end

  def order_fixture(organization_id, customer_id, items, attrs \\ %{}) do
    item_params =
      items
      |> Enum.with_index()
      |> Map.new(fn {{product_id, quantity, unit_price}, index} ->
        {Integer.to_string(index),
         %{
           "product_id" => Integer.to_string(product_id),
           "quantity" => Integer.to_string(quantity),
           "unit_price" => Integer.to_string(unit_price)
         }}
      end)

    raw =
      Enum.into(attrs, %{
        "customer_id" => Integer.to_string(customer_id),
        "ordered_at" => DateTime.utc_now() |> DateTime.truncate(:second),
        "delivery_address" => "Test Delivery Address",
        "items" => item_params
      })

    {:ok, order} = DistributorOrders.create_order(organization_id, raw)
    Repo.preload(order, items: :product, shipment: :cartons)
  end
end
