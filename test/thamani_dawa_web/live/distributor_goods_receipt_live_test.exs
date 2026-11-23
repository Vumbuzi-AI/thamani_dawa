defmodule ThamaniDawaWeb.DistributorGoodsReceiptLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ProductsFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.Repo

  setup do
    organization = distributor_organization_fixture()
    warehouse = warehouse_fixture(organization.id)
    user = distributor_user_fixture(%{organization_id: organization.id, site_id: warehouse.id})
    {:ok, user} = Accounts.switch_current_site(Scope.for_user(user), warehouse.id)
    product = product_fixture(%{organization_id: organization.id})

    %{organization: organization, warehouse: warehouse, user: user, product: product}
  end

  test "a missing line is closed on the goods receipt", %{conn: conn} = ctx do
    receipt = receipt_fixture(ctx)
    discrepancy = discrepancy_fixture(ctx, receipt)

    conn = log_in_user(conn, ctx.user)
    {:ok, index, _html} = live(conn, ~p"/distributor/receiving")

    assert has_element?(index, "#receipt-open-lines-#{receipt.id}", "1 not confirmed")
    refute render(index) =~ "/distributor/discrepancies"

    {:ok, view, _html} = live(conn, ~p"/distributor/receiving/#{receipt.id}")

    assert has_element?(view, "#discrepancy-#{discrepancy.id}-found")
    assert has_element?(view, "#discrepancy-#{discrepancy.id}-lost")
    assert has_element?(view, "#discrepancy-#{discrepancy.id}-stolen")
    refute render(view) =~ "/distributor/discrepancies"

    view |> element("#discrepancy-#{discrepancy.id}-lost") |> render_click()

    view
    |> form("#resolve-discrepancy-form", %{"resolution_reference" => "INC-100"})
    |> render_submit()

    assert render(view) =~ "Line closed as lost."
    assert has_element?(view, "#goods-receipt-line-discrepancy-#{discrepancy.id}", "Lost")
    assert has_element?(view, "#goods-receipt-line-discrepancy-#{discrepancy.id}", "INC-100")
    refute has_element?(view, "#discrepancy-#{discrepancy.id}-lost")

    closed = GoodsReceipts.get_discrepancy!(ctx.organization.id, discrepancy.id)
    assert closed.status == :lost
    assert closed.resolution_reference == "INC-100"

    {:ok, index, _html} = live(conn, ~p"/distributor/receiving")
    refute has_element?(index, "#receipt-open-lines-#{receipt.id}")
  end

  test "lost and stolen stay open until an investigation reference is given",
       %{conn: conn} = ctx do
    receipt = receipt_fixture(ctx)
    discrepancy = discrepancy_fixture(ctx, receipt)

    conn = log_in_user(conn, ctx.user)
    {:ok, view, _html} = live(conn, ~p"/distributor/receiving/#{receipt.id}")

    view |> element("#discrepancy-#{discrepancy.id}-stolen") |> render_click()

    html =
      view
      |> form("#resolve-discrepancy-form", %{"resolution_reference" => ""})
      |> render_submit()

    assert html =~ "Could not close this line"
    assert has_element?(view, "#discrepancy-#{discrepancy.id}-stolen")
    assert GoodsReceipts.get_discrepancy!(ctx.organization.id, discrepancy.id).status == :open
  end

  test "a receipt with only a missing line still shows for that warehouse", %{conn: conn} = ctx do
    receipt = receipt_fixture(ctx)
    _discrepancy = discrepancy_fixture(ctx, receipt)

    conn = log_in_user(conn, ctx.user)
    {:ok, index, _html} = live(conn, ~p"/distributor/receiving")

    assert has_element?(index, "#receipt-open-lines-#{receipt.id}", "1 not confirmed")
  end

  test "the standalone discrepancies page is gone", %{conn: conn} = ctx do
    conn = get(log_in_user(conn, ctx.user), "/distributor/discrepancies")
    assert html_response(conn, 404)
  end

  defp receipt_fixture(ctx) do
    {:ok, receipt} =
      %GoodsReceipt{}
      |> GoodsReceipt.changeset(%{
        number: "GRN-#{System.unique_integer([:positive])}",
        posting_key: Ecto.UUID.generate(),
        received_at: DateTime.utc_now(:second),
        received_by_id: ctx.user.id
      })
      |> Ecto.Changeset.put_change(:organization_id, ctx.organization.id)
      |> Repo.insert()

    receipt
  end

  defp discrepancy_fixture(ctx, receipt) do
    GoodsReceipts.create_discrepancy!(ctx.organization.id, receipt.id, %{
      "sscc" => "061600010000000035",
      "gtin" => ctx.product.gtin,
      "batch_no" => "LOT-MISSING-#{System.unique_integer([:positive])}",
      "serial" => "SN-MISSING",
      "quantity" => 1,
      "expiry_date" => Date.add(Date.utc_today(), 365),
      "product_id" => ctx.product.id,
      "site_id" => ctx.warehouse.id
    })
  end
end
