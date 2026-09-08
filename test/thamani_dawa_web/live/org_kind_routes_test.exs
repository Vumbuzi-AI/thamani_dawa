defmodule ThamaniDawaWeb.OrgKindRoutesTest do
  @moduledoc """
  Distributor/manufacturer organizations only ever see the serialisation
  module; healthcare (pharmacy/lab) organizations never see it
  (serialisation.md §1). This exercises the router guard directly.
  """

  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawaWeb.UserAuth

  defp admin_for(kind) do
    organization = organization_fixture(%{kind: kind})
    user_fixture(%{organization_id: organization.id})
  end

  describe "a distributor admin" do
    test "can reach the serialisation catalog", %{conn: conn} do
      admin = admin_for(:distributor)
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:ok, _view, _html} = live(conn, ~p"/org/serialisation")
    end

    test "is bounced away from the product catalog", %{conn: conn} do
      admin = admin_for(:distributor)
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:error, {:redirect, %{to: "/org/serialisation"}}} = live(conn, ~p"/org/products")
    end

    test "is bounced away from suppliers", %{conn: conn} do
      admin = admin_for(:distributor)
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:error, {:redirect, %{to: "/org/serialisation"}}} = live(conn, ~p"/org/suppliers")
    end

    test "logging in lands on the serialisation catalog", %{conn: conn} do
      admin = admin_for(:distributor)

      conn =
        post(conn, ~p"/login", %{"email" => admin.email, "password" => valid_user_password()})

      assert redirected_to(conn) == ~p"/org/serialisation"
    end
  end

  describe "a healthcare admin" do
    test "can reach the product catalog", %{conn: conn} do
      admin = admin_for(:healthcare)
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:ok, _view, _html} = live(conn, ~p"/org/products")
    end

    test "is bounced away from serialisation", %{conn: conn} do
      admin = admin_for(:healthcare)
      conn = conn |> init_test_session(%{}) |> UserAuth.log_in_user(admin)

      assert {:error, {:redirect, %{to: "/org/dashboard"}}} = live(conn, ~p"/org/serialisation")
    end
  end
end
