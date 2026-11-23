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

  test "a minted mini-SSCC is itself a case, broken from the case page, not the batch page", %{
    conn: conn
  } do
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

    {:ok, lv, _html} = live(conn, ~p"/distributor/batches/#{child.id}")

    refute has_element?(lv, "#break-case-button")
    refute has_element?(lv, "#break-bulk-button")
    assert has_element?(lv, "#batch-sscc", child.sscc)
  end

  test "the batch page shows the trail", %{conn: conn} do
    %{conn: conn, batch: batch} = visit_batch(conn)

    {:ok, lv, _html} = live(conn, ~p"/distributor/batches/#{batch.id}")

    assert has_element?(lv, "#batch-trail", "This batch hasn't been shipped onward.")
    assert has_element?(lv, "#batch-status", "Active")
  end

  test "a depleted batch does not offer the split", %{conn: conn} do
    %{conn: conn, batch: batch, user: user, organization: organization} = visit_batch(conn)

    assert {:ok, _children} =
             Batches.break_into_mini_ssccs(batch, [%{quantity: 60}], user.id)

    {:ok, lv, _html} = live(conn, ~p"/distributor/batches/#{batch.id}")
    refute has_element?(lv, "#break-bulk-button")
    assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 0
  end

  test "breaks a whole mixed case into mini-SSCCs and retires the case SSCC", %{conn: conn} do
    %{conn: conn, unit: unit, organization: organization, batch_a: batch_a, batch_b: batch_b} =
      visit_case(conn)

    {:ok, lv, _html} = live(conn, ~p"/distributor/cases/#{unit.id}")
    assert has_element?(lv, "#break-case-panel")
    assert has_element?(lv, "#sscc-contents")
    assert has_element?(lv, "#case-line-#{batch_a.id}")
    assert has_element?(lv, "#case-line-#{batch_b.id}")

    lv |> element("#add-sub-shipper-#{batch_b.id}") |> render_click()
    assert has_element?(lv, "#sub-shipper-#{batch_b.id}-2")

    html =
      lv
      |> form("#break-case-form", %{
        "allocations" => %{
          to_string(batch_a.id) => %{"1" => %{"quantity" => "60"}},
          to_string(batch_b.id) => %{
            "1" => %{"quantity" => "13"},
            "2" => %{"quantity" => "27"}
          }
        }
      })
      |> render_submit()

    assert html =~ "print and label"
    assert has_element?(lv, "#minted-mini-ssccs")
    assert has_element?(lv, "#case-retired")
    refute has_element?(lv, "#break-case-panel")

    unit = ThamaniDawa.Repo.get!(ThamaniDawa.Batches.LogisticUnit, unit.id)
    assert unit.status == :disaggregated
    assert Batches.get_batch!(organization.id, batch_a.id).status == :disaggregated
    assert Batches.get_batch!(organization.id, batch_b.id).status == :disaggregated
  end

  test "the batch page does not offer to break a cased batch — that lives on the case page", %{
    conn: conn
  } do
    %{conn: conn, batch_a: batch_a} = visit_case(conn)

    {:ok, lv, _html} = live(conn, ~p"/distributor/batches/#{batch_a.id}")

    refute has_element?(lv, "#break-bulk-button")
    refute has_element?(lv, "#break-case-button")
  end

  defp visit_case(conn) do
    organization = distributor_organization_fixture()
    site = warehouse_fixture(organization.id)
    user = distributor_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product_a = product_fixture(%{organization_id: organization.id})
    product_b = product_fixture(%{organization_id: organization.id})
    sscc = "006141411234567890"

    {:ok, unit} =
      %ThamaniDawa.Batches.LogisticUnit{}
      |> ThamaniDawa.Batches.LogisticUnit.changeset(%{
        organization_id: organization.id,
        sscc: sscc,
        kind: :case,
        source: :inbound,
        site_id: site.id
      })
      |> ThamaniDawa.Repo.insert()

    batch_a = cased_batch(organization, site, product_a, "LOT-A", 60, sscc, unit, user)
    batch_b = cased_batch(organization, site, product_b, "LOT-B", 40, sscc, unit, user)

    %{
      conn: log_in_user(conn, user),
      unit: unit,
      organization: organization,
      batch_a: batch_a,
      batch_b: batch_b
    }
  end

  defp cased_batch(org, site, product, batch_no, qty, sscc, unit, user) do
    {:ok, batch} =
      Batches.create_batch(org.id, %{
        "product_id" => product.id,
        "site_id" => site.id,
        "gtin" => product.gtin,
        "batch_no" => batch_no,
        "expiry_date" => "2027-06-01",
        "quantity" => qty,
        "remaining_quantity" => qty,
        "serials" => [],
        "sscc" => sscc,
        "logistic_unit_id" => unit.id
      })

    {:ok, batch} = Batches.receive_batch(batch, user.id)
    batch
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
