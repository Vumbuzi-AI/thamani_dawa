defmodule ThamaniDawaWeb.SerialCatalogLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Gs1Api
  alias ThamaniDawa.Repo
  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.Serialisation.{SerialisedCode, Shipment, Sscc, SsccItem}

  setup do
    organization = organization_fixture(%{kind: :distributor})
    admin = user_fixture(%{organization_id: organization.id})
    {:ok, admin: admin}
  end

  describe "index" do
    test "lists the organization's serialisation catalog", %{conn: conn, admin: admin} do
      {:ok, _item} =
        SerialCatalog.ensure_item(admin.organization_id, %{
          gtin: "6161100000018",
          name: "Panadol 500mg"
        })

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/serialisation")

      assert html =~ "Panadol 500mg"
      assert html =~ "06161100000018"
    end

    test "shows the empty state when nothing has been added", %{conn: conn, admin: admin} do
      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/serialisation")

      assert html =~ "No GTINs in the serialisation catalog yet"
    end

    test "opens the issued SSCC and serialised-code lists from their counts", %{
      conn: conn,
      admin: admin
    } do
      {:ok, item} =
        SerialCatalog.ensure_item(admin.organization_id, %{
          gtin: "6161100000018",
          name: "Panadol 500mg"
        })

      sscc_shipment =
        Repo.insert!(%Shipment{
          organization_id: admin.organization_id,
          user_id: admin.id,
          type: :sscc,
          status: :issued,
          batch: "BATCH-SSCC"
        })

      serialised_shipment =
        Repo.insert!(%Shipment{
          organization_id: admin.organization_id,
          user_id: admin.id,
          type: :serialised,
          status: :issued,
          batch: "BATCH-SERIAL"
        })

      sscc =
        Repo.insert!(%Sscc{
          organization_id: admin.organization_id,
          shipment_id: sscc_shipment.id,
          code: "100000000000000018",
          level: :pallet,
          extension_digit: "1"
        })

      Repo.insert!(%SsccItem{sscc_id: sscc.id, gtin: item.gtin, count: 1, items: 24})

      Repo.insert!(%SerialisedCode{
        organization_id: admin.organization_id,
        shipment_id: serialised_shipment.id,
        gtin: item.gtin,
        serial: "SERIAL-ABC-123"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation")

      lv |> element("#show-ssccs-#{item.id}") |> render_click()
      assert has_element?(lv, "#serial-code-details-modal")
      assert has_element?(lv, "#serial-code-details", "100000000000000018")
      assert has_element?(lv, "#serial-code-details", "BATCH-SSCC")

      lv |> element("button", "Close") |> render_click()
      refute has_element?(lv, "#serial-code-details-modal")

      lv |> element("#show-serialised-#{item.id}") |> render_click()
      assert has_element?(lv, "#serial-code-details", "SERIAL-ABC-123")
      assert has_element?(lv, "#serial-code-details", "BATCH-SERIAL")
    end
  end

  describe "adding a GTIN" do
    test "a lookup previews without writing, and only Add saves", %{conn: conn, admin: admin} do
      Req.Test.stub(Gs1Api, fn conn ->
        Req.Test.json(conn, %{"name" => "Brufen 400mg", "company_name" => "Abbott"})
      end)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/new")

      lv
      |> form("#serial-gtin-form", gtin: "6161100000018")
      |> render_submit()

      assert render_async(lv) =~ "Brufen 400mg"
      # Still nothing persisted: searching must not write (§2.4.9).
      assert SerialCatalog.list_items(admin.organization_id) == []

      lv |> element("button", "Add to catalog") |> render_click()

      assert [item] = SerialCatalog.list_items(admin.organization_id)
      assert item.gtin == "06161100000018"
      assert item.name == "Brufen 400mg"
    end

    test "a GS1 rejection is shown in the member's own words", %{conn: conn, admin: admin} do
      Req.Test.stub(Gs1Api, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"result" => "Barcode does not exist on the platform"})
      end)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/new")

      lv |> form("#serial-gtin-form", gtin: "6161100000018") |> render_submit()

      assert render_async(lv) =~ "Barcode does not exist on the platform"
    end

    test "an invalid GTIN is rejected locally", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/new")

      lv |> form("#serial-gtin-form", gtin: "12345") |> render_submit()

      assert render_async(lv) =~ "Enter a valid GTIN"
    end
  end
end
