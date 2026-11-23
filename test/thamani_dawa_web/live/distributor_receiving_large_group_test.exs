defmodule ThamaniDawaWeb.DistributorReceivingLargeGroupTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.GS1.MemberApiStub

  test "scanning a large serial group's SSCC adds it straight to the delivery" do
    organization = distributor_organization_fixture(%{gs1_company_prefix: "0614141"})
    warehouse = warehouse_fixture(organization.id)

    admin =
      staff_fixture(%{
        organization_id: organization.id,
        role: :distributor,
        site_id: warehouse.id
      })

    {:ok, admin} = ThamaniDawa.Accounts.switch_current_site(Scope.for_user(admin), warehouse.id)

    sscc = "261620061000015916"
    serials = for i <- 1..19, do: "SER#{i}"

    MemberApiStub.put_contents(sscc, [
      %{
        "name" => "Renova",
        "gtin" => "6162006100734",
        "batches" => [
          %{
            "batch" => "SNL005",
            "production_date" => "2025-12-01",
            "expiry_date" => "2027-12-31",
            "serials" => Enum.map(serials, &%{"serial" => &1})
          }
        ]
      }
    ])

    conn = log_in_user(build_conn(), admin)
    {:ok, view, _html} = live(conn, ~p"/distributor/receiving/new")

    view |> element("#open-add-item-empty") |> render_click()

    view
    |> form("#distributor-entry-sscc-form", sscc_entry: %{"sscc" => sscc})
    |> render_change()

    :timer.sleep(200)

    final_html = render(view)

    refute final_html =~ "Confirm this case's contents"
    assert final_html =~ "Renova"
    assert final_html =~ "19 units"
  end
end
