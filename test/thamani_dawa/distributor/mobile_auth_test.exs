defmodule ThamaniDawa.Distributor.MobileAuthTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{MobileAuth, MobileUser}

  setup do
    organization = distributor_organization_fixture()

    mobile_user =
      organization.id
      |> mobile_user_fixture()
      |> MobileUser.pin_changeset("4321")
      |> Repo.update!()

    %{organization: organization, mobile_user: mobile_user}
  end

  test "signs in with username and PIN and authenticates the access token", %{mobile_user: mu} do
    assert {:ok, tokens} = MobileAuth.login(String.upcase(mu.username), "4321")
    assert {:ok, authenticated} = MobileAuth.authenticate(tokens.access_token)
    assert authenticated.id == mu.id
  end

  test "an unknown username and a wrong PIN are both invalid credentials", %{mobile_user: mu} do
    assert {:error, :invalid_credentials} = MobileAuth.login("nobody", "4321")
    assert {:error, :invalid_credentials} = MobileAuth.login(mu.username, "0000")
  end

  test "five wrong PINs lock the account", %{mobile_user: mu} do
    for _ <- 1..5, do: MobileAuth.login(mu.username, "0000")
    assert {:error, :locked} = MobileAuth.login(mu.username, "4321")
  end

  test "refresh rotates both tokens", %{mobile_user: mu} do
    {:ok, tokens} = MobileAuth.login(mu.username, "4321")

    assert {:ok, rotated} = MobileAuth.refresh(tokens.refresh_token)
    assert {:error, :invalid_token} = MobileAuth.authenticate(tokens.access_token)
    assert {:error, :invalid_token} = MobileAuth.refresh(tokens.refresh_token)
    assert {:ok, _} = MobileAuth.authenticate(rotated.access_token)
  end

  test "deactivating the user revokes sessions", %{mobile_user: mu} do
    {:ok, tokens} = MobileAuth.login(mu.username, "4321")
    {:ok, _} = Distributor.set_mobile_user_active(mu, false)

    assert {:error, :invalid_token} = MobileAuth.authenticate(tokens.access_token)
    assert {:error, :inactive} = MobileAuth.login(mu.username, "4321")
  end

  test "leaving the distributor model locks mobile users out", %{
    organization: organization,
    mobile_user: mu
  } do
    {:ok, tokens} = MobileAuth.login(mu.username, "4321")

    organization
    |> Ecto.Changeset.change(operating_models: [:pharmacy])
    |> Repo.update!()

    assert {:error, :invalid_token} = MobileAuth.authenticate(tokens.access_token)
  end
end
