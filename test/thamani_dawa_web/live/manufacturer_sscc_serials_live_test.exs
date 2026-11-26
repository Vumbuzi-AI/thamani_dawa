defmodule ThamaniDawaWeb.ManufacturerSsccSerialsLiveTest do
  use ThamaniDawaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.GS1.MemberApiStub
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Repo

  setup %{conn: conn} do
    MemberApiStub.reset()

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

  defp complete_sscc(sscc) do
    sscc
    |> Ecto.Changeset.change(status: "completed")
    |> Repo.update!()
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
    sscc = complete_sscc(sscc)
    put_remote_serials(sscc.code)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials")
    render_async(lv)

    assert has_element?(lv, "#sscc-serials")
    assert has_element?(lv, "#sscc-serials-back[href$='/ssccs']")
    assert has_element?(lv, "#sscc-primary-06141411234567-GS1-LOT-SN-1")
    assert has_element?(lv, "#sscc-primary-06141411234567-GS1-LOT-SN-2")
    assert has_element?(lv, "#sscc-primary-06141411234567-GS1-LOT-SN-1 td:nth-child(3)", "SN-1")

    refute has_element?(
             lv,
             "#sscc-primary-06141411234567-GS1-LOT-SN-1 td:nth-child(3)",
             "(01)06141411234567(21)SN-1"
           )

    assert has_element?(lv, "#sscc-dm-06141411234567-GS1-LOT-SN-1")
    refute has_element?(lv, "#pack-another-shipper")
  end

  test "the back link honours a safe return_to", %{conn: conn, sscc: sscc} do
    {:ok, lv, _html} =
      live(
        conn,
        ~p"/manufacturer/sscc/#{sscc.id}/serials?#{%{return_to: "/manufacturer/products/123/serials?batch=B1"}}"
      )

    assert has_element?(lv, "#sscc-serials-back", "Back to Batches")

    {:ok, lv, _html} =
      live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials?#{%{return_to: "//evil.example"}}")

    refute has_element?(lv, "#sscc-serials-back[href*='evil']")
  end

  test "navigates between shippers in the same batch", %{
    conn: conn,
    organization: organization,
    sscc: sscc
  } do
    sibling =
      Repo.insert!(%ShipperSscc{
        organization_id: organization.id,
        code: "261600005060028614",
        gtin: sscc.gtin,
        batch: sscc.batch
      })

    return_to = "/manufacturer/products/#{sscc.gtin}/serials?batch=#{sscc.batch}"

    {:ok, lv, _html} =
      live(
        conn,
        ~p"/manufacturer/sscc/#{sscc.id}/serials?#{%{return_to: return_to}}"
      )

    assert has_element?(lv, "#batch-shipper-navigation")
    assert has_element?(lv, "#batch-shipper-position", "2 of 2")

    assert has_element?(
             lv,
             "#previous-batch-shipper[href^='/manufacturer/sscc/#{sibling.id}/serials?']",
             "Previous"
           )

    refute has_element?(lv, "#next-batch-shipper")
  end

  test "shows an error when GS1 has no record of the SSCC", %{conn: conn, sscc: sscc} do
    sscc = complete_sscc(sscc)

    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials")
    render_async(lv)

    assert has_element?(lv, "#sscc-serials-error")
    refute has_element?(lv, "#sscc-serials")
  end

  test "CSV export uses shipper packed serials", %{
    conn: conn,
    organization: organization,
    sscc: sscc
  } do
    product = manufacturer_product_fixture(organization.id)
    batch = manufacturer_batch_fixture(organization.id, product.id)

    sscc =
      sscc
      |> Ecto.Changeset.change(%{
        gtin: product.gtin,
        batch: batch.batch_no,
        production_date: batch.production_date,
        expiry_date: batch.expiry_date,
        packed_serials: ["SN-LOCAL"]
      })
      |> Repo.update!()

    body = conn |> get(~p"/manufacturer/sscc/#{sscc.id}/export") |> response(200)

    assert body =~ "Shipper SSCC,#{sscc.code}"
    assert body =~ "gtin,batch,production_date,expiry_date,serial"
    assert body =~ ~s(="") <> "#{sscc.gtin}" <> ~s(")
    assert body =~ "#{batch.batch_no},#{batch.production_date},#{batch.expiry_date},SN-LOCAL"
    refute body =~ ~r/^sscc,/m
  end

  test "an available preprinted SSCC is ready for mobile packing without a GS1 lookup", %{
    conn: conn,
    sscc: sscc
  } do
    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials")
    render_async(lv)

    assert has_element?(lv, "#sscc-serials-empty")
    assert has_element?(lv, "#sscc-next-mobile")
    assert has_element?(lv, "#sscc-preview-content-#{sscc.id}")
    refute has_element?(lv, "#sscc-serials-error")
    refute sscc.code in MemberApiStub.requested_contents()
  end

  test "shipper label modal shows only the centered label preview", %{
    conn: conn,
    sscc: sscc
  } do
    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/label")

    assert has_element?(lv, "#shipper-label-modal")
    assert has_element?(lv, "#shipper-label-modal .printable-sscc-label")
    assert has_element?(lv, "#print-manufacturer-label")

    refute has_element?(lv, "#shipper-label-size")
    refute has_element?(lv, "#shipper-label-copies")
  end

  test "print label opens and closes the modal without leaving the serials page", %{
    conn: conn,
    sscc: sscc
  } do
    {:ok, lv, _html} = live(conn, ~p"/manufacturer/sscc/#{sscc.id}/serials")

    refute has_element?(lv, "#shipper-label-modal")
    assert has_element?(lv, "#sscc-serials-back")

    lv |> element("#sscc-serials-print-label") |> render_click()

    assert has_element?(lv, "#shipper-label-modal")
    assert has_element?(lv, "#print-manufacturer-label")
    assert has_element?(lv, "#sscc-serials-back")
    assert has_element?(lv, "#sscc-preview-content-#{sscc.id}")

    lv |> element("#shipper-label-modal button[aria-label='Close']") |> render_click()

    refute has_element?(lv, "#shipper-label-modal")
    assert has_element?(lv, "#sscc-serials-back")
  end
end
