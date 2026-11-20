defmodule ThamaniDawaWeb.DistributorShipmentDocumentLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Sites

  setup %{conn: conn} do
    distributor = distributor_user_fixture(%{roles: [:admin, :distributor]})
    %{conn: log_in(conn, distributor), distributor: distributor}
  end

  defp log_in(conn, user) do
    conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(user)
  end

  test "an approved shipment offers a delivery note and a packing list", %{
    conn: conn,
    distributor: distributor
  } do
    prepay_allowance_fixture(distributor.organization_id, distributor)

    warehouse =
      Sites.get_site!(distributor.organization_id, distributor.current_site_id)

    batch =
      received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

    shipment =
      submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
        order_number: "PO-DOC-1",
        warehouse: warehouse
      })

    {:ok, submitted, _html} = live(conn, ~p"/distributor/shipments/#{shipment.id}")
    refute has_element?(submitted, "#delivery-note")
    refute has_element?(submitted, "#packing-list")

    assert {:ok, approved} =
             Distributor.approve_shipment(distributor.organization_id, distributor, shipment.id)

    {:ok, view, _html} = live(conn, ~p"/distributor/shipments/#{approved.id}")
    assert has_element?(view, "#delivery-note")
    assert has_element?(view, "#packing-list")

    {:ok, note, _html} = live(conn, ~p"/distributor/shipments/#{approved.id}/delivery-note")
    assert has_element?(note, "#shipment-delivery-note")
    assert has_element?(note, "#shipment-document-destination", approved.destination_company)
    assert has_element?(note, "#delivery-note-lines", batch.batch_no)
    assert has_element?(note, "#delivery-note-received-by")
    refute has_element?(note, "#delivery-note-lines", batch.serial)

    {:ok, list, _html} = live(conn, ~p"/distributor/shipments/#{approved.id}/packing-list")
    assert has_element?(list, "#shipment-packing-list")
    assert has_element?(list, "#packing-list-shippers", batch.serial)
    assert has_element?(list, "#packing-list-shippers", "SSCC")
  end

  test "documents stay closed until the shipment is approved", %{
    conn: conn,
    distributor: distributor
  } do
    warehouse = Sites.get_site!(distributor.organization_id, distributor.current_site_id)
    batch = received_unit_fixture(distributor.organization_id, warehouse.id, distributor.id)

    shipment =
      submitted_shipment_fixture(distributor.organization_id, distributor, [batch], %{
        warehouse: warehouse
      })

    assert {:error, {:redirect, %{to: "/distributor/shipments/" <> _id, flash: flash}}} =
             live(conn, ~p"/distributor/shipments/#{shipment.id}/delivery-note")

    assert flash["error"] == "Delivery documents are available once the shipment is approved."
  end
end
