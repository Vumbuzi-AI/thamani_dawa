defmodule ThamaniDawaWeb.DistributorBatchLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SuppliersFixtures

  alias ThamaniDawa.Batches

  test "adds and removes carton rows", %{conn: conn} do
    session = visit_batch(conn)

    {:ok, lv, _html} = open_batch(session)

    refute has_element?(lv, "#mini-sscc-form")
    lv |> element("#break-bulk-button") |> render_click()
    assert has_element?(lv, "#split-group-1")
    assert has_element?(lv, "#split-quantity-1")

    lv |> element("#add-split-group") |> render_click()
    assert has_element?(lv, "#split-group-2")

    lv |> element("#remove-split-group-2") |> render_click()
    refute has_element?(lv, "#split-group-2")
    assert has_element?(lv, "#split-group-1")
  end

  test "a successful split shows the new SSCCs and the remaining quantity", %{conn: conn} do
    %{batch: batch, organization: organization} =
      session =
      visit_batch(conn, %{"quantity" => 60, "remaining_quantity" => 60, "serials" => []})

    {:ok, lv, _html} = open_batch(session)
    lv |> element("#break-bulk-button") |> render_click()
    lv |> element("#add-split-group") |> render_click()

    html =
      lv
      |> form("#mini-sscc-form", %{
        "groups" => %{
          "1" => %{"quantity" => "25"},
          "2" => %{"quantity" => "15"}
        }
      })
      |> render_submit()

    assert html =~ "New mini-SSCCs"
    assert has_element?(lv, "#minted-mini-ssccs")

    # Full disaggregation: parent retired, leftover swept into a remainder carton.
    parent = Batches.get_batch!(organization.id, batch.id)
    assert parent.remaining_quantity == 0
    assert parent.status == :disaggregated

    children =
      Batches.list_batches(organization.id)
      |> Enum.filter(&(&1.source_batch_id == batch.id))
      |> Enum.sort_by(& &1.batch_no)

    assert length(children) == 3
    assert Enum.map(children, & &1.quantity) == [25, 15, 20]

    assert Enum.all?(children, fn child ->
             has_element?(lv, "#minted-mini-ssccs", child.sscc)
           end)
  end

  test "an over-quantity split shows the error and leaves the batch unchanged", %{conn: conn} do
    %{batch: batch, organization: organization} = session = visit_batch(conn)

    {:ok, lv, _html} = open_batch(session)
    lv |> element("#break-bulk-button") |> render_click()

    html =
      lv
      |> form("#mini-sscc-form", %{"groups" => %{"1" => %{"quantity" => "999"}}})
      |> render_submit()

    assert html =~ "exceeds the stock on hand"
    refute has_element?(lv, "#minted-mini-ssccs")
    assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 60
  end

  test "an invalid serial selection shows the error and leaves the batch unchanged", %{conn: conn} do
    %{batch: batch, organization: organization} =
      session =
      visit_batch(conn, %{
        "quantity" => 2,
        "remaining_quantity" => 2,
        "serials" => ["SN1", "SN2"]
      })

    {:ok, lv, _html} = open_batch(session)
    lv |> element("#break-bulk-button") |> render_click()

    html =
      lv
      |> form("#mini-sscc-form", %{
        "groups" => %{"1" => %{"quantity" => "2", "serials" => ["SN1"]}}
      })
      |> render_submit()

    assert html =~ "remaining serials"
    refute has_element?(lv, "#minted-mini-ssccs")

    parent = Batches.get_batch!(organization.id, batch.id)
    assert parent.remaining_quantity == 2
    assert parent.serials == ["SN1", "SN2"]
  end

  test "a mini-SSCC's own page offers the same split", %{conn: conn} do
    %{conn: conn, batch: batch, user: user} =
      visit_batch(conn, %{
        "quantity" => 4,
        "remaining_quantity" => 4,
        "serials" => ["SN1", "SN2", "SN3", "SN4"]
      })

    assert {:ok, [child | _rest]} =
             Batches.break_into_mini_ssccs(
               batch,
               [%{quantity: 2, serials: ["SN1", "SN2"]}],
               user.id
             )

    {:ok, lv, html} = live(conn, ~p"/distributor/batches/#{child.id}")

    assert html =~ "Split from"
    assert html =~ batch.batch_no
    assert has_element?(lv, "#split-from")
    assert has_element?(lv, "#break-bulk-button")
    assert has_element?(lv, "#batch-sscc", child.sscc)
  end

  test "the batch page shows the trail and records a status change", %{conn: conn} do
    %{conn: conn, batch: batch, organization: organization} = visit_batch(conn)

    {:ok, lv, _html} = live(conn, ~p"/distributor/batches/#{batch.id}")

    assert has_element?(lv, "#batch-trail", "This batch hasn't been shipped onward.")
    assert has_element?(lv, "#batch-status", "Active")
    assert has_element?(lv, "#status-target-expired")

    lv |> element("#status-target-expired") |> render_click()

    html = lv |> form("#status-form") |> render_submit()

    assert html =~ "Status updated."
    assert has_element?(lv, "#batch-status", "Expired")
    assert Batches.get_batch!(organization.id, batch.id).status == :expired
  end

  test "a depleted batch does not offer the split", %{conn: conn} do
    %{conn: conn, batch: batch, user: user, organization: organization} = visit_batch(conn)

    assert {:ok, _children} =
             Batches.break_into_mini_ssccs(batch, [%{quantity: 60}], user.id)

    {:ok, lv, _html} = live(conn, ~p"/distributor/batches/#{batch.id}")
    refute has_element?(lv, "#break-bulk-button")
    assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 0
  end

  defp visit_batch(conn, overrides \\ %{}) do
    organization = distributor_organization_fixture()
    site = warehouse_fixture(organization.id)
    user = distributor_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = product_fixture(%{organization_id: organization.id})
    supplier = supplier_fixture(%{organization_id: organization.id})

    attrs =
      Map.merge(
        %{
          "product_id" => product.id,
          "site_id" => site.id,
          "supplier_id" => supplier.id,
          "gtin" => product.gtin,
          "batch_no" => "LOT-UI",
          "manufacturer" => "Acme",
          "manufacture_date" => ~D[2026-01-15],
          "expiry_date" => ~D[2027-06-01],
          "quantity" => 60,
          "remaining_quantity" => 60,
          "cost_per_unit" => "10.00",
          "serials" => [],
          "sscc" => "006141411234567890"
        },
        overrides
      )

    {:ok, batch} = Batches.create_batch(organization.id, attrs)
    {:ok, batch} = Batches.receive_batch(batch, user.id)

    %{
      conn: log_in_user(conn, user),
      path: ~p"/distributor/batches/#{batch.id}",
      batch: batch,
      user: user,
      organization: organization
    }
  end

  defp open_batch(%{conn: conn, path: path}), do: live(conn, path)
end
