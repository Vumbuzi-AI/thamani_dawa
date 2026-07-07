defmodule ThamaniDawa.Accounts.ScopeTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts.Scope

  import ThamaniDawa.AccountsFixtures

  test "admin?/1 and pharmacist?/1 reflect the user's role" do
    admin = user_fixture()
    pharmacist = staff_fixture(%{role: :pharmacist})

    assert Scope.admin?(Scope.for_user(admin))
    refute Scope.pharmacist?(Scope.for_user(admin))

    assert Scope.pharmacist?(Scope.for_user(pharmacist))
    refute Scope.admin?(Scope.for_user(pharmacist))
  end

  test "admin?/1 is false for a deactivated admin" do
    admin = user_fixture()
    {:ok, deactivated} = admin |> change(is_active: false) |> Repo.update()

    refute Scope.admin?(Scope.for_user(deactivated))
  end

  test "lab_technician?/1 reflects the user's role" do
    lab_technician = staff_fixture(%{role: :lab_technician})

    assert Scope.lab_technician?(Scope.for_user(lab_technician))
    refute Scope.admin?(Scope.for_user(lab_technician))
  end

  test "role predicates are false for a nil scope" do
    refute Scope.admin?(nil)
    refute Scope.pharmacist?(nil)
    refute Scope.lab_technician?(nil)
  end
end
