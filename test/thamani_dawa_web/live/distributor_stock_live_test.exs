defmodule ThamaniDawaWeb.DistributorStockLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Repo

  test "short-dated stock is a filter of the inventory batches", %{conn: conn} do
    org = distributor_organization_fixture()
    site = warehouse_fixture(org.id)
    distributor = distributor_user_fixture(%{organization_id: org.id, site_id: site.id})

    short =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-SHORT",
        expiry_date: Date.add(Date.utc_today(), 10)
      })

    _mid =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-MID",
        expiry_date: Date.add(Date.utc_today(), 45)
      })

    expired =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-EXPIRED",
        expiry_date: Date.add(Date.utc_today(), 20)
      })

    {:ok, _expired} =
      expired
      |> Ecto.Changeset.change(expiry_date: Date.add(Date.utc_today(), -5))
      |> Repo.update()

    _long =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-LONG",
        expiry_date: Date.add(Date.utc_today(), 200)
      })

    conn = log_in_user(conn, distributor)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/distributor/stock?expiry=critical")

    assert to =~ "view=batches"
    assert to =~ "expiry=critical"

    {:ok, view, html} = follow_redirect(live(conn, ~p"/distributor/stock?expiry=critical"), conn)

    assert has_element?(view, "#expiry-filter-critical[aria-checked='true']")
    assert has_element?(view, "#expiry-filter-expired")
    assert html =~ "Inventory"
    assert html =~ short.batch_no
    refute html =~ "LOT-MID"
    refute html =~ "LOT-EXPIRED"
    refute html =~ "LOT-LONG"

    html = view |> element("#expiry-filter-expired") |> render_click()
    assert html =~ "LOT-EXPIRED"
    refute html =~ short.batch_no
    refute html =~ "LOT-MID"

    html = view |> element("#expiry-filter-near") |> render_click()
    assert html =~ short.batch_no
    assert html =~ "LOT-MID"
    refute html =~ "LOT-EXPIRED"
    refute html =~ "LOT-LONG"

    {:ok, redirected, redirected_html} =
      follow_redirect(live(conn, ~p"/distributor/expiring"), conn)

    assert has_element?(redirected, "#expiry-filter-near")
    assert redirected_html =~ "LOT-SHORT"
    refute redirected_html =~ "LOT-LONG"
  end

  test "inventory batches list stock and quarantine, and leave shipment stock off the page", %{
    conn: conn
  } do
    org = distributor_organization_fixture()
    site = warehouse_fixture(org.id)
    distributor = distributor_user_fixture(%{organization_id: org.id, site_id: site.id})

    _on_hand =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-ON-HAND"
      })

    held =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-HELD"
      })

    {:ok, _} =
      held
      |> Ecto.Changeset.change(status: :quarantined)
      |> Repo.update()

    dispatched =
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        batch_no: "LOT-DISPATCHED"
      })

    {:ok, _} = ThamaniDawa.Batches.putaway(dispatched, %{"zone" => "dispatch"})

    conn = log_in_user(conn, distributor)
    {:ok, view, html} = live(conn, ~p"/distributor/products?view=batches")

    assert html =~ "Inventory"
    assert has_element?(view, "#distributor-batches")
    assert html =~ "LOT-ON-HAND"
    assert html =~ "LOT-HELD"
    refute html =~ "LOT-DISPATCHED"
    refute html =~ "Dock"
    refute html =~ "Picking"
    refute has_element?(view, ~s(a[href="/distributor/stock"]))

    {:ok, _view, quarantine_html} =
      live(conn, ~p"/distributor/products?#{%{view: "batches", hold: "quarantine"}}")

    assert quarantine_html =~ "LOT-HELD"
    refute quarantine_html =~ "LOT-ON-HAND"
  end
end
