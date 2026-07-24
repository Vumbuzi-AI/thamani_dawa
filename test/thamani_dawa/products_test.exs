defmodule ThamaniDawa.ProductsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures

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
end
