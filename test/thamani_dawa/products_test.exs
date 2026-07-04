defmodule ThamaniDawa.ProductsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures

  describe "create_product/2" do
    test "requires a product_type" do
      organization = organization_fixture()
      assert {:error, changeset} = Products.create_product(organization.id, %{})
      assert %{product_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires generic_name for a drug" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{product_type: :drug, uom: "tablet"})

      assert %{generic_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires name for a non-drug product" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{product_type: :general_supply})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "creates a drug product scoped to the organization" do
      organization = organization_fixture()

      assert {:ok, %Product{} = product} =
               Products.create_product(organization.id, %{
                 generic_name: "Amoxicillin",
                 brand_name: "Amoxil",
                 product_type: :drug,
                 uom: "capsule",
                 gtin: "00614141000012"
               })

      assert product.organization_id == organization.id
      assert product.generic_name == "Amoxicillin"
      assert product.product_type == :drug
    end

    test "enforces per-organization unique gtin, allowing the same gtin across organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      assert {:ok, _product} =
               Products.create_product(organization_a.id, %{
                 name: "Surgical Gloves",
                 product_type: :general_supply,
                 gtin: "00614141000012"
               })

      assert {:error, changeset} =
               Products.create_product(organization_a.id, %{
                 name: "Surgical Gloves (dup)",
                 product_type: :general_supply,
                 gtin: "00614141000012"
               })

      assert %{gtin: ["has already been taken"]} = errors_on(changeset)

      assert {:ok, _product} =
               Products.create_product(organization_b.id, %{
                 name: "Surgical Gloves",
                 product_type: :general_supply,
                 gtin: "00614141000012"
               })
    end

    test "allows more than one product with no gtin" do
      organization = organization_fixture()

      assert {:ok, _a} =
               Products.create_product(organization.id, %{
                 name: "Cotton Wool",
                 product_type: :general_supply
               })

      assert {:ok, _b} =
               Products.create_product(organization.id, %{
                 name: "Bandages",
                 product_type: :general_supply
               })
    end

    test "normalizes a shorter GTIN to canonical GTIN-14 via ex_gtin" do
      organization = organization_fixture()

      assert {:ok, product} =
               Products.create_product(organization.id, %{
                 name: "Surgical Gloves",
                 product_type: :general_supply,
                 gtin: "614141000012"
               })

      assert product.gtin == "00614141000012"
    end

    test "rejects a gtin that fails the GS1 check digit" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Products.create_product(organization.id, %{
                 name: "Surgical Gloves",
                 product_type: :general_supply,
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
