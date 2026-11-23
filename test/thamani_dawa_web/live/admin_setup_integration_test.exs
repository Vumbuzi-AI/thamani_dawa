defmodule ThamaniDawaWeb.AdminSetupIntegrationTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.BatchesFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Products
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  test "admin configures a brand-new organization end to end: signup -> combined-capability site -> invite staff -> product -> initial stock",
       %{conn: conn} do
    admin_email = "admin-#{System.unique_integer([:positive])}@example.com"

    # Step 1: sign up the organization admin
    {:ok, signup_view, _html} = live(conn, ~p"/signup")

    # Step 1: operating models and organization name. GS1 company prefixes
    # are no longer collected at signup — they're added later from the
    # settings page. PPB/KMLTTB licensing is a property of a specific
    # premises, not the organization as a whole, so it lives on the site
    # step below.
    signup_view
    |> form("#organization-setup-form",
      organization: %{operating_models: ["pharmacy", "laboratory"], name: "Test Licensee"}
    )
    |> render_submit()

    # The main-location GLN is mandatory and checked against the registry
    # too, so it also needs a second Continue once the registry answers.
    signup_view
    |> form("#site-setup-form", site: %{gln: "0614141000784"})
    |> render_submit()

    render_async(signup_view, 5_000)

    signup_view
    |> form("#site-setup-form", site: %{gln: "0614141000784"})
    |> render_submit()

    # Both operating models were selected, so the default site activity is
    # already the combined "pharmacy + diagnostic lab" choice — no radio
    # selection needed, just the KMLTTB license. "Unique Lab"/"L 01000/26"
    # is recognized by the registry test stub as a unique match.
    site_attrs = %{
      gln: "0614141000784",
      kmlttb_facility_name: "Unique Lab",
      kmlttb_license_number: "L 01000/26"
    }

    signup_view
    |> form("#site-setup-form", site: site_attrs)
    |> render_submit()

    render_async(signup_view, 5_000)

    signup_view
    |> form("#site-setup-form", site: site_attrs)
    |> render_submit()

    render_async(signup_view, 5_000)

    signup_view
    |> form("#site-setup-form", site: site_attrs)
    |> render_submit()

    signup_view
    |> form("#signup-form",
      user: %{
        first_name: "Ada",
        last_name: "Admin",
        email: admin_email,
        password: "supersecret123",
        accepted_legal_terms: "true"
      }
    )
    |> render_submit()

    assert has_element?(signup_view, "#signup-form[phx-trigger-action][action='/login']")

    admin = Accounts.get_user_by_email(admin_email)
    assert admin.roles == [:admin, :pharmacist, :lab_technician]

    # Not under test here — this exercises everything *after* signup, so
    # skip straight past the email-confirmation gate rather than wiring up
    # the full token/email round trip.
    admin =
      admin
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

    organization = Organizations.get_organization!(admin.organization_id)
    assert organization.name == "Test Licensee"

    admin_conn = log_in_user(conn, admin)

    # Step 2: create a combined-capability (pharmacy + lab) site
    {:ok, site_view, _html} = live(admin_conn, ~p"/org/sites/new")

    site_view |> form("#site-form", site: %{gln: "0614141000128"}) |> render_submit()
    render_async(site_view, 5_000)

    site_view
    |> form("#site-form", site: %{gln: "0614141000128", activity_choice: "pharmacy_laboratory"})
    |> render_submit()

    assert_patch(site_view, ~p"/org/sites")

    site = Enum.find(Sites.list_sites(organization.id), &(&1.gln == "0614141000128"))
    assert site
    assert site.activities == [:pharmacy, :laboratory]
    # The GLN is the one GS1 issued to the location, resolved and verified
    # against the registry rather than hand-typed alongside the name.
    assert site.gln == "0614141000128"

    # Step 3: invite staff to that site
    staff_email = "pharmacist-#{System.unique_integer([:positive])}@example.com"

    {:ok, team_view, _html} = live(admin_conn, ~p"/org/team/new")

    team_view
    |> form("#invite-form",
      user: %{
        name: "Peter Pharmacist",
        email: staff_email,
        roles: ["pharmacist"],
        site_ids: [to_string(site.id)]
      }
    )
    |> render_submit()

    assert_patch(team_view, ~p"/org/team")

    staff = Accounts.get_user_by_email(staff_email)
    assert staff
    assert staff.roles == [:pharmacist]
    # Staff are assigned to one or more sites; `current_site_id` is the active one.
    assert staff.current_site_id == site.id
    assert Enum.map(Accounts.get_user!(organization.id, staff.id).sites, & &1.id) == [site.id]
    assert is_nil(staff.hashed_password)

    # Step 4: add a product to the (org-wide) catalog
    gtin = unique_gtin()

    {:ok, product_view, _html} = live(admin_conn, ~p"/org/products/new")

    product_view
    |> form("#gtin-scan-form", gtin_search: "")
    |> render_submit()

    product_view
    |> form("#product-form",
      product: %{
        generic_name: "Paracetamol",
        brand_name: "Panadol",
        category: "Analgesic",
        uom: "U2",
        gtin: gtin,
        price: 100,
        reorder_level: 20
      }
    )
    |> render_submit()

    assert_patch(product_view, ~p"/org/products")

    product = Enum.find(Products.list_products(organization.id), &(&1.gtin == gtin))
    assert product
    assert product.generic_name == "Paracetamol"

    # Step 5: record initial stock as org-level, then dispatch it to the new site
    {:ok, batch_view, _html} = live(admin_conn, ~p"/org/products/#{product.id}/batches/new")

    batch_view
    |> form("#batch-form",
      batch: %{
        gtin: gtin,
        batch_no: "LOT-INITIAL-1",
        expiry_date: Date.to_iso8601(Date.add(Date.utc_today(), 365)),
        quantity: 200,
        cost_per_unit: "50.00"
      }
    )
    |> render_submit()

    assert_patch(batch_view, ~p"/org/products/#{product.id}")

    assert [org_batch] =
             Batches.list_undispatched_batches_for_product(organization.id, product.id)

    assert is_nil(org_batch.site_id)
    assert org_batch.batch_no == "LOT-INITIAL-1"

    {:ok, dispatch_view, _html} =
      live(admin_conn, ~p"/org/products/#{product.id}/batches/#{org_batch.id}/dispatch")

    dispatch_view
    |> form("#dispatch-batch-form", dispatch: %{site_id: site.id})
    |> render_submit()

    assert_patch(dispatch_view, ~p"/org/products/#{product.id}")

    assert [batch] = Batches.list_batches_for_product(organization.id, product.id)
    assert batch.site_id == site.id
    assert batch.source_batch_id == org_batch.id
    assert batch.batch_no == "LOT-INITIAL-1"
    assert batch.quantity == 200
    assert batch.remaining_quantity == 200
    assert is_nil(batch.approver_id)
  end
end
