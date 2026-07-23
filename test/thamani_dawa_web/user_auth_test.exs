defmodule ThamaniDawaWeb.UserAuthTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts
  alias ThamaniDawaWeb.UserAuth

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

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
      staff = staff_fixture(%{role: :pharmacist})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_pharmacy_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "continues for combined pharmacy/lab staff" do
      staff = staff_fixture(%{role: :pharma_lab})
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
      staff = staff_fixture(%{role: :lab_technician})
      session = %{"user_token" => Accounts.generate_user_session_token(staff)}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_lab_access, %{}, session, live_socket())

      assert socket.assigns.current_scope.user.id == staff.id
    end

    test "continues for combined pharmacy/lab staff" do
      staff = staff_fixture(%{role: :pharma_lab})
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
end
