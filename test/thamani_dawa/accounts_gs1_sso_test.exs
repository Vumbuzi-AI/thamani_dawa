defmodule ThamaniDawa.AccountsGs1SsoTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Repo

  test "links once by normalized email and subsequently resolves by sub" do
    user = user_fixture()

    assert {:ok, linked} = Accounts.link_gs1_sso_user("subject-1", String.upcase(user.email))
    assert linked.id == user.id
    assert Repo.reload!(user).gs1_sso_sub == "subject-1"

    assert {:ok, same_user} =
             Accounts.link_gs1_sso_user("subject-1", "provider-email-changed@example.com")

    assert same_user.id == user.id
  end

  test "does not relink a local account to a different subject" do
    user = user_fixture()
    assert {:ok, _user} = Accounts.link_gs1_sso_user("subject-1", user.email)

    assert {:error, :identity_already_linked} =
             Accounts.link_gs1_sso_user("subject-2", user.email)
  end

  test "does not provision unknown or inactive accounts" do
    assert {:error, :account_not_found} =
             Accounts.link_gs1_sso_user("unknown", "nobody@example.com")

    user = user_fixture()
    user |> Ecto.Changeset.change(is_active: false) |> Repo.update!()

    assert {:error, :inactive_account} = Accounts.link_gs1_sso_user("inactive", user.email)
  end
end
