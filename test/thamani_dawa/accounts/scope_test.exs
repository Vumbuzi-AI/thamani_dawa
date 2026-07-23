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

  test "pharma_lab?/1 reflects the combined role without granting admin" do
    pharma_lab = staff_fixture(%{role: :pharma_lab})
    scope = Scope.for_user(pharma_lab)

    assert Scope.pharma_lab?(scope)
    refute Scope.admin?(scope)
    refute Scope.pharmacist?(scope)
    refute Scope.lab_technician?(scope)
  end

  test "pharmacy_access?/1 and lab_access?/1 cover each capable role" do
    admin = Scope.for_user(user_fixture())
    pharmacist = Scope.for_user(staff_fixture(%{role: :pharmacist}))
    lab_technician = Scope.for_user(staff_fixture(%{role: :lab_technician}))
    pharma_lab = Scope.for_user(staff_fixture(%{role: :pharma_lab}))

    assert Scope.pharmacy_access?(admin)
    assert Scope.pharmacy_access?(pharmacist)
    assert Scope.pharmacy_access?(pharma_lab)
    refute Scope.pharmacy_access?(lab_technician)

    assert Scope.lab_access?(admin)
    assert Scope.lab_access?(lab_technician)
    assert Scope.lab_access?(pharma_lab)
    refute Scope.lab_access?(pharmacist)
  end

  test "role predicates are false for a nil scope" do
    refute Scope.admin?(nil)
    refute Scope.pharmacist?(nil)
    refute Scope.lab_technician?(nil)
    refute Scope.pharma_lab?(nil)
    refute Scope.pharmacy_access?(nil)
    refute Scope.lab_access?(nil)
  end
end
