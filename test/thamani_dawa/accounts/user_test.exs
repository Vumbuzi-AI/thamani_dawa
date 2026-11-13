defmodule ThamaniDawa.Accounts.UserTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Accounts.User

  test "accepts an eight-character password" do
    changeset =
      User.registration_changeset(%User{}, valid_user_attributes(%{password: "password"}))

    assert changeset.valid?
  end

  test "rejects passwords shorter than eight characters" do
    changeset =
      User.registration_changeset(%User{}, valid_user_attributes(%{password: "1234567"}))

    assert %{password: ["Must be at least 8 characters"]} = errors_on(changeset)
  end
end
