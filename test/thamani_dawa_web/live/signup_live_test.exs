defmodule ThamaniDawaWeb.SignupLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @gs1_prefix "0614141"

  describe "signup" do
    test "creates an organization, admin, and selected first site in three steps",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> complete_organization_step(%{
        name: "Acme Pharmacy",
        license_number: "LIC-1",
        operating_models: ["pharmacy"]
      })

      assert has_element?(view, "#site-setup-form")

      view
      |> complete_site_step(%{name: "Acme Main", address: "Nairobi", gln: "0614141000784"})

      assert has_element?(view, "#signup-form")
      assert has_element?(view, "#signup-submit", "Complete setup")
      assert has_element?(view, "#signup-form input[name='start_tour'][value='true']")

      view
      |> form("#signup-form",
        user: %{
          first_name: "Jane",
          last_name: "Admin",
          email: "jane@example.com",
          password: "secretpass12",
          accepted_legal_terms: "true"
        }
      )
      |> render_submit()

      assert has_element?(view, "#signup-form[phx-trigger-action][action='/login']")

      organization = Repo.get_by!(Organization, name: "Acme Pharmacy")
      assert organization.license_number == "LIC-1"
      assert organization.slug == "acme-pharmacy"
      assert organization.operating_models == [:pharmacy]
      assert organization.gs1_company_prefix == @gs1_prefix

      site = Repo.get_by!(Site, organization_id: organization.id)
      assert site.name == "Acme Main"
      assert site.activities == [:pharmacy]
      assert site.address == "Nairobi"
      assert site.gln == "0614141000784"
    end

    test "shows the error on the admin form when the email is already taken", %{conn: conn} do
      existing = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> complete_organization_step(%{
        name: "Other Pharmacy",
        license_number: "LIC-2",
        operating_models: ["pharmacy"]
      })

      view
      |> form("#site-setup-form", site: %{name: "Other Main"})
      |> render_submit()

      html =
        view
        |> form("#signup-form",
          user: %{
            first_name: "Someone",
            last_name: "Else",
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

      view = select_operating_models(view, ["pharmacy"])

      html =
        view
        |> form("#organization-setup-form",
          organization: %{
            name: "Other Pharmacy",
            license_number: "",
            operating_models: ["pharmacy"],
            gs1_company_prefix: @gs1_prefix
          }
        )
        |> render_submit()

      assert html =~ "Please enter your license number"
      refute has_element?(view, "#signup-form")
      refute Repo.get_by(Organization, name: "Other Pharmacy")
    end

    test "requires a GS1 company prefix for organizations that dispense", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = select_operating_models(view, ["pharmacy"])

      html =
        view
        |> form("#organization-setup-form",
          organization: %{
            name: "No Prefix Pharmacy",
            license_number: "LIC-NOPREFIX",
            operating_models: ["pharmacy"]
          }
        )
        |> render_submit()

      assert html =~ "Please enter your GS1 company prefix"
      refute has_element?(view, "#site-setup-form")
    end

    test "keeps the user on the organization step when GS1 does not know the prefix", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = select_operating_models(view, ["pharmacy"])

      view
      |> form("#organization-setup-form",
        organization: %{
          name: "Unknown Prefix Pharmacy",
          license_number: "LIC-UNKNOWN",
          operating_models: ["pharmacy"],
          gs1_company_prefix: "0000000"
        }
      )
      |> render_submit()

      html = render_async(view, 5_000)

      assert html =~ "couldn&#39;t find this prefix in the GS1 registry"

      html =
        view
        |> form("#organization-setup-form",
          organization: %{
            name: "Unknown Prefix Pharmacy",
            license_number: "LIC-UNKNOWN",
            operating_models: ["pharmacy"],
            gs1_company_prefix: "0000000"
          }
        )
        |> render_submit()

      assert html =~ "couldn&#39;t find this GS1 company prefix"
      refute has_element?(view, "#site-setup-form")
    end

    test "validates both wizard steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = select_operating_models(view, ["pharmacy"])

      html =
        view
        |> form("#organization-setup-form",
          organization: %{
            name: "A",
            license_number: "",
            operating_models: ["pharmacy"],
            gs1_company_prefix: @gs1_prefix
          }
        )
        |> render_change()

      assert html =~ "Please enter your license number"

      view
      |> complete_organization_step(%{
        name: "A",
        license_number: "LIC-A",
        operating_models: ["pharmacy"]
      })

      html =
        view
        |> form("#site-setup-form", site: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      refute has_element?(view, "#signup-form")

      view
      |> form("#site-setup-form", site: %{name: "Main"})
      |> render_submit()

      html =
        view
        |> form("#signup-form",
          user: %{first_name: "", last_name: "", email: "notanemail", password: ""}
        )
        |> render_change()

      assert html =~ "Please enter a valid email"
    end

    test "selecting operating models recommends the correct first site activities", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> complete_organization_step(%{
        name: "Lab Only Co",
        license_number: "LIC-LAB",
        operating_models: ["laboratory"]
      })

      assert has_element?(view, "input[name='site[activities][]'][value='laboratory']")
      refute has_element?(view, "input[name='site[activities][]'][value='pharmacy']")

      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> complete_organization_step(%{
        name: "Distribution Only Co",
        license_number: "LIC-DIST",
        operating_models: ["distributor"]
      })

      assert has_element?(view, "input[name='site[activities][]'][value='distribution']")
      refute has_element?(view, "input[name='site[activities][]'][value='pharmacy']")
    end

    test "makes multi-selection explicit and shows the selected count", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/signup")

      assert html =~ "Select all that apply"
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
      |> complete_organization_step(%{
        name: "Consent Health",
        license_number: "LIC-CONSENT",
        operating_models: ["pharmacy"]
      })

      view
      |> form("#site-setup-form", site: %{name: "Consent Main"})
      |> render_submit()

      assert has_element?(view, "input[name='user[accepted_legal_terms]'][required]")
      assert has_element?(view, "a[href='/terms'][target='_blank']", "Terms of Service")
      assert has_element?(view, "a[href='/privacy'][target='_blank']", "Privacy Policy")

      html =
        view
        |> element("#signup-form")
        |> render_submit(%{
          "user" => %{
            "first_name" => "Consent",
            "last_name" => "Admin",
            "email" => "consent@example.com",
            "password" => "secretpass12",
            "accepted_legal_terms" => "false"
          }
        })

      assert html =~ "You must accept the Terms of Service and Privacy Policy"
      refute Repo.get_by(Organization, name: "Consent Health")

      view
      |> form("#signup-form",
        user: %{
          first_name: "Consent",
          last_name: "Admin",
          email: "consent@example.com",
          password: "secretpass12",
          accepted_legal_terms: "true"
        }
      )
      |> render_submit()

      user = Repo.get_by!(ThamaniDawa.Accounts.User, email: "consent@example.com")
      assert user.name == "Consent Admin"
      assert %DateTime{} = user.legal_terms_accepted_at
      assert user.legal_policy_version == "2026-10-29"
    end

    test "back preserves organization data and step one never writes records", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> complete_organization_step(%{
        name: "Lab and Distribution Co",
        license_number: "LIC-MULTI",
        operating_models: ["laboratory", "distributor"]
      })

      refute Repo.get_by(Organization, name: "Lab and Distribution Co")

      view |> element("#site-back") |> render_click()

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

  # Ticks the given operating models. The GS1 company prefix field only
  # appears once a model that needs one is selected, so this runs before
  # the organization step can be filled in.
  defp select_operating_models(view, models) do
    view
    |> form("#organization-setup-form", organization: %{operating_models: models})
    |> render_change(%{"_target" => ["organization", "operating_models"]})

    view
  end

  # Completes the organization step of the wizard: the first submit asks GS1
  # about the company prefix, so the wizard needs a second Continue once the
  # registry has answered.
  defp complete_organization_step(view, organization) do
    organization =
      organization
      |> Map.put_new(:license_number, "LIC-1")
      |> Map.put_new(:gs1_company_prefix, @gs1_prefix)

    view = select_operating_models(view, organization.operating_models)

    view
    |> form("#organization-setup-form", organization: organization)
    |> render_submit()

    render_async(view, 5_000)

    view
    |> form("#organization-setup-form", organization: organization)
    |> render_submit()

    view
  end

  # Completes the first location step of the wizard. Like the organization
  # step, a site GLN is checked against the GS1 registry, so the wizard needs
  # a second Continue once the registry has answered.
  defp complete_site_step(view, site) do
    view
    |> form("#site-setup-form", site: site)
    |> render_submit()

    if site[:gln] do
      render_async(view, 5_000)

      view
      |> form("#site-setup-form", site: site)
      |> render_submit()
    end

    view
  end
end
