defmodule ThamaniDawa.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Accounts`.
  """

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.OrganizationsFixtures

  def valid_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"
  def valid_user_name, do: "Test User #{System.unique_integer()}"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: valid_user_name(),
      email: valid_user_email(),
      password: valid_user_password()
    })
  end

  @doc "Creates an admin user under a fresh organization unless `organization_id` is given."
  def user_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> then(&Accounts.register_user(organization_id, &1))

    user
  end

  @doc """
  Creates a staff user via the invite/accept-invite flow, defaulting to the
  `pharmacist` role. Pass `role:`, `organization_id:`, `invited_by_id:`, or
  `site_id:` to override.
  """
  def staff_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {invited_by_id, attrs} = Map.pop(attrs, :invited_by_id, nil)

    invite_attrs =
      Enum.into(attrs, %{name: valid_user_name(), email: valid_user_email(), role: :pharmacist})

    {:ok, invited, _encoded_token} =
      Accounts.invite_user(organization_id, invited_by_id, invite_attrs)

    {:ok, user} = Accounts.accept_invite(invited, %{password: valid_user_password()})
    user
  end
end
