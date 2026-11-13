defmodule ThamaniDawaWeb.DistributorInvoiceLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor.{Billing, SerialPayment}
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.UserAuth

  defp log_in(conn, user), do: conn |> init_test_session(%{}) |> UserAuth.log_in_user(user)

  setup %{conn: conn} do
    distributor = distributor_user_fixture()
    %{conn: log_in(conn, distributor), distributor: distributor}
  end

  test "paid invoice shows brand, invoice details, tax, totals, and remittance", %{
    conn: conn,
    distributor: distributor
  } do
    payment = prepay_allowance_fixture(distributor.organization_id, distributor, 200)
    {:ok, view, _html} = live(conn, ~p"/distributor/billing/invoices/#{payment.id}")

    assert has_element?(view, "#distributor-serial-invoice.printable-invoice")
    assert has_element?(view, "#invoice-brand-logo[src='/images/logo.png']")
    assert has_element?(view, "#invoice-number", payment.invoice_number)
    assert has_element?(view, "#invoice-issue-date")
    assert has_element?(view, "#invoice-bill-to")
    assert has_element?(view, "#invoice-paid-stamp.absolute.right-8.top-8.rotate-12", "PAID")
    assert has_element?(view, "#invoice-line-items")
    assert has_element?(view, "#invoice-totals", "VAT")
    assert has_element?(view, "#invoice-totals", "Total")
    assert has_element?(view, "#invoice-remittance")
    refute has_element?(view, "#distributor-serial-invoice.printable-lab-report")
  end

  test "pending payment cannot render a paid invoice", %{conn: conn, distributor: distributor} do
    organization = Organizations.get_organization!(distributor.organization_id)
    {:ok, organization} = Billing.choose_prepay(organization)

    payment =
      Repo.insert!(%SerialPayment{
        organization_id: organization.id,
        initiated_by_id: distributor.id,
        kind: "prepay",
        method: "mpesa",
        status: "pending",
        quantity: 100,
        buffer_quantity: 0,
        unit_price: Decimal.new("2.00"),
        amount_excl_vat: Decimal.new("200.00"),
        vat_amount: Decimal.new("32.00"),
        amount: Decimal.new("232.00")
      })

    assert {:error, {:live_redirect, %{to: "/distributor/billing"}}} =
             live(conn, ~p"/distributor/billing/invoices/#{payment.id}")
  end
end
