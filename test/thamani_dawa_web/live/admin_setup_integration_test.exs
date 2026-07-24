defmodule ThamaniDawaWeb.AdminSetupIntegrationTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.BatchesFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  test "admin configures a brand-new organization end to end: signup -> combined-capability site -> invite staff -> product -> initial stock",
       %{conn: conn} do
    admin_email = "admin-#{System.unique_integer([:positive])}@example.com"

    # Step 1: sign up the organization admin
    {:ok, signup_view, _html} = live(conn, ~p"/signup")

    assert {:error, {:live_redirect, %{to: login_path}}} =
             signup_view
             |> form("#signup-form",
               organization: %{name: "Acme Pharmacy Co", license_number: "PPB-ACME-001"},
               user: %{name: "Ada Admin", email: admin_email, password: "supersecret123"}
             )
             |> render_submit()

    assert login_path == ~p"/login"

    admin = Accounts.get_user_by_email(admin_email)
    assert admin.role == :admin

    organization = Organizations.get_organization!(admin.organization_id)
    assert organization.name == "Acme Pharmacy Co"

    admin_conn = log_in_user(conn, admin)

    # Step 2: create a combined-capability (pharmacy + lab) site
    {:ok, site_view, _html} = live(admin_conn, ~p"/org/sites/new")

    site_view
    |> form("#site-form",
      site: %{
        name: "Main Branch",
        site_type: :pharmacy_lab,
        gln: "0614141000005",
        address: "1 Test Street"
      }
    )
    |> render_submit()

    assert_patch(site_view, ~p"/org/sites")

    site = Enum.find(Sites.list_sites(organization.id), &(&1.name == "Main Branch"))
    assert site
    assert site.site_type == :pharmacy_lab

    # Step 3: invite staff to that site
    staff_email = "pharmacist-#{System.unique_integer([:positive])}@example.com"

    {:ok, team_view, _html} = live(admin_conn, ~p"/org/team/new")

    team_view
    |> form("#invite-form",
      user: %{
        name: "Peter Pharmacist",
        email: staff_email,
        role: :pharmacist,
        site_id: site.id
      }
    )
    |> render_submit()

    assert_patch(team_view, ~p"/org/team")

    staff = Accounts.get_user_by_email(staff_email)
    assert staff
    assert staff.role == :pharmacist
    assert staff.site_id == site.id
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
        uom: "tablet",
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

    # Step 5: dispatch initial stock to the new site
    {:ok, batch_view, _html} = live(admin_conn, ~p"/org/products/#{product.id}/batches/new")

    batch_view
    |> form("#batch-form",
      batch: %{
        site_id: site.id,
        gtin: gtin,
        batch_no: "LOT-INITIAL-1",
        expiry_date: Date.to_iso8601(Date.add(Date.utc_today(), 365)),
        quantity: 200,
        cost_per_unit: "50.00"
      }
    )
    |> render_submit()

    assert_patch(batch_view, ~p"/org/products/#{product.id}")

    assert [batch] = Batches.list_batches_for_product(organization.id, product.id)
    assert batch.site_id == site.id
    assert batch.batch_no == "LOT-INITIAL-1"
    assert batch.quantity == 200
    assert batch.remaining_quantity == 200
    assert is_nil(batch.approver_id)
  end
end
