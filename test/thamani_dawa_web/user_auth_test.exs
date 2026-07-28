defmodule ThamaniDawaWeb.UserAuthTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts
  alias ThamaniDawaWeb.UserAuth

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  defp live_socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, flash: %{}}}
  end

  describe "on_mount :mount_current_scope" do
    test "assigns current_scope, including organization_id, for a valid session token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      session = %{"user_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:mount_current_scope, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
      assert socket.assigns.current_scope.organization_id == user.organization_id
    end

    test "resolves the organization the user actually belongs to, not just any organization" do
      org_a = organization_fixture()
      org_b = organization_fixture()
      user = user_fixture(%{organization_id: org_a.id})
      token = Accounts.generate_user_session_token(user)

      assert {:cont, socket} =
               UserAuth.on_mount(
                 :mount_current_scope,
                 %{},
                 %{"user_token" => token},
                 live_socket()
               )

      assert socket.assigns.current_scope.organization_id == org_a.id
      refute socket.assigns.current_scope.organization_id == org_b.id
    end

    test "assigns a nil current_scope when there is no session token" do
      assert {:cont, socket} =
               UserAuth.on_mount(:mount_current_scope, %{}, %{}, live_socket())

      assert socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_authenticated" do
    test "continues when a user is present" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      session = %{"user_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_authenticated, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "halts and redirects when there is no user" do
      assert {:halt, socket} =
               UserAuth.on_mount(:require_authenticated, %{}, %{}, live_socket())

      assert socket.redirected
    end
  end

  describe "on_mount :require_admin" do
    test "continues when the current user is an admin" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      session = %{"user_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_admin, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "halts and redirects for a non-admin role" do
      staff = staff_fixture(%{role: :pharmacist})
      token = Accounts.generate_user_session_token(staff)
      session = %{"user_token" => token}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_admin, %{}, session, live_socket())

      assert socket.redirected
    end

    test "halts and redirects for combined pharmacy/lab staff" do
      staff = staff_fixture(%{role: :pharma_lab})
      token = Accounts.generate_user_session_token(staff)
      session = %{"user_token" => token}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_admin, %{}, session, live_socket())

      assert socket.redirected
    end

    test "halts and redirects when there is no user" do
      assert {:halt, socket} =
               UserAuth.on_mount(:require_admin, %{}, %{}, live_socket())

      assert socket.redirected
    end
  end

  describe "on_mount :require_pharmacy_access" do
    test "continues for an admin" do
      user = user_fixture()
      session = %{"user_token" => Accounts.generate_user_session_token(user)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "continues for a pharmacist" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, site_type: :pharmacy})
      staff = staff_fixture(%{role: :pharmacist, organization_id: org.id, site_id: site.id})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "continues for combined pharmacy/lab staff" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, site_type: :pharmacy_lab})
      staff = staff_fixture(%{role: :pharma_lab, organization_id: org.id, site_id: site.id})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "halts and redirects for a lab technician" do
      staff = staff_fixture(%{role: :lab_technician})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert socket.redirected
    end

    test "halts and redirects when there is no user" do
      assert {:halt, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, %{}, live_socket())

      assert socket.redirected
    end
  end

  describe "on_mount :require_lab_access" do
    test "continues for an admin" do
      user = user_fixture()
      session = %{"user_token" => Accounts.generate_user_session_token(user)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "continues for a lab technician" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, site_type: :lab})
      staff = staff_fixture(%{role: :lab_technician, organization_id: org.id, site_id: site.id})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "continues for combined pharmacy/lab staff" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id, site_type: :pharmacy_lab})
      staff = staff_fixture(%{role: :pharma_lab, organization_id: org.id, site_id: site.id})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "halts and redirects for a pharmacist" do
      staff = staff_fixture(%{role: :pharmacist})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.redirected
    end

    test "halts and redirects when there is no user" do
      assert {:halt, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, %{}, live_socket())

      assert socket.redirected
    end
  end

  describe "on_mount site-capability checks for combined pharmacy/lab staff" do
    test "denied :require_pharmacy_access at a lab-only site, redirected to /lab" do
      org = organization_fixture()
      lab_site = site_fixture(%{organization_id: org.id, site_type: :lab})
      staff = staff_fixture(%{role: :pharma_lab, organization_id: org.id, site_id: lab_site.id})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert {:redirect, %{to: "/lab"}} = socket.redirected
    end

    test "denied :require_lab_access at a pharmacy-only site, redirected to /pharmacy" do
      org = organization_fixture()
      pharmacy_site = site_fixture(%{organization_id: org.id, site_type: :pharmacy})

      staff =
        staff_fixture(%{role: :pharma_lab, organization_id: org.id, site_id: pharmacy_site.id})

      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert {:redirect, %{to: "/pharmacy"}} = socket.redirected
    end

    test "denied both portals at a warehouse-only site, redirected to /" do
      org = organization_fixture()
      warehouse_site = site_fixture(%{organization_id: org.id, site_type: :warehouse})

      staff =
        staff_fixture(%{role: :pharma_lab, organization_id: org.id, site_id: warehouse_site.id})

      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:halt, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert {:redirect, %{to: "/"}} = socket.redirected
    end

    test "with no current site (e.g. not yet assigned one), still passes on role alone — the page itself handles the missing site" do
      staff = staff_fixture(%{role: :pharma_lab})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "an admin passes :require_pharmacy_access regardless of current_site_id" do
      user = user_fixture()
      session = %{"user_token" => Accounts.generate_user_session_token(user)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
    end

    test "an admin passes :require_lab_access regardless of current_site_id" do
      user = user_fixture()
      session = %{"user_token" => Accounts.generate_user_session_token(user)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == user.id
    end
  end
end
