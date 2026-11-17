defmodule ThamaniDawaWeb.SignupLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites.Site

  @gs1_prefix "0614141"
  @site_gln "0614141000784"
  @unique_pharmacy_ppb %{ppb_facility_name: "Unique Pharmacy", license_number: "AB1XXXX9999"}

  describe "authenticated access" do
    test "redirects an authenticated user out of the signup wizard", %{conn: conn} do
      admin = user_fixture()

      assert {:error, {:redirect, %{to: "/login"}}} =
               live(log_in_user(conn, admin), ~p"/signup")
    end
  end

  describe "signup" do
    test "creates an organization, admin, and selected first site in four steps",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])
      complete_regulatory_details_step(view, ["pharmacy"])

      assert has_element?(view, "#site-setup-form")

      view
      |> complete_site_step(Map.merge(%{gln: @site_gln}, @unique_pharmacy_ppb))

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

      organization = Repo.get_by!(Organization, gs1_company_prefix: @gs1_prefix)
      assert organization.name == "Test Licensee"
      assert organization.operating_models == [:pharmacy]
      assert organization.gs1_company_prefix == @gs1_prefix
      assert is_nil(organization.license_number)
      assert is_nil(organization.ppb_facility_name)

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

    test "shows the error on the admin form when the email is already taken", %{conn: conn} do
      existing = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])
      complete_regulatory_details_step(view, ["pharmacy"])

      view |> complete_site_step(Map.merge(%{gln: @site_gln}, @unique_pharmacy_ppb))

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
      refute Repo.get_by(Organization, gs1_company_prefix: @gs1_prefix)
    end

    test "requires a GS1 company prefix for organizations that dispense", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      html =
        submit_regulatory_details(view, %{
          operating_models: ["pharmacy"],
          gs1_company_prefix: ""
        })

      assert html =~ "Please enter your GS1 company prefix"
      refute has_element?(view, "#site-setup-form")
    end

    test "explains the GS1 company prefix and links to GS1 Kenya", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      assert has_element?(view, "#gs1-prefix-help", "Not sure what this is?")

      assert has_element?(
               view,
               "#gs1-prefix-registration-link[href='https://gs1kenya.org/'][target='_blank'][rel='noopener noreferrer']"
             )
    end

    test "restores a saved onboarding step and reverifies its registry data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      render_hook(view, "restore_signup_draft", %{
        "version" => 1,
        "step" => "main_location",
        "organization" => %{
          "operating_models" => ["pharmacy", "laboratory", "distributor"],
          "gs1_company_prefix" => @gs1_prefix,
          "name" => "Untrusted saved name"
        },
        "site" => %{
          "activities" => ["pharmacy", "laboratory", "distribution"],
          "gln" => @site_gln
        }
      })

      assert has_element?(view, "#step-panel-main_location")
      assert has_element?(view, "#site-setup-form input[name='site[gln]'][value='#{@site_gln}']")

      render_async(view, 5_000)
      view |> element("#main-location-back") |> render_click()

      assert has_element?(view, "p", "Verified · matches Test Licensee")
      refute render(view) =~ "Untrusted saved name"

      view |> element("#regulatory-details-back") |> render_click()

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
          "gs1_company_prefix" => @gs1_prefix
        },
        "site" => %{"activities" => ["pharmacy"], "gln" => @site_gln},
        "user" => %{
          "email" => "saved@example.com",
          "password" => "must-not-be-restored",
          "accepted_legal_terms" => "true"
        }
      })

      assert has_element?(view, "#signup-form")
      refute has_element?(view, "#signup-form input[value='saved@example.com']")
      refute render(view) =~ "must-not-be-restored"
      refute has_element?(view, "input[name='user[accepted_legal_terms]'][checked]")
    end

    test "keeps the user on the regulatory details step when GS1 does not know the prefix", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      attrs = %{
        operating_models: ["pharmacy"],
        gs1_company_prefix: "0000000"
      }

      submit_regulatory_details(view, attrs)
      html = render_async(view, 5_000)

      assert html =~ "couldn&#39;t find this prefix in the GS1 registry"

      html = submit_regulatory_details(view, attrs)

      assert html =~ "couldn&#39;t find this GS1 company prefix"
      refute has_element?(view, "#site-setup-form")
    end

    test "blocks continue when the GS1 company prefix is found but no longer active", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      attrs = %{
        operating_models: ["pharmacy"],
        # Sentinel prefix the test stub answers with a withdrawn licence for.
        gs1_company_prefix: "9996141"
      }

      submit_regulatory_details(view, attrs)
      html = render_async(view, 5_000)

      assert html =~ "not currently active in the GS1 registry"

      html = submit_regulatory_details(view, attrs)

      assert html =~ "isn&#39;t currently active"
      refute has_element?(view, "#site-setup-form")
    end

    test "keeps organization name registry-controlled when GS1 cannot resolve one", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      refute has_element?(view, "input[type='text'][name='organization[name]']")

      submit_regulatory_details(view, %{
        operating_models: ["pharmacy"],
        gs1_company_prefix: "0000000"
      })

      render_async(view, 5_000)

      refute has_element?(view, "input[type='text'][name='organization[name]']")
    end

    test "blocks continue when the location GLN is found but no longer active", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])
      complete_regulatory_details_step(view, ["pharmacy"])

      assert has_element?(view, "#site-setup-form")

      # Sentinel GLN the test stub answers with a withdrawn licence for.
      inactive_gln = "9996141000454"

      view
      |> form("#site-setup-form", site: %{gln: inactive_gln})
      |> render_submit()

      html = render_async(view, 5_000)

      assert html =~ "not currently active in the GS1 registry"

      html =
        view
        |> form("#site-setup-form", site: %{gln: inactive_gln})
        |> render_submit()

      assert html =~ "isn&#39;t currently active"
      refute has_element?(view, "#signup-form")
    end

    test "validates each wizard step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy"])

      complete_regulatory_details_step(view, ["pharmacy"])

      html =
        view
        |> form("#site-setup-form", site: %{})
        |> render_submit()

      assert html =~ "GLN is required"
      refute has_element?(view, "#signup-form")

      view |> complete_site_step(Map.merge(%{gln: @site_gln}, @unique_pharmacy_ppb))

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
      complete_regulatory_details_step(view, ["laboratory"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      assert has_element?(view, "input[name='site[activity_choice]'][value='laboratory']")
      refute has_element?(view, "input[name='site[activity_choice]'][value='pharmacy']")

      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["distributor"])
      complete_regulatory_details_step(view, ["distributor"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      assert has_element?(view, "input[name='site[activity_choice]'][value='distribution']")
      refute has_element?(view, "input[name='site[activity_choice]'][value='pharmacy']")
    end

    test "offers the four real-world site types but not wholesale + lab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy", "laboratory", "distributor"])
      complete_regulatory_details_step(view, ["pharmacy", "laboratory", "distributor"])
      submit_site(view, %{gln: @site_gln})
      render_async(view, 5_000)

      for value <- ~w(pharmacy laboratory pharmacy_laboratory distribution) do
        assert has_element?(view, "input[name='site[activity_choice]'][value='#{value}']")
      end
    end

    test "selecting the combined pharmacy + lab option sets both activities", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["pharmacy", "laboratory"])
      complete_regulatory_details_step(view, ["pharmacy", "laboratory"])
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
      complete_regulatory_details_step(view, ["pharmacy"])

      view |> complete_site_step(Map.merge(%{gln: @site_gln}, @unique_pharmacy_ppb))

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
      refute Repo.get_by(Organization, gs1_company_prefix: @gs1_prefix)

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

      complete_regulatory_details_step(view, ["pharmacy", "distributor"])

      assert has_element?(view, "#site-setup-form")
    end

    test "back preserves regulatory and operating-model data across steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/signup")

      view = complete_operating_model_step(view, ["laboratory", "distributor"])
      complete_regulatory_details_step(view, ["laboratory", "distributor"])

      view |> element("#main-location-back") |> render_click()

      assert has_element?(view, "p", "Verified · matches Test Licensee")

      view |> element("#regulatory-details-back") |> render_click()

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

  # Completes the operating-model step (step 1): ticks the given models and
  # submits, advancing straight to the regulatory-details step.
  defp complete_operating_model_step(view, models) do
    view
    |> form("#organization-setup-form", organization: %{operating_models: models})
    |> render_submit()

    view
  end

  # The real form carries `operating_models` forward via hidden inputs set in
  # step 1, so direct event submissions must include them explicitly too.
  defp submit_regulatory_details(view, attrs) do
    render_submit(view, "continue_regulatory_details", %{
      "organization" => stringify_keys(attrs)
    })
  end

  defp stringify_keys(attrs), do: Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

  # Completes the GS1-only regulatory-details step. The first submit starts
  # the registry lookup; the second carries the resolved organization name in
  # the form's hidden field and advances to site setup.
  defp complete_regulatory_details_step(view, models, attrs \\ %{}) do
    gs1_prefix = Map.get(attrs, :gs1_company_prefix, @gs1_prefix)

    submit_regulatory_details(view, %{operating_models: models, gs1_company_prefix: gs1_prefix})
    render_async(view, 5_000)

    full_attrs =
      attrs
      |> Map.put(:operating_models, models)
      |> Map.put_new(:gs1_company_prefix, gs1_prefix)

    view |> form("#regulatory-details-form", organization: full_attrs) |> render_submit()

    view
  end

  # Raw event dispatch rather than `form/3`, since some of these fields
  # (activity_choice, ppb_facility_name, license_number, kmlttb_*) don't
  # exist as actual inputs in the DOM until an earlier field (the GLN, the
  # activity choice) has already resolved — `form/3` can only set values on
  # inputs that are currently rendered.
  defp submit_site(view, attrs) do
    render_submit(view, "continue_site", %{"site" => stringify_keys(attrs)})
  end

  # Completes the main-location step of the wizard. Each of the GLN, PPB,
  # and KMLTTB checks is async and gated behind the previous one resolving
  # (PPB/KMLTTB fields aren't even rendered until the GLN matches), so
  # `continue_site` itself triggers the next pending check and flashes an
  # "press Continue again" error each time it's submitted with that check
  # still idle — this just keeps pressing it, once per check present in
  # `site`, until the step actually advances.
  defp complete_site_step(view, site) do
    gln_attrs = Map.take(site, [:gln])
    ppb_attrs = Map.take(site, [:ppb_facility_name, :license_number])
    kmlttb_attrs = Map.take(site, [:kmlttb_facility_name, :kmlttb_license_number])

    view |> form("#site-setup-form", site: gln_attrs) |> render_submit()

    if site[:gln] do
      render_async(view, 5_000)
      view |> form("#site-setup-form", site: gln_attrs) |> render_submit()
    end

    if ppb_attrs != %{} do
      full = Map.merge(gln_attrs, ppb_attrs)
      view |> form("#site-setup-form", site: full) |> render_submit()
      render_async(view, 5_000)
      view |> form("#site-setup-form", site: full) |> render_submit()
    end

    if kmlttb_attrs != %{} do
      full = gln_attrs |> Map.merge(ppb_attrs) |> Map.merge(kmlttb_attrs)
      view |> form("#site-setup-form", site: full) |> render_submit()
      render_async(view, 5_000)
      view |> form("#site-setup-form", site: full) |> render_submit()
    end

    view
  end
end
