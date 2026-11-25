defmodule ThamaniDawa.ProductsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product

  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_product/2" do
    test "requires price" do
      organization = organization_fixture()
      assert {:error, changeset} = Products.create_product(organization.id, %{})
      assert %{price: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires a unit of measure" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Test Drug"
               })

      assert %{uom: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a negative price" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{
                 price: -1,
                 generic_name: "Test Drug"
               })

      assert %{price: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "creates a product scoped to the organization" do
      organization = organization_fixture()

      assert {:ok, %Product{} = product} =
               Products.create_product(organization.id, %{
                 price: 500,
                 generic_name: "Amoxicillin",
                 brand_name: "Amoxil",
                 manufacturer: "GlaxoSmithKline",
                 uom: "capsule",
                 gtin: "00614141000012"
               })

      assert product.organization_id == organization.id
      assert product.price == 500
      assert product.generic_name == "Amoxicillin"
      assert product.manufacturer == "GlaxoSmithKline"
    end

    test "enforces per-organization unique gtin, allowing the same gtin across organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      assert {:ok, _product} =
               Products.create_product(organization_a.id, %{
                 price: 100,
                 generic_name: "Surgical Gloves",
                 uom: "pair",
                 gtin: "00614141000012"
               })

      assert {:error, changeset} =
               Products.create_product(organization_a.id, %{
                 price: 100,
                 generic_name: "Surgical Gloves (dup)",
                 uom: "pair",
                 gtin: "00614141000012"
               })

      assert %{gtin: ["has already been taken"]} = errors_on(changeset)

      assert {:ok, _product} =
               Products.create_product(organization_b.id, %{
                 price: 100,
                 generic_name: "Surgical Gloves",
                 uom: "pair",
                 gtin: "00614141000012"
               })
    end

    test "rejects a product with neither a generic nor a brand name" do
      organization = organization_fixture()

      assert {:error, changeset} = Products.create_product(organization.id, %{price: 100})

      assert %{generic_name: ["enter a generic or brand name"]} = errors_on(changeset)
    end

    test "accepts a product with only a brand name" do
      organization = organization_fixture()

      assert {:ok, product} =
               Products.create_product(organization.id, %{
                 price: 100,
                 brand_name: "Panadol",
                 uom: "tablet",
                 gtin: "00614141000012"
               })

      assert product.brand_name == "Panadol"
      assert is_nil(product.generic_name)
    end

    test "accepts a product with only a generic name" do
      organization = organization_fixture()

      assert {:ok, product} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Paracetamol",
                 uom: "tablet",
                 gtin: "00614141000012"
               })

      assert product.generic_name == "Paracetamol"
    end

    test "stores what one unit contains without a pack conversion" do
      organization = organization_fixture()

      assert {:ok, product} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Paracetamol",
                 uom: "U2",
                 gtin: "00614141000012",
                 net_content_quantity: 20,
                 net_content_uom: "U2"
               })

      assert product.net_content_quantity == 20
      assert product.net_content_uom == "U2"
      assert Products.format_net_content(product) == "20 tablet(s)"
      assert Products.format_unit_count(1) == "1 unit"
    end

    test "requires both the contents quantity and its unit" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Paracetamol",
                 uom: "U2",
                 gtin: "00614141000012",
                 net_content_quantity: 20
               })

      assert %{net_content_uom: ["must be set when contents are specified"]} =
               errors_on(changeset)
    end

    test "requires a gtin" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Cotton Wool",
                 uom: "roll"
               })

      assert %{gtin: ["can't be blank"]} = errors_on(changeset)
    end

    test "normalizes a shorter GTIN to canonical GTIN-14 via ex_gtin" do
      organization = organization_fixture()

      assert {:ok, product} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Surgical Gloves",
                 uom: "pair",
                 gtin: "614141000012"
               })

      assert product.gtin == "00614141000012"
    end

    test "rejects a gtin that fails the GS1 check digit" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{
                 price: 100,
                 generic_name: "Surgical Gloves",
                 gtin: "00614141000011"
               })

      assert %{gtin: ["is not a valid GTIN"]} = errors_on(changeset)
    end
  end

  describe "list_products/1" do
    test "only returns products for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      product_a = product_fixture(%{organization_id: organization_a.id})
      product_fixture(%{organization_id: organization_b.id})

      assert [%Product{id: id}] = Products.list_products(organization_a.id)
      assert id == product_a.id
    end
  end

  describe "get_product!/2" do
    test "raises when the product belongs to a different organization" do
      other_organization = organization_fixture()
      product = product_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Products.get_product!(other_organization.id, product.id)
      end
    end
  end

  describe "list_products_with_site_batches_paginated/4" do
    test "returns an empty page when site_ids is an empty list (no accessible sites)" do
      organization = organization_fixture()

      assert %Scrivener.Page{
               entries: [],
               page_number: 1,
               total_pages: 1,
               total_entries: 0,
               page_size: _page_size
             } = Products.list_products_with_site_batches_paginated(organization.id, [])
    end

    test "nil site_ids returns every product with any batch, dispatched or not" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      dispatched_product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: dispatched_product.id
      })

      undispatched_product = product_fixture(%{organization_id: organization.id})

      org_batch_fixture(%{
        organization_id: organization.id,
        product_id: undispatched_product.id
      })

      page = Products.list_products_with_site_batches_paginated(organization.id, nil, 1)

      product_ids = page.entries |> Enum.map(& &1.id) |> Enum.sort()

      assert product_ids ==
               Enum.sort([dispatched_product.id, undispatched_product.id])
    end

    test "a concrete site_ids list excludes products with only undispatched stock" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      dispatched_product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: dispatched_product.id
      })

      undispatched_product = product_fixture(%{organization_id: organization.id})

      org_batch_fixture(%{
        organization_id: organization.id,
        product_id: undispatched_product.id
      })

      page = Products.list_products_with_site_batches_paginated(organization.id, [site.id], 1)

      assert Enum.map(page.entries, & &1.id) == [dispatched_product.id]
    end
  end

  describe "sync_from_gs1/1" do
    test "refuses when the organization has no GS1 API key" do
      organization = organization_fixture()
      assert {:error, :unconfigured} = Products.sync_from_gs1(organization.id)
    end

    test "creates catalogue products from the member account GTINs" do
      organization = organization_with_gs1_key()
      gtin = unique_gtin()

      MemberApiStub.put_products([
        %{
          "gtin" => gtin,
          "name" => "GS1 Panadol",
          "description" => "Paracetamol 500mg",
          "brand_owner" => "GSK",
          "status" => "active"
        }
      ])

      assert {:ok, 1} = Products.sync_from_gs1(organization.id)

      product = Products.get_product_by_gtin(organization.id, gtin)
      assert product.generic_name == "Paracetamol 500mg"
      assert product.brand_name == "GS1 Panadol"
      assert product.manufacturer == "GSK"
      assert product.uom == "H87"
      assert product.price == 0
      assert product.is_active
    end

    test "refreshes name and status without overwriting price or unit" do
      organization = organization_with_gs1_key()
      gtin = unique_gtin()

      {:ok, existing} =
        Products.create_product(organization.id, %{
          gtin: gtin,
          generic_name: "Old name",
          brand_name: "Old brand",
          manufacturer: "Old Co",
          uom: "U2",
          price: 250,
          is_active: true
        })

      MemberApiStub.put_products([
        %{
          "gtin" => gtin,
          "name" => "New brand",
          "description" => "New generic",
          "brand_owner" => "New Co",
          "status" => "inactive"
        }
      ])

      assert {:ok, 1} = Products.sync_from_gs1(organization.id)

      product = Products.get_product!(organization.id, existing.id)
      assert product.generic_name == "New generic"
      assert product.brand_name == "New brand"
      assert product.manufacturer == "New Co"
      refute product.is_active
      assert product.uom == "U2"
      assert product.price == 250
    end
  end

  defp organization_with_gs1_key do
    organization = organization_fixture()
    {:ok, organization} = Organizations.set_gs1_api_key(organization, "gs1-secret-key-9876")
    organization
  end
end
