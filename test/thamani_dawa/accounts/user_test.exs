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
      assert "Must be at least 6 characters" in errors_on(changeset).password
    end
  end

  test "registration_changeset/2 accepts and hashes a six-character password" do
    changeset =
      User.registration_changeset(%User{}, %{
        name: "Jane",
        email: "jane@example.com",
        password: "secret"
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :password) == nil
    assert Ecto.Changeset.get_change(changeset, :hashed_password) != nil
  end

  test "registration_changeset/2 trims name and email but preserves password whitespace" do
    changeset =
      User.registration_changeset(%User{}, %{
        name: "  Jane Admin  ",
        email: "  jane@example.com  ",
        password: " secret "
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :name) == "Jane Admin"
    assert Ecto.Changeset.get_field(changeset, :email) == "jane@example.com"

    assert User.valid_password?(
             %User{hashed_password: Ecto.Changeset.get_change(changeset, :hashed_password)},
             " secret "
           )
  end

  test "required legal consent records its timestamp and policy version" do
    changeset =
      User.registration_changeset(
        %User{},
        %{
          name: "Jane",
          email: "jane@example.com",
          password: "secret",
          accepted_legal_terms: true
        },
        require_legal_consent: true
      )

    assert changeset.valid?
    assert %DateTime{} = Ecto.Changeset.get_change(changeset, :legal_terms_accepted_at)
    assert Ecto.Changeset.get_change(changeset, :legal_policy_version) == "2026-10-29"
  end

  test "required legal consent rejects an unchecked value" do
    changeset =
      User.registration_changeset(
        %User{},
        %{name: "Jane", email: "jane@example.com", password: "secret"},
        require_legal_consent: true
      )

    refute changeset.valid?

    assert "You must accept the Terms of Service and Privacy Policy" in errors_on(changeset).accepted_legal_terms
  end
end
