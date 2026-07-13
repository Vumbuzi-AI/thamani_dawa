defmodule ThamaniDawaWeb.ReceiveStockLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.SitesFixtures

  describe "GS1 decoding" do
    test "empty GS1 input is accepted and does not produce a decode error", %{conn: conn} do
      user = user_fixture()
      _site = site_fixture(%{organization_id: user.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/pharmacy/receive-stock")

      html =
        lv
        |> form("form[phx-submit='decode_gs1']", raw_gs1: "")
        |> render_submit()

      refute html =~ "Couldn't decode that code"
      assert html =~ "Raw GS1 element string"
    end
  end
end
