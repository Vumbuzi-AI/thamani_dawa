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

  describe "org print and download overlays" do
    import ThamaniDawa.AccountsFixtures
    import ThamaniDawa.SitesFixtures

    alias ThamaniDawa.GoodsReceipts.Attachment

    test "Print opens the shared dialog and Download shows the ready overlay", %{conn: conn} do
      admin = user_fixture()
      _site = site_fixture(%{organization_id: admin.organization_id})
      receipt = org_receipt_fixture(admin)
      attachment = attachment_fixture(receipt, admin)

      {:ok, view, html} = live(log_in_user(conn, admin), ~p"/org/receiving/#{receipt.id}")

      assert html =~ "Goods receipt"
      assert has_element?(view, "#goods-receipt-print")
      assert has_element?(view, "#goods-receipt-document-#{attachment.id}-print")
      assert has_element?(view, "#goods-receipt-document-#{attachment.id}-download")
      refute has_element?(view, "#goods-receipt-print-dialog")
      refute has_element?(view, "#goods-receipt-download-ready")

      view |> element("#goods-receipt-print") |> render_click()
      assert has_element?(view, "#goods-receipt-print-dialog", "Print")
      assert has_element?(view, "#goods-receipt-print-dialog", "Send this document to a printer at your site.")
      assert has_element?(view, "#goods-receipt-print-dialog-printer", "This computer")

      view |> form("#goods-receipt-print-dialog-form") |> render_submit()
      refute has_element?(view, "#goods-receipt-print-dialog")

      view |> element("#goods-receipt-document-#{attachment.id}-print") |> render_click()
      assert has_element?(view, "#goods-receipt-print-dialog")
      view |> element("#goods-receipt-print-dialog button", "Cancel") |> render_click()
      refute has_element?(view, "#goods-receipt-print-dialog")

      view |> element("#goods-receipt-document-#{attachment.id}-download") |> render_click()
      assert has_element?(view, "#goods-receipt-download-ready", "Your file is ready")
      assert has_element?(view, "#goods-receipt-download-ready", "inv-KP-88120.pdf")
      assert has_element?(view, "#goods-receipt-download-ready", "ready")
      view |> element("#goods-receipt-download-ready button", "Done") |> render_click()
      refute has_element?(view, "#goods-receipt-download-ready")
    end

    test "the distributor receipt is unchanged", %{conn: conn} = ctx do
      receipt = receipt_fixture(ctx)
      conn = log_in_user(conn, ctx.user)
      {:ok, view, _html} = live(conn, ~p"/distributor/receiving/#{receipt.id}")

      refute has_element?(view, "#goods-receipt-print")
      refute has_element?(view, "#goods-receipt-print-dialog")
      refute has_element?(view, "#goods-receipt-download-ready")
    end

    defp org_receipt_fixture(admin) do
      {:ok, receipt} =
        %GoodsReceipt{}
        |> GoodsReceipt.changeset(%{
          number: "GRN-#{System.unique_integer([:positive])}",
          posting_key: Ecto.UUID.generate(),
          received_at: DateTime.utc_now(:second),
          received_by_id: admin.id
        })
        |> Ecto.Changeset.put_change(:organization_id, admin.organization_id)
        |> Repo.insert()

      receipt
    end

    defp attachment_fixture(receipt, admin) do
      %Attachment{}
      |> Attachment.changeset(%{
        doc_type: :invoice,
        filename: "inv-KP-88120.pdf",
        path: "/uploads/goods_receipts/#{receipt.id}/inv-KP-88120.pdf",
        content_type: "application/pdf",
        byte_size: 312_000,
        goods_receipt_id: receipt.id,
        uploaded_by_id: admin.id
      })
      |> Repo.insert!()
    end
  end
end
