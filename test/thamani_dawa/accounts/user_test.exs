defmodule ThamaniDawa.Accounts.UserTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts.User

  describe "registration_changeset/3 with hash_password: false" do
    test "leaves the password unhashed, for cheap live validation" do
      changeset =
        User.registration_changeset(
          %User{},
          %{name: "Jane", email: "jane@example.com", password: "hello world!"},
          hash_password: false
        )

      assert Ecto.Changeset.get_change(changeset, :password) == "hello world!"
      assert Ecto.Changeset.get_change(changeset, :hashed_password) == nil
    end

    test "still surfaces password validation errors" do
      changeset =
        User.registration_changeset(
          %User{},
          %{name: "Jane", email: "jane@example.com", password: "short"},
          hash_password: false
        )

      refute changeset.valid?
      assert "Must be at least 8 characters" in errors_on(changeset).password
    end
  end

  test "registration_changeset/2 hashes the password by default" do
    changeset =
      User.registration_changeset(%User{}, %{
        name: "Jane",
        email: "jane@example.com",
        password: "hello world!"
      })

    assert Ecto.Changeset.get_change(changeset, :password) == nil
    assert Ecto.Changeset.get_change(changeset, :hashed_password) != nil
  end
end
