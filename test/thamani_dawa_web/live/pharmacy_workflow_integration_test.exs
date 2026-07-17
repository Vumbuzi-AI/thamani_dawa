defmodule ThamaniDawaWeb.PharmacyWorkflowIntegrationTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Prescriptions

  test "pharmacist takes a dispatched batch through receive -> scan -> prescribe -> dispense -> verify",
       %{conn: conn} do
    organization = organization_fixture()
    site = site_fixture(%{organization_id: organization.id, site_type: :pharmacy})
    patient = patient_fixture(%{organization_id: organization.id})
    pharmacist = staff_fixture(%{organization_id: organization.id, site_id: site.id})
    gtin = unique_gtin()

    product =
      product_fixture(%{organization_id: organization.id, uom: "tablet", gtin: gtin})

    pending_batch =
      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        gtin: gtin,
        batch_no: "LOT-E2E-1",
        quantity: 50,
        pending: true
      })

    conn = log_in_user(conn, pharmacist)

    {:ok, receive_live, _html} = live(conn, ~p"/pharmacy/receive-stock")

    receive_live
    |> form("#receive-stock-gs1-form", raw_gs1: "01" <> gtin <> "10" <> "LOT-E2E-1")
    |> render_submit()

    assert render(receive_live) =~ "Stock received."

    received_batch = Batches.get_batch!(organization.id, pending_batch.id)
    assert received_batch.approver_id == pharmacist.id
    assert received_batch.remaining_quantity == 50

    {:ok, scan_live, _html} = live(conn, ~p"/pharmacy/scan")

    scan_live
    |> form("#scan-form", gtin: gtin)
    |> render_submit()

    assert has_element?(scan_live, "#scan-result-found")
    assert has_element?(scan_live, "#result-quantity", "50")
    assert has_element?(scan_live, "#result-site", site.name)

    {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

    assert index_live |> element("a", "+ New prescription") |> render_click()
    assert index_live |> element("button", "+ Add Item") |> render_click()

    assert {:error, {:live_redirect, %{to: prescription_path}}} =
             index_live
             |> form("form",
               prescription: %{
                 patient_id: patient.id,
                 payment_type: "Cash",
                 items: %{"0" => %{product_id: product.id, quantity_prescribed: "5"}}
               }
             )
             |> render_submit()

    prescription_id = prescription_path |> String.split("/") |> List.last() |> String.to_integer()

    [item] = Prescriptions.list_prescription_items(organization.id, prescription_id)
    assert item.quantity_prescribed == 5

    {:ok, show_live, _html} = live(conn, prescription_path)

    show_live
    |> form("form", %{"item_id" => item.id, "quantity" => "5"})
    |> render_submit()

    assert render(show_live) =~ "Item dispensed."

    dispensed_batch = Batches.get_batch!(organization.id, pending_batch.id)
    assert dispensed_batch.remaining_quantity == 45

    show_live
    |> form("form[phx-submit='verify_item']", %{"item_id" => item.id, "gtin" => gtin})
    |> render_submit()

    assert render(show_live) =~ "Item verified successfully."

    prescription = Prescriptions.get_prescription!(organization.id, prescription_id)
    assert prescription.status == :completed
  end
end
