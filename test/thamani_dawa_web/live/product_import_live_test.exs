defmodule ThamaniDawaWeb.ProductImportLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Products
  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  defp upload_csv(view, content) do
    view
    |> file_input("#upload-form", :csv_file, [
      %{name: "products.csv", content: content, type: "text/csv"}
    ])
    |> render_upload("products.csv")

    view |> form("#upload-form") |> render_submit()
  end

  test "an admin imports a valid product row end to end", %{conn: conn} do
    admin = user_fixture()
    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/products/import")

    csv = """
    Generic name,Brand name,GTIN,Price,Unit of measure
    Paracetamol,Panadol,6291041500213,100,U2
    """

    html = upload_csv(view, csv)
    assert html =~ "Match each of our fields to a column from your file"

    assert has_element?(
             view,
             "select[name='mapping[generic_name]'] option[value='Generic name'][selected]"
           )

    assert has_element?(view, "select[name='mapping[gtin]'] option[value='GTIN'][selected]")

    html =
      view
      |> form("#mapping-form",
        mapping: %{
          generic_name: "Generic name",
          brand_name: "Brand name",
          gtin: "GTIN",
          price: "Price",
          uom: "Unit of measure",
          category: "",
          manufacturer: "",
          reorder_level: "",
          is_otc: "",
          is_dangerous_drug: ""
        }
      )
      |> render_submit()

    assert html =~ "Ready to import"
    assert html =~ "Paracetamol"

    html = view |> element("button", "Import 1 products") |> render_click()
    assert html =~ "Imported 1 of 1 rows"

    product = Products.get_product_by_gtin(admin.organization_id, "06291041500213")
    assert product
    assert product.generic_name == "Paracetamol"
    assert product.price == 100
  end

  test "an invalid GTIN is flagged and excluded from import", %{conn: conn} do
    admin = user_fixture()
    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/products/import")

    csv = """
    Generic name,GTIN,Price,Unit of measure
    Bad Product,1234567890123,50,U2
    """

    upload_csv(view, csv)

    html =
      view
      |> form("#mapping-form",
        mapping: %{
          generic_name: "Generic name",
          brand_name: "",
          gtin: "GTIN",
          price: "Price",
          uom: "Unit of measure",
          category: "",
          manufacturer: "",
          reorder_level: "",
          is_otc: "",
          is_dangerous_drug: ""
        }
      )
      |> render_submit()

    assert html =~ "Needs fixing"
    assert has_element?(view, "button[disabled]", "Import 0 products")

    refute Products.get_product_by_gtin(admin.organization_id, "1234567890123")
  end

  test "a GTIN already in the catalogue is skipped, not duplicated", %{conn: conn} do
    admin = user_fixture()

    {:ok, existing} =
      Products.create_product(admin.organization_id, %{
        "generic_name" => "Amoxicillin",
        "gtin" => "6291041500213",
        "price" => 200,
        "uom" => "U2",
        "inventory_type" => "medicine"
      })

    {:ok, view, _html} = live(log_in(conn, admin), ~p"/org/products/import")

    csv = """
    Generic name,GTIN,Price,Unit of measure
    Amoxicillin,6291041500213,250,U2
    """

    upload_csv(view, csv)

    html =
      view
      |> form("#mapping-form",
        mapping: %{
          generic_name: "Generic name",
          brand_name: "",
          gtin: "GTIN",
          price: "Price",
          uom: "Unit of measure",
          category: "",
          manufacturer: "",
          reorder_level: "",
          is_otc: "",
          is_dangerous_drug: ""
        }
      )
      |> render_submit()

    assert html =~ "Already in catalogue"
    assert Products.get_product!(admin.organization_id, existing.id).price == 200
  end
end
