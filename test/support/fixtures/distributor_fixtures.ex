defmodule ThamaniDawa.DistributorFixtures do
  @moduledoc """
  Test helpers for the distributor portal: distributor organizations and
  users, warehouses, customers, mobile app users, received batches, and
  shipments at each lifecycle stage.
  """

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.Billing
  alias ThamaniDawa.DistributorCustomers
  alias ThamaniDawa.Gln
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  @doc "Creates an organization operating as a distributor, with a GS1 Company Prefix."
  def distributor_organization_fixture(attrs \\ %{}) do
    org =
      attrs
      |> Enum.into(%{operating_models: [:distributor]})
      |> OrganizationsFixtures.organization_fixture()

    {:ok, org} =
      Organizations.update_organization_gs1_settings(org, %{gs1_company_prefix: "0614141"})

    org
  end

  @doc """
  Puts an organization on the prepay plan with a paid bundle of `quantity`
  serials (via a manual-reference payment, which confirms immediately).
  """
  def prepay_allowance_fixture(organization_id, user, quantity \\ 1_000) do
    {:ok, organization} =
      organization_id
      |> Organizations.get_organization!()
      |> Billing.choose_prepay()

    {:ok, payment} =
      Billing.start_prepay_payment(organization, user, %{
        "quantity" => Integer.to_string(quantity),
        "method" => "manual",
        "manual_reference" => "REF-#{System.unique_integer([:positive])}"
      })

    payment
  end

  @doc "Creates an active distributor-role user in a distributor organization."
  def distributor_user_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> distributor_organization_fixture().id end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn -> warehouse_fixture(organization_id).id end)

    attrs
    |> Map.put(:organization_id, organization_id)
    |> Map.put(:site_id, site_id)
    |> Map.put(:role, :distributor)
    |> AccountsFixtures.staff_fixture()
  end

  def warehouse_fixture(organization_id, attrs \\ %{}) do
    {:ok, site} =
      attrs
      |> Enum.into(%{
        name: "Warehouse #{System.unique_integer([:positive])}",
        activities: [:distribution],
        address: "#{System.unique_integer([:positive])} Warehouse Road",
        gln: Gln.generate!(),
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
      Enum.into(attrs, %{
        name: "Customer #{System.unique_integer([:positive])}",
        phone: "+254700#{phone_suffix}",
        address: "Moi Avenue, Nairobi",
        po_box: "P.O. Box 100-00100",
        is_active: true
      })

    {:ok, customer} = DistributorCustomers.create_customer(organization_id, customer_attrs)
    customer
  end

  def mobile_user_fixture(organization_id, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        "name" => "Packer #{unique}",
        "username" => "packer#{unique}",
        "email" => "packer#{unique}@example.com",
        "phone" => "0712#{String.pad_leading(Integer.to_string(rem(unique, 1_000_000)), 6, "0")}"
      })

    {:ok, mobile_user} = Distributor.create_mobile_user(organization_id, attrs)
    mobile_user
  end

  @doc """
  Creates a received (approved) batch carrying a unit serial, so scans of
  `gtin`/`serial` resolve as a known unit.
  """
  def received_unit_fixture(organization_id, site_id, user_id, attrs \\ %{}) do
    product =
      Map.get_lazy(attrs, :product, fn ->
        ProductsFixtures.product_fixture(%{organization_id: organization_id})
      end)

    batch_attrs = %{
      "product_id" => product.id,
      "site_id" => site_id,
      "gtin" => product.gtin,
      "batch_no" => Map.get(attrs, :batch_no, "LOT#{System.unique_integer([:positive])}"),
      "serial" => Map.get(attrs, :serial, "SN#{System.unique_integer([:positive])}"),
      "manufacture_date" => Map.get(attrs, :manufacture_date, ~D[2026-01-01]),
      "expiry_date" => Map.get(attrs, :expiry_date, Date.add(Date.utc_today(), 365)),
      "quantity" => 10,
      "remaining_quantity" => 10,
      "cost_per_unit" => "10.00"
    }

    {:ok, batch} = Batches.create_batch(organization_id, batch_attrs)
    {:ok, batch} = Batches.receive_batch(batch, user_id)
    Repo.preload(batch, :product)
  end

  @doc "GS1 element string (raw DataMatrix payload) for a received unit batch."
  def data_matrix_for(batch) do
    "01" <>
      batch.gtin <>
      "11" <>
      Calendar.strftime(batch.manufacture_date, "%y%m%d") <>
      "17" <>
      Calendar.strftime(batch.expiry_date, "%y%m%d") <>
      "10" <> batch.batch_no <> <<29>> <> "21" <> batch.serial
  end

  @doc "Creates a draft shipment from a warehouse to a customer."
  def shipment_fixture(organization_id, user, attrs \\ %{}) do
    warehouse = Map.get_lazy(attrs, :warehouse, fn -> warehouse_fixture(organization_id) end)
    customer = Map.get_lazy(attrs, :customer, fn -> customer_fixture(organization_id) end)

    {:ok, shipment} =
      Distributor.create_shipment(organization_id, user, %{
        "order_number" =>
          Map.get(attrs, :order_number, "PO-#{System.unique_integer([:positive])}"),
        "origin_gln" => warehouse.gln,
        "destination_gln" => customer.gln
      })

    shipment
  end

  @doc """
  Builds a submitted shipment: a mobile user claims a draft, adds one
  shipper, scans `batches` into it, and submits.
  """
  def submitted_shipment_fixture(organization_id, user, batches, attrs \\ %{}) do
    shipment = shipment_fixture(organization_id, user, attrs)

    mobile_user =
      Map.get_lazy(attrs, :mobile_user, fn -> mobile_user_fixture(organization_id) end)

    {:ok, _} = Distributor.select_shipment(mobile_user, shipment.id)
    {:ok, shipper} = Distributor.create_shipper(mobile_user, shipment.id, %{})

    Enum.each(batches, fn batch ->
      {:ok, _item} =
        Distributor.scan_item(mobile_user, shipper.id, %{
          "raw_data_matrix" => data_matrix_for(batch)
        })
    end)

    {:ok, shipment} = Distributor.submit_shipment(mobile_user, shipment.id)
    shipment
  end
end
