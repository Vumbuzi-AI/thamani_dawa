defmodule ThamaniDawaWeb.DistributorMobileUserPhoneTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawaWeb.UserAuth

  setup %{conn: conn} do
    distributor = distributor_user_fixture()
    prepay_allowance_fixture(distributor.organization_id, distributor, 100)
    conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(distributor)
    %{conn: conn, distributor: distributor}
  end

  test "create form shows an inline phone error and does not create an invalid user", %{
    conn: conn,
    distributor: distributor
  } do
    {:ok, view, _html} = live(conn, ~p"/distributor/mobile-users/new")

    assert has_element?(view, "#mobile_user_phone[type='tel']")

    html =
      view
      |> form("#distributor-mobile-user-form",
        mobile_user: %{
          name: "Bad Phone Packer",
          username: "bad.phone",
          email: "bad-phone@example.com",
          phone: "letters123"
        }
      )
      |> render_submit()

    assert html =~ "Enter a phone number using digits"

    refute Enum.any?(
             Distributor.list_mobile_users(distributor.organization_id),
             &(&1.name == "Bad Phone Packer")
           )
  end

  test "edit form rejects an invalid phone", %{conn: conn, distributor: distributor} do
    mobile_user = mobile_user_fixture(distributor.organization_id)
    {:ok, view, _html} = live(conn, ~p"/distributor/mobile-users/#{mobile_user.id}/edit")

    html =
      view
      |> form("#distributor-mobile-user-form",
        mobile_user: %{
          name: mobile_user.name,
          username: mobile_user.username,
          email: mobile_user.email,
          phone: "letters123"
        }
      )
      |> render_submit()

    assert html =~ "Enter a phone number using digits"

    assert Distributor.get_mobile_user!(distributor.organization_id, mobile_user.id).phone ==
             mobile_user.phone
  end
end
