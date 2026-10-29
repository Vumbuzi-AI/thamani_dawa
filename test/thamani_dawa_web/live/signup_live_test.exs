defmodule ThamaniDawaWeb.SignupLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  describe "signup" do
    test "creates an organization, admin, and selected first site in two steps",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      organization_attrs = %{
        organization: %{
          name: "Acme Pharmacy",
          license_number: "LIC-1",
          operating_models: ["pharmacy"]
        },
        site: %{name: "Acme Main", site_type: "pharmacy", address: "Nairobi"}
      }

      view |> form("#organization-setup-form", organization_attrs) |> render_submit()

      assert has_element?(view, "#signup-form")
      assert has_element?(view, "#signup-submit", "Complete setup")
      assert has_element?(view, "#signup-form input[name='start_tour'][value='true']")

      view
      |> form("#signup-form",
        user: %{
          name: "Jane Admin",
          email: "jane@example.com",
          password: "secret",
          accepted_legal_terms: "true"
        }
      )
      |> render_submit()

      assert has_element?(view, "#signup-form[phx-trigger-action][action='/login']")

      organization = Repo.get_by!(Organization, name: "Acme Pharmacy")
      assert organization.license_number == "LIC-1"
      assert organization.slug == "acme-pharmacy"
      assert organization.operating_models == [:pharmacy]

      site = Repo.get_by!(ThamaniDawa.Sites.Site, organization_id: organization.id)
      assert site.name == "Acme Main"
      assert site.site_type == :pharmacy
      assert site.address == "Nairobi"
    end

    test "shows the error on the admin form when the email is already taken", %{conn: conn} do
      existing = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> form("#organization-setup-form",
        organization: %{
          name: "Other Pharmacy",
          license_number: "LIC-2",
          operating_models: ["pharmacy"]
        },
        site: %{name: "Other Main", site_type: "pharmacy"}
      )
      |> render_submit()

      html =
        view
        |> form("#signup-form",
          user: %{
            name: "Someone Else",
            email: existing.email,
            password: "hello world!",
            accepted_legal_terms: "true"
          }
        )
        |> render_submit()

      assert html =~ "This email is already registered"
      refute Repo.get_by(Organization, name: "Other Pharmacy")
    end

    test "shows the error on the organization form when the license number is missing", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      html =
        view
        |> form("#organization-setup-form",
          organization: %{
            name: "Other Pharmacy",
            license_number: "",
            operating_models: ["pharmacy"]
          },
          site: %{name: "Other Main", site_type: "pharmacy"}
        )
        |> render_submit()

      assert html =~ "Please enter your license number"
      refute has_element?(view, "#signup-form")
      refute Repo.get_by(Organization, name: "Other Pharmacy")
    end

    test "validates both wizard steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      html =
        view
        |> form("#organization-setup-form",
          organization: %{name: "A", license_number: "", operating_models: ["pharmacy"]},
          site: %{name: ""}
        )
        |> render_change()

      assert html =~ "Please enter your license number"

      view
      |> form("#organization-setup-form",
        organization: %{
          name: "A",
          license_number: "LIC-A",
          operating_models: ["pharmacy"]
        },
        site: %{name: "Main", site_type: "pharmacy"}
      )
      |> render_submit()

      html =
        view
        |> form("#signup-form", user: %{name: "", email: "notanemail", password: ""})
        |> render_change()

      assert html =~ "Please enter a valid email"
    end

    test "selecting operating models recommends the correct first site type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> form("#organization-setup-form",
        organization: %{operating_models: ["laboratory"]},
        site: %{site_type: "pharmacy"}
      )
      |> render_change(%{"_target" => ["organization", "operating_models"]})

      assert has_element?(view, "select[name='site[site_type]'] option[selected][value='lab']")

      view
      |> form("#organization-setup-form",
        organization: %{operating_models: ["distributor"]},
        site: %{site_type: "lab"}
      )
      |> render_change(%{"_target" => ["organization", "operating_models"]})

      assert has_element?(
               view,
               "select[name='site[site_type]'] option[selected][value='warehouse']"
             )
    end

    test "makes multi-selection explicit and shows the selected count", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/signup")

      assert html =~ "Select all that apply"
      assert html =~ "Initial site"
      refute has_element?(view, "#operating-model-selection-count")

      view
      |> form("#organization-setup-form",
        organization: %{operating_models: ["pharmacy", "laboratory"]}
      )
      |> render_change(%{"_target" => ["organization", "operating_models"]})

      assert has_element?(view, "#operating-model-selection-count", "2 selected")

      assert has_element?(
               view,
               "input[name='organization[operating_models][]'][value='pharmacy'][checked]"
             )

      assert has_element?(
               view,
               "input[name='organization[operating_models][]'][value='laboratory'][checked]"
             )
    end

    test "requires and records legal consent before completing signup", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> form("#organization-setup-form",
        organization: %{
          name: "Consent Health",
          license_number: "LIC-CONSENT",
          operating_models: ["pharmacy"]
        },
        site: %{name: "Consent Main", site_type: "pharmacy"}
      )
      |> render_submit()

      assert has_element?(view, "input[name='user[accepted_legal_terms]'][required]")
      assert has_element?(view, "a[href='/terms'][target='_blank']", "Terms of Service")
      assert has_element?(view, "a[href='/privacy'][target='_blank']", "Privacy Policy")

      html =
        view
        |> element("#signup-form")
        |> render_submit(%{
          "user" => %{
            "name" => "Consent Admin",
            "email" => "consent@example.com",
            "password" => "secret",
            "accepted_legal_terms" => "false"
          }
        })

      assert html =~ "You must accept the Terms of Service and Privacy Policy"
      refute Repo.get_by(Organization, name: "Consent Health")

      view
      |> form("#signup-form",
        user: %{
          name: "Consent Admin",
          email: "consent@example.com",
          password: "secret",
          accepted_legal_terms: "true"
        }
      )
      |> render_submit()

      user = Repo.get_by!(ThamaniDawa.Accounts.User, email: "consent@example.com")
      assert %DateTime{} = user.legal_terms_accepted_at
      assert user.legal_policy_version == "2026-10-29"
    end

    test "back preserves organization data and step one never writes records", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> form("#organization-setup-form",
        organization: %{
          name: "Lab and Distribution Co",
          license_number: "LIC-MULTI",
          operating_models: ["laboratory", "distributor"]
        },
        site: %{name: "Central Warehouse", site_type: "warehouse"}
      )
      |> render_submit()

      refute Repo.get_by(Organization, name: "Lab and Distribution Co")

      view |> element("#onboarding-back") |> render_click()

      assert has_element?(
               view,
               "input[name='organization[name]'][value='Lab and Distribution Co']"
             )

      assert has_element?(
               view,
               "input[name='organization[operating_models][]'][value='laboratory'][checked]"
             )
    end

    test "does not crash on a malformed event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")
      assert render_change(view, "unexpected", %{"unexpected" => "shape"})
    end
  end
end
