defmodule ThamaniDawaWeb.SignupLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @org_name "Afya Test Org"
  @site_gln "0614141000784"

  describe "authenticated access" do
    test "redirects an authenticated user out of the signup wizard", %{conn: conn} do
      admin = user_fixture()

      assert {:error, {:redirect, %{to: "/login"}}} =
               live(log_in_user(conn, admin), ~p"/signup")
    end
  end

  describe "signup" do
    test "creates an organization, admin, and selected first site from GS1 details",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      assert has_element?(view, "#site-setup-form")

      view
      |> complete_site_step(%{gln: @site_gln})

      assert has_element?(view, "#signup-form")
      assert has_element?(view, "#signup-submit", "Create account")
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

      organization = Repo.get_by!(Organization, name: @org_name)
      assert organization.operating_models == [:pharmacy]
      assert is_nil(organization.license_number)
      assert organization.gs1_api_key_last4 == "-key"

      assert [%{prefix: "6160001", is_primary: true}] =
               Organizations.list_gs1_prefixes(organization.id)

      site = Repo.get_by!(Site, organization_id: organization.id)
      assert site.name == "Test Licensee"
      assert site.activities == [:pharmacy]
      assert site.address == "Nairobi, Kenya"
      assert site.gln == @site_gln
    end

    test "renders a neutral restoration state before the browser draft is resolved", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      assert has_element?(view, "#signup-restoring[role='status']", "Restoring your progress…")
    end

    test "describes the distributor operating model clearly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      distributor_card =
        "label:has(input[name='organization[operating_models][]'][value='distributor'])"

      assert has_element?(view, distributor_card, "Pharmaceutical distributor")

      assert has_element?(
               view,
               distributor_card,
               "Supply medicines to pharmacies, hospitals and other buyers."
             )
    end

    test "does not render an organization name field and advances to GS1 verification", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      refute has_element?(view, "input[name='organization[name]']")

      view
      |> form("#organization-setup-form", organization: %{operating_models: ["pharmacy"]})
      |> render_submit()

      assert has_element?(view, "#gs1-key-form")
      assert has_element?(view, "#gs1_api_key[type='text'][autocomplete='off']")
      assert has_element?(view, "#gs1_api_key-toggle")
      refute has_element?(view, "#gs1-key-form input[type='password']")
    end

    test "shows the verified organization without asking for a primary prefix", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view
      |> form("#organization-setup-form", organization: %{operating_models: ["pharmacy"]})
      |> render_submit()

      view
      |> form("#gs1-key-form", gs1: %{api_key: "test-member-key"})
      |> render_submit()

      render_async(view, 5_000)

      assert has_element?(view, "#gs1-organization-badge", @org_name)
      assert has_element?(view, "#gs1-organization-badge", "Verified organization")
      refute has_element?(view, "input[name='prefix']")
      refute render(view) =~ "Primary company prefix"
    end

    test "shows the error on the admin form when the email is already taken", %{conn: conn} do
      existing = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      view |> complete_site_step(%{gln: @site_gln})

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
      refute Repo.get_by(Organization, name: @org_name)
    end

    test "restores only the operating-model step because GS1 credentials are never drafted", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      render_hook(view, "restore_signup_draft", %{
        "version" => 1,
        "step" => "main_location",
        "organization" => %{
          "operating_models" => ["pharmacy", "laboratory", "distributor"],
          "name" => @org_name
        },
        "site" => %{
          "activities" => ["pharmacy", "laboratory", "distribution"],
          "gln" => @site_gln
        }
      })

      assert has_element?(view, "#step-panel-operating_model")
      refute has_element?(view, "input[name='organization[name]']")

      for model <- ~w(pharmacy laboratory distributor) do
        assert has_element?(
                 view,
                 "input[name='organization[operating_models][]'][value='#{model}'][checked]"
               )
      end
    end

    test "never restores administrator credentials or consent from a draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      render_hook(view, "restore_signup_draft", %{
        "version" => 1,
        "step" => "administrator",
        "organization" => %{
          "operating_models" => ["pharmacy"],
          "name" => @org_name
        },
        "site" => %{"activities" => ["pharmacy"], "gln" => @site_gln},
        "user" => %{
          "email" => "saved@example.com",
          "password" => "must-not-be-restored",
          "accepted_legal_terms" => "true"
        }
      })

      assert has_element?(view, "#organization-setup-form")
      refute has_element?(view, "#signup-form input[value='saved@example.com']")
      refute render(view) =~ "must-not-be-restored"
      refute has_element?(view, "input[name='user[accepted_legal_terms]'][checked]")
    end

    test "treats a GLN from the GS1 member account as verified", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      assert has_element?(view, "#site-setup-form")

      inactive_gln = "0614141000456"

      html =
        view
        |> form("#site-setup-form", site: %{gln: inactive_gln})
        |> render_change(%{"_target" => ["site", "gln"]})

      assert html =~ "Verified · Test Licensee Annex"
      refute html =~ "Checking with the GS1 registry"
    end

    test "validates each wizard step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      html =
        view
        |> form("#site-setup-form", site: %{})
        |> render_submit()

      assert html =~ "GLN is required"
      refute has_element?(view, "#signup-form")

      view |> complete_site_step(%{gln: @site_gln})

      html =
        view
        |> form("#signup-form",
          user: %{first_name: "", last_name: "", email: "notanemail", password: ""}
        )
        |> render_change()

      assert html =~ "Please enter a valid email"
    end

    test "selecting a single operating model forces the matching site activity", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["laboratory"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      # SIGNUP-1: no KMLTTB licence either, so a lab-only site with a
      # verified GLN goes straight on to the administrator step too.
      refute has_element?(view, "#site_kmlttb_facility_name")
      refute has_element?(view, "input[name='site[activity_choice]'][value='pharmacy']")
      assert has_element?(view, "#signup-form")

      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["distributor"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      # No PPB licence is collected at signup, so a distributor site with a
      # verified GLN goes straight on to the administrator step.
      refute has_element?(view, "#site_ppb_facility_name")
      assert has_element?(view, "#signup-form")
    end

    test "offers the four real-world site types but not wholesale + lab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy", "laboratory", "distributor"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      for value <- ~w(pharmacy laboratory pharmacy_laboratory distribution) do
        assert has_element?(view, "input[name='site[activity_choice]'][value='#{value}']")
      end
    end

    test "selecting the combined pharmacy + lab option sets both activities", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy", "laboratory"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      html =
        view
        |> form("#site-setup-form", site: %{activity_choice: "pharmacy_laboratory"})
        |> render_change()

      assert html =~ "input[name='site[activity_choice]'][value='pharmacy_laboratory']" or
               has_element?(
                 view,
                 "input[name='site[activity_choice]'][value='pharmacy_laboratory'][checked]"
               )
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

      view = complete_operating_model_step(view, ["pharmacy"])

      view |> complete_site_step(%{gln: @site_gln})

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
      refute Repo.get_by(Organization, name: @org_name)

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

    test "does not render organization-level PPB fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy", "distributor"])

      refute has_element?(view, "input[name='organization[ppb_facility_name]']")
      refute has_element?(view, "input[name='organization[license_number]']")

      assert has_element?(view, "#site-setup-form")
    end

    test "back preserves organization data across steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["laboratory", "distributor"])

      view |> element("#main-location-back") |> render_click()
      view |> element("#gs1-key-back") |> render_click()

      assert has_element?(view, "#organization-setup-form")

      assert has_element?(
               view,
               "input[name='organization[operating_models][]'][value='laboratory'][checked]"
             )

      assert has_element?(
               view,
               "input[name='organization[operating_models][]'][value='distributor'][checked]"
             )
    end

    test "does not crash on a malformed event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")
      assert render_change(view, "unexpected", %{"unexpected" => "shape"})
    end
  end

  defp complete_operating_model_step(view, models, _name \\ @org_name) do
    view
    |> form("#organization-setup-form", organization: %{operating_models: models})
    |> render_submit()

    view
    |> form("#gs1-key-form", gs1: %{api_key: "test-member-key"})
    |> render_submit()

    render_async(view, 5_000)

    view
    |> form("#gs1-continue-form", %{})
    |> render_submit()

    view
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  # Raw event dispatch rather than `form/3`, since some of these fields
  # (activity_choice, kmlttb_*) don't
  # exist as actual inputs in the DOM until an earlier field (the GLN, the
  # activity choice) has already resolved — `form/3` can only set values on
  # inputs that are currently rendered.
  defp submit_site(view, attrs) do
    render_submit(view, "continue_site", %{"site" => stringify_keys(attrs)})
  end

  # Completes the main-location step of the wizard. Each of the GLN and
  # KMLTTB checks is async and gated behind the previous one resolving
  # (KMLTTB fields aren't even rendered until the GLN matches), so
  # `continue_site` itself triggers the next pending check and flashes an
  # "press Continue again" error each time it's submitted with that check
  # still idle — this just keeps pressing it, once per check present in
  # `site`, until the step actually advances.
  defp complete_site_step(view, site) do
    gln_attrs = Map.take(site, [:gln])
    kmlttb_attrs = Map.take(site, [:kmlttb_facility_name, :kmlttb_license_number])

    view |> form("#site-setup-form", site: gln_attrs) |> render_submit()

    if site[:gln] && has_element?(view, "#site-setup-form") do
      render_async(view, 5_000)
      view |> form("#site-setup-form", site: gln_attrs) |> render_submit()
    end

    if kmlttb_attrs != %{} && has_element?(view, "#site-setup-form") do
      full = Map.merge(gln_attrs, kmlttb_attrs)
      view |> form("#site-setup-form", site: full) |> render_submit()
      render_async(view, 5_000)
      view |> form("#site-setup-form", site: full) |> render_submit()
    end

    view
  end
end
