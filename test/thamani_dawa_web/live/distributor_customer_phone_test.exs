defmodule ThamaniDawaWeb.DistributorCustomerPhoneTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.DistributorCustomers
  alias ThamaniDawaWeb.UserAuth

  setup %{conn: conn} do
    distributor = distributor_user_fixture()
    conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)
    %{conn: conn, distributor: distributor}
  end

  test "customer phone field is a telephone input and shows invalid phone inline on create", %{
    conn: conn,
    distributor: distributor
  } do
    {:ok, view, _html} = live(conn, ~p"/distributor/customers/new")

    assert has_element?(view, "#customer_phone[type='tel']")

    html =
      view
      |> form("#distributor-customer-form",
        customer: %{name: "Invalid Phone Clinic", phone: "12345678n"}
      )
      |> render_submit()

    assert html =~ "Enter a phone number using digits"

    refute Enum.any?(
             DistributorCustomers.list_customers(distributor.organization_id),
             &(&1.name == "Invalid Phone Clinic")
           )
  end

  test "edit form also renders a phone validation error", %{conn: conn, distributor: distributor} do
    customer = customer_fixture(distributor.organization_id)
    {:ok, view, _html} = live(conn, ~p"/distributor/customers/#{customer.id}/edit")

    html =
      view
      |> form("#distributor-customer-form",
        customer: %{name: customer.name, phone: "12345678n"}
      )
      |> render_submit()

    assert html =~ "Enter a phone number using digits"

    assert DistributorCustomers.get_customer!(distributor.organization_id, customer.id).phone ==
             customer.phone
  end
end
