defmodule ThamaniDawaWeb.ManufacturerAggregationWizardTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Gln
  alias ThamaniDawa.Manufacturing

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)

    %{conn: log_in_user(conn, user), organization: organization, site: site, product: product}
  end

  test "builds a pallet hierarchy and inherits parties into its shipper", %{
    conn: conn,
    organization: organization,
    site: site
  } do
    {:ok, dashboard, _html} = live(conn, ~p"/manufacturer/aggregations")
    assert has_element?(dashboard, "#add-aggregation-sscc")

    {:ok, wizard, _html} = live(conn, ~p"/manufacturer/aggregations/new")
    assert has_element?(wizard, "#aggregation-type-pallet")
    wizard |> element("#aggregation-type-pallet") |> render_click()

    attrs = %{
      "code" => "PALLET-1001",
      "from_gln" => site.gln,
      "from_company_name" => site.name,
      "from_address" => site.address,
      "to_gln" => "0614141000784",
      "to_company_name" => "Afya Test Org",
      "to_address" => "Nairobi, Kenya"
    }

    wizard
    |> element("#aggregation_to_gln_search")
    |> render_keyup(%{"value" => "Afya Test"})

    render_async(wizard)

    wizard
    |> element("#aggregation-to-gln-0614141000784")
    |> render_click()

    wizard
    |> form("#aggregation-sscc-form", %{
      "sscc" => Map.take(attrs, ["code", "from_gln", "from_company_name", "from_address"])
    })
    |> render_submit()

    [pallet] = Manufacturing.list_pallets(organization.id)
    assert_redirect(wizard, ~p"/manufacturer/aggregations/pallets/#{pallet.id}")

    {:ok, shipper_wizard, _html} =
      live(conn, ~p"/manufacturer/aggregations/pallets/#{pallet.id}/ssccs/new")

    assert has_element?(shipper_wizard, "#aggregation-parent-pallet")

    shipper_wizard |> form("#aggregation-sscc-form", %{"sscc" => %{}}) |> render_submit()

    [shipper] = Manufacturing.get_pallet!(organization.id, pallet.id).shipper_ssccs
    assert shipper.from_gln == attrs["from_gln"]
    assert shipper.to_company_name == attrs["to_company_name"]
    assert_redirect(shipper_wizard, ~p"/manufacturer/aggregations/ssccs/#{shipper.id}")

    assert [%{"serials" => [], "from" => %{"gln" => from}, "to" => %{"gln" => to}}] =
             ThamaniDawa.GS1.MemberApiStub.shipper_sscc_requests()

    assert from == attrs["from_gln"]
    assert to == attrs["to_gln"]
  end

  test "adds multiple batches and pasted serials to a shipper", %{
    conn: conn,
    organization: organization,
    product: product
  } do
    {:ok, sscc} =
      Manufacturing.create_manual_sscc(organization.id, nil, %{
        "code" => "SHIPPER-2001",
        "from_gln" => Gln.generate!(),
        "from_company_name" => "Factory",
        "from_address" => "Factory Road",
        "to_gln" => Gln.generate!(),
        "to_company_name" => "Warehouse",
        "to_address" => "Warehouse Road"
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations/ssccs/#{sscc.id}")

    view |> element("#upload-sscc-gtins") |> render_click()

    view
    |> form("#sscc-bulk-gtins-form", %{"bulk" => %{"gtins" => product.gtin}})
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#bulk-gtin-review")
    assert has_element?(view, "#bulk-gtin-#{product.gtin}", "Owned GTIN")

    view |> element("#save-bulk-gtins") |> render_click()
    view |> element("#add-sscc-batch") |> render_click()

    view
    |> form("#sscc-batch-form", %{
      "batch" => %{
        "product_id" => product.id,
        "batch_no" => "LOT-2001",
        "production_date" => "2026-11-01",
        "expiry_date" => "2027-11-01"
      }
    })
    |> render_submit()

    [{batch, 0}] = Manufacturing.list_batches(organization.id, product.id)
    assert has_element?(view, "#sscc-batch-#{batch.id}")

    view |> element("#add-sscc-serials") |> render_click()

    view
    |> form("#sscc-serials-form", %{
      "serials" => %{"batch_id" => batch.id, "serials" => "SER-1\nSER-2,SER-3"}
    })
    |> render_submit()

    assert length(Manufacturing.list_serials(organization.id, batch.id)) == 3
    assert has_element?(view, "#sscc-batch-#{batch.id}", "3 serials")
  end
end
