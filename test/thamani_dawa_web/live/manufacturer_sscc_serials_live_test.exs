defmodule ThamaniDawaWeb.ManufacturerSsccSerialsLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Repo

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})

    number = rem(System.unique_integer([:positive]), 1_000_000_000)
    body = "06160000" <> String.pad_leading(Integer.to_string(number), 9, "0")
    code = body <> Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(body))

    sscc =
      Repo.insert!(%ShipperSscc{
        organization_id: organization.id,
        code: code,
        gtin: "06141411234567",
        batch: "LOCAL-LOT"
      })

    %{conn: log_in_user(conn, user), organization: organization, sscc: sscc}
  end

  defp put_remote_serials(code) do
    MemberApiStub.put_contents(code, [
      %{
        "gtin" => "06141411234567",
        "name" => "Amoxicillin",
        "batches" => [
          %{
            "batch" => "GS1-LOT",
            "production_date" => "2026-01-15",
            "expiry_date" => "2027-06-01",
            "serials" => [%{"serial" => "SN-2"}, %{"serial" => "SN-1"}]
          }
        ]
      }
    ])
  end

  test "fetch_sscc_serials/2 reads the serials from the GS1 API", %{
    organization: organization,
    sscc: sscc
  } do
    put_remote_serials(sscc.code)

    assert {:ok, [first, second]} = Manufacturing.fetch_sscc_serials(organization.id, sscc.code)
    assert first.serial == "SN-1"
    assert second.serial == "SN-2"
    assert first.batch == "GS1-LOT"
    assert first.expiry_date == ~D[2027-06-01]
    assert sscc.code in MemberApiStub.requested_contents()
  end

  test "renders serials returned by the GS1 API", %{conn: conn, sscc: sscc} do
    put_remote_serials(sscc.code)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials")
    render_async(lv)

    assert has_element?(lv, "#sscc-serials")
    assert has_element?(lv, "#sscc-serials-back[href$='/ssccs']")
    assert has_element?(lv, "#sscc-primary-06141411234567-GS1-LOT-SN-1")
    assert has_element?(lv, "#sscc-primary-06141411234567-GS1-LOT-SN-2")
  end

  test "the back link honours a safe return_to", %{conn: conn, sscc: sscc} do
    {:ok, lv, _html} =
      live(
        conn,
        ~p"/manufacturer/sscc/#{sscc.id}/serials?#{%{return_to: "/manufacturer/products/123/serials?batch=B1"}}"
      )

    assert has_element?(lv, "#sscc-serials-back", "Back to Batches")

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials?#{%{return_to: "//evil.example"}}")
    refute has_element?(lv, "#sscc-serials-back[href*='evil']")
  end

  test "shows an error when GS1 has no record of the SSCC", %{conn: conn, sscc: sscc} do
    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials")
    render_async(lv)

    assert has_element?(lv, "#sscc-serials-error")
    refute has_element?(lv, "#sscc-serials")
  end

  test "CSV export uses the GS1 API serials", %{conn: conn, sscc: sscc} do
    put_remote_serials(sscc.code)

    body = conn |> get(~p"/manufacturer/sscc/#{sscc.id}/export") |> response(200)

    assert body =~ "#{sscc.code},06141411234567,GS1-LOT,SN-1"
    assert body =~ "#{sscc.code},06141411234567,GS1-LOT,SN-2"
  end
end
