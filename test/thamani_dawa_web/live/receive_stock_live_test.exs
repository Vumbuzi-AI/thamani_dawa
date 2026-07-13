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

      assert has_element?(lv, "form#receive-stock-gs1-form input[name='raw_gs1']")

      form = form(lv, "#receive-stock-gs1-form", raw_gs1: "")

      render_submit(form)

      refute has_element?(lv, "#gs1-decode-error")
    end

    test "invalid GS1 input displays a decode error", %{conn: conn} do
      user = user_fixture()
      _site = site_fixture(%{organization_id: user.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/pharmacy/receive-stock")

      assert has_element?(lv, "form#receive-stock-gs1-form input[name='raw_gs1']")

      invalid_form = form(lv, "#receive-stock-gs1-form", raw_gs1: "01" <> "0061414100001A")

      render_submit(invalid_form)

      assert has_element?(lv, "#gs1-decode-error", "Couldn't decode that code")
    end

    test "a successful GS1 decode clears a previous decode error", %{conn: conn} do
      user = user_fixture()
      _site = site_fixture(%{organization_id: user.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/pharmacy/receive-stock")

      invalid_form = form(lv, "#receive-stock-gs1-form", raw_gs1: "01" <> "0061414100001A")
      render_submit(invalid_form)
      assert has_element?(lv, "#gs1-decode-error", "Couldn't decode that code")

      valid_form = form(lv, "#receive-stock-gs1-form", raw_gs1: "01" <> "00614141000012")
      render_submit(valid_form)

      refute has_element?(lv, "#gs1-decode-error")
    end

    test "invalid GS1 shows an error and a subsequent valid decode clears it", %{conn: conn} do
      user = user_fixture()
      _site = site_fixture(%{organization_id: user.organization_id})

      {:ok, lv, _html} = live(log_in_user(conn, user), ~p"/pharmacy/receive-stock")

      assert has_element?(lv, "form#receive-stock-gs1-form input[name='raw_gs1']")

      # Submit an invalid GS1 (truncated GTIN) -> should show error
      invalid_form = form(lv, "#receive-stock-gs1-form", raw_gs1: "01")
      _invalid_html = render_submit(invalid_form)

      assert has_element?(lv, "#gs1-decode-error", "Couldn't decode that code")

      # Now submit a valid GS1 -> error should be cleared
      valid_form = form(lv, "#receive-stock-gs1-form", raw_gs1: "01" <> "00614141000012")
      _valid_html = render_submit(valid_form)

      refute has_element?(lv, "#gs1-decode-error")
    end
  end
end
