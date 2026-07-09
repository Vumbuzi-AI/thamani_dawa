defmodule ThamaniDawaWeb.SignupLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  describe "signup" do
    test "creates an organization, admin, and default site, then redirects to login", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      attrs = %{
        organization: %{name: "Acme Pharmacy", license_number: "LIC-1"},
        user: %{name: "Jane Admin", email: "jane@example.com", password: "hello world!"}
      }

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> form("form", attrs) |> render_submit()

      assert to == ~p"/login"

      organization = Repo.get_by!(Organization, name: "Acme Pharmacy")
      assert organization.license_number == "LIC-1"
      assert organization.slug == "acme-pharmacy"
    end

    test "shows the error on the admin form when the email is already taken", %{conn: conn} do
      existing = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/signup")

      attrs = %{
        organization: %{name: "Other Pharmacy", license_number: "LIC-2"},
        user: %{name: "Someone Else", email: existing.email, password: "hello world!"}
      }

      html = view |> form("form", attrs) |> render_submit()

      assert html =~ "This email is already registered"
      refute Repo.get_by(Organization, name: "Other Pharmacy")
    end

    test "shows the error on the organization form when the license number is missing", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      attrs = %{
        organization: %{name: "Other Pharmacy", license_number: ""},
        user: %{name: "Someone Else", email: "someone@example.com", password: "hello world!"}
      }

      html = view |> form("form", attrs) |> render_submit()

      assert html =~ "Please enter your license number"
      refute Repo.get_by(Organization, name: "Other Pharmacy")
    end

    test "validates the form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      attrs = %{
        organization: %{name: "A", license_number: ""},
        user: %{name: "", email: "notanemail", password: ""}
      }

      html = view |> form("form", attrs) |> render_change()

      assert html =~ "Please enter a valid email"
    end

    test "does not crash on a malformed validate event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      assert render_change(view, "validate", %{"unexpected" => "shape"})
    end
  end
end
