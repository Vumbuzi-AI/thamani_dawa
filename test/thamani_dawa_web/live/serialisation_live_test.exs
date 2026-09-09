defmodule ThamaniDawaWeb.SerialisationLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Repo
  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.Serialisation.{SerialisedCode, Shipment, Sscc, SsccItem}

  @gtin "06164005056791"

  setup do
    organization = organization_fixture(%{kind: :distributor})
    admin = user_fixture(%{organization_id: organization.id})

    {:ok, item} =
      SerialCatalog.ensure_item(admin.organization_id, %{
        gtin: @gtin,
        name: "Playground product 10"
      })

    {:ok, admin: admin, item: item}
  end

  defp sscc_run(admin, opts \\ []) do
    shipment =
      Repo.insert!(%Shipment{
        organization_id: admin.organization_id,
        user_id: admin.id,
        type: :sscc,
        status: :issued,
        batch: Keyword.get(opts, :batch, "HC-2608-A"),
        production_date: ~D[2026-08-03],
        expiry_date: ~D[2028-08-03],
        order_number: Keyword.get(opts, :order_number, "PO-10362-001"),
        material_description: "Temperature-controlled healthcare products",
        from_company_name: "Test GS1 company Ltd",
        from_address: "Nairobi, Kenya",
        to_company_name: "Central Medical Stores",
        to_address: "Enterprise Road, Nairobi"
      })

    sscc =
      Repo.insert!(%Sscc{
        organization_id: admin.organization_id,
        shipment_id: shipment.id,
        code: Keyword.get(opts, :code, "161640050000010001"),
        level: :pallet,
        extension_digit: "1"
      })

    Repo.insert!(%SsccItem{sscc_id: sscc.id, gtin: @gtin, count: 8, items: 8})

    {shipment, sscc}
  end

  defp serialised_run(admin, opts \\ []) do
    shipment =
      Repo.insert!(%Shipment{
        organization_id: admin.organization_id,
        user_id: admin.id,
        type: :serialised,
        status: :issued,
        batch: Keyword.get(opts, :batch, "HC-2608-B"),
        production_date: ~D[2026-08-10],
        expiry_date: ~D[2028-08-10],
        order_number: "PO-10362-002",
        from_company_name: "Test GS1 company Ltd",
        from_address: "Nairobi, Kenya",
        to_company_name: "Central Medical Stores",
        to_address: "Enterprise Road, Nairobi"
      })

    pallet =
      Repo.insert!(%Sscc{
        organization_id: admin.organization_id,
        shipment_id: shipment.id,
        code: Keyword.get(opts, :code, "161640050000010018"),
        level: :pallet
      })

    Repo.insert!(%SsccItem{sscc_id: pallet.id, gtin: @gtin, count: 8, items: 8})

    shippers =
      for {code, serial, index} <- [
            {"261640050000010110", "SHIP103621001", 0},
            {"261640050000010120", "SHIP103621002", 1}
          ] do
        shipper =
          Repo.insert!(%Sscc{
            organization_id: admin.organization_id,
            shipment_id: shipment.id,
            parent_sscc_id: pallet.id,
            code: code,
            serial: serial,
            level: :case
          })

        Repo.insert!(%SsccItem{sscc_id: shipper.id, gtin: @gtin, count: 4, items: 4})

        for n <- 1..4 do
          Repo.insert!(%SerialisedCode{
            organization_id: admin.organization_id,
            shipment_id: shipment.id,
            sscc_id: shipper.id,
            gtin: @gtin,
            serial: "HC1036220000#{index * 4 + n}"
          })
        end

        shipper
      end

    {shipment, pallet, shippers}
  end

  describe "batch list (Screen B)" do
    test "lists the batches generated for the GTIN", %{conn: conn, admin: admin} do
      sscc_run(admin)

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/batches")

      assert html =~ "HC-2608-A"
      assert html =~ "PO-10362-001"
      assert html =~ "1 labels"
      assert html =~ "1 Pallets"
      assert html =~ "1 batches"
    end

    test "never shows another organization's batches", %{conn: conn, admin: admin} do
      other_org = organization_fixture(%{kind: :distributor})
      other_admin = user_fixture(%{organization_id: other_org.id})
      sscc_run(other_admin, batch: "NOT-YOURS")

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/batches")

      refute html =~ "NOT-YOURS"
      assert html =~ "No SSCC batches for this product yet"
    end

    test "searching filters by batch and can be reset", %{conn: conn, admin: admin} do
      sscc_run(admin, batch: "HC-2608-A")
      sscc_run(admin, batch: "HC-2608-Z", code: "161640050000010025")

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/batches")

      html = lv |> form("#batch-search", search: "2608-Z") |> render_change()

      assert html =~ "HC-2608-Z"
      refute html =~ "HC-2608-A"

      assert lv |> element("button", "Reset") |> render_click() =~ "HC-2608-A"
    end

    test "View pallets opens the label modal with the issued SSCC", %{conn: conn, admin: admin} do
      {shipment, _sscc} = sscc_run(admin)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/batches")

      html = lv |> element("#view-pallets-#{shipment.id}") |> render_click()

      assert html =~ "Pallet labels"
      assert html =~ "161640050000010001"
      # The label carries the AI lines its Data Matrix encodes (§10).
      assert html =~ "(00) 161640050000010001"
      assert html =~ "(37) 8"
      assert has_element?(lv, "#pallet-labels-modal")
    end

    test "the modal reopens from its own URL", %{conn: conn, admin: admin} do
      {shipment, _sscc} = sscc_run(admin)

      {:ok, _lv, html} =
        live(
          log_in_user(conn, admin),
          ~p"/org/serialisation/#{@gtin}/batches?modal=pallet-labels&batch_id=#{shipment.id}"
        )

      assert html =~ "Pallet labels"
      assert html =~ "161640050000010001"
    end
  end

  describe "SSCC group list (Screen D)" do
    test "groups serialised output by pallet SSCC with consistent counts", %{
      conn: conn,
      admin: admin
    } do
      serialised_run(admin)

      {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/groups")

      assert html =~ "161640050000010018"
      assert html =~ "HC-2608-B"
      assert html =~ "2 Shippers"
      assert html =~ "8 Primary serials"
      assert html =~ "1 groups"
    end

    test "the Shippers modal lists each shipper and its serial count", %{
      conn: conn,
      admin: admin
    } do
      {_shipment, pallet, _shippers} = serialised_run(admin)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/groups")

      html = lv |> element("#shippers-#{pallet.id}") |> render_click()

      assert html =~ "Shipper Serials"
      assert html =~ "261640050000010110"
      assert html =~ "(21) SHIP103621001"
      assert html =~ "Serials (4)"
      assert html =~ "Shipper (2)"
      assert html =~ "Primary (8)"
    end

    test "the Primary tab paginates the serials", %{conn: conn, admin: admin} do
      {_shipment, pallet, _shippers} = serialised_run(admin)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/groups")

      html = lv |> element("#serials-#{pallet.id}") |> render_click()

      assert html =~ "Primary Serials"
      assert html =~ "HC10362200001"
      assert html =~ "(21) HC10362200008"
      assert html =~ "Showing 8 of 8 items"
    end

    test "a shipper drills into only its own serials", %{conn: conn, admin: admin} do
      {_shipment, pallet, [shipper, _other]} = serialised_run(admin)

      {:ok, _lv, html} =
        live(
          log_in_user(conn, admin),
          ~p"/org/serialisation/#{@gtin}/groups?modal=primary&sscc_id=#{pallet.id}&shipper_id=#{shipper.id}"
        )

      assert html =~ "HC10362200001"
      refute html =~ "HC10362200005"
      assert html =~ "Showing 4 of 8 items"
    end

    test "a shipper from another group is ignored rather than obeyed", %{
      conn: conn,
      admin: admin
    } do
      {_shipment, pallet, _shippers} = serialised_run(admin)

      {:ok, _lv, html} =
        live(
          log_in_user(conn, admin),
          ~p"/org/serialisation/#{@gtin}/groups?modal=primary&sscc_id=#{pallet.id}&shipper_id=999999"
        )

      assert html =~ "Showing 8 of 8 items"
    end

    test "the Label modal shows the pallet label", %{conn: conn, admin: admin} do
      {_shipment, pallet, _shippers} = serialised_run(admin)

      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/groups")

      html = lv |> element("#label-#{pallet.id}") |> render_click()

      assert html =~ "SSCC Label"
      assert html =~ "(00) 161640050000010018"
    end
  end

  describe "export" do
    test "streams a CSV of the group's serials, preserving leading zeroes", %{
      conn: conn,
      admin: admin
    } do
      {_shipment, pallet, _shippers} = serialised_run(admin)

      conn =
        get(log_in_user(conn, admin), ~p"/org/serialisation/#{@gtin}/groups/#{pallet.id}/export")

      assert ["text/csv" <> _rest] = get_resp_header(conn, "content-type")

      assert ["attachment; filename=\"serials-" <> _name] =
               get_resp_header(conn, "content-disposition")

      body = response(conn, 200)

      assert body =~ "pallet_sscc,shipper_sscc,shipper_serial,gtin,serial"
      assert body =~ ~s("\t06164005056791")
      assert body =~ "HC10362200008"
      assert length(String.split(String.trim(body), "\r\n")) == 9
    end

    test "another organization cannot export the group", %{conn: conn, admin: admin} do
      {_shipment, pallet, _shippers} = serialised_run(admin)

      other_org = organization_fixture(%{kind: :distributor})
      other_admin = user_fixture(%{organization_id: other_org.id})

      assert_raise Ecto.NoResultsError, fn ->
        get(
          log_in_user(conn, other_admin),
          ~p"/org/serialisation/#{@gtin}/groups/#{pallet.id}/export"
        )
      end
    end
  end
end
