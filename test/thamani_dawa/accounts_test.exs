defmodule ThamaniDawa.AccountsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Accounts.UserToken

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  describe "register_user/2" do
    test "registers an admin user scoped to the given organization" do
      organization = organization_fixture()
      email = valid_user_email()

      assert {:ok, %User{} = user} =
               Accounts.register_user(organization.id, valid_user_attributes(%{email: email}))

      assert user.organization_id == organization.id
      assert user.email == email
      assert user.role == :admin
      assert is_binary(user.hashed_password)
    end

    test "requires name, email, and password" do
      organization = organization_fixture()
      assert {:error, changeset} = Accounts.register_user(organization.id, %{})

      assert %{
               name: ["Please enter your name"],
               email: ["Please enter your email"],
               password: ["Please choose a password"]
             } =
               errors_on(changeset)
    end

    test "enforces globally unique email even across different organizations" do
      email = valid_user_email()
      user_fixture(%{email: email})

      other_organization = organization_fixture()

      assert {:error, changeset} =
               Accounts.register_user(
                 other_organization.id,
                 valid_user_attributes(%{email: email})
               )

      assert %{email: ["This email is already registered"]} = errors_on(changeset)
    end
  end

  describe "invite_user/3" do
    test "creates an unconfirmed user with no password, tied to the inviting organization" do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id})

      assert {:ok, user, encoded_token} =
               Accounts.invite_user(organization.id, admin.id, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist
               })

      assert user.organization_id == organization.id
      assert user.invited_by_id == admin.id
      assert user.role == :pharmacist
      assert is_nil(user.hashed_password)
      assert is_binary(encoded_token)
    end

    test "accepts a home site that belongs to the same organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, user, _encoded_token} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist,
                 site_ids: [site.id]
               })

      user = Repo.preload(user, :sites)
      assert Enum.map(user.sites, & &1.id) == [site.id]
      assert user.current_site_id == site.id
    end

    test "accepts multiple home sites that belong to the same organization" do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})

      assert {:ok, user, _encoded_token} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist,
                 site_ids: [site_a.id, site_b.id]
               })

      user = Repo.preload(user, :sites)
      assert user.sites |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([site_a.id, site_b.id])
      assert user.current_site_id in [site_a.id, site_b.id]
    end

    test "rejects a home site that belongs to a different organization" do
      organization = organization_fixture()
      other_org_site = site_fixture()

      assert {:error, changeset} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist,
                 site_ids: [other_org_site.id]
               })

      assert %{sites: ["must belong to the same organization"]} = errors_on(changeset)
    end

    test "rejects a site_id that does not exist at all" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist,
                 site_ids: [999_999]
               })

      assert %{sites: ["must belong to the same organization"]} = errors_on(changeset)
    end

    test "requires a role" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email()
               })

      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects a role outside the known roles" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: "owner"
               })

      assert %{role: ["is invalid"]} = errors_on(changeset)
    end

    for role <- [:admin, :pharmacist, :lab_technician, :pharma_lab] do
      test "accepts the #{role} role" do
        organization = organization_fixture()

        assert {:ok, user, _encoded_token} =
                 Accounts.invite_user(organization.id, nil, %{
                   name: "New Hire",
                   email: valid_user_email(),
                   role: unquote(role)
                 })

        assert user.role == unquote(role)
      end
    end

    test "persists an invite token tied to the invited user" do
      organization = organization_fixture()

      assert {:ok, user, encoded_token} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist
               })

      assert {:ok, hashed_token} = UserToken.verify_email_token_query(encoded_token, "invite")
      assert %User{id: id} = Repo.one(hashed_token)
      assert id == user.id

      assert Repo.exists?(
               from t in UserToken, where: t.user_id == ^user.id and t.context == "invite"
             )
    end
  end

  describe "update_user/3" do
    test "sets current_site_id when a user invited without a site is later assigned one" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, user, _encoded_token} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist
               })

      assert user.current_site_id == nil

      assert {:ok, updated} =
               Accounts.update_user(organization.id, user.id, %{
                 role: :pharmacist,
                 site_ids: [site.id]
               })

      assert updated.current_site_id == site.id
    end

    test "leaves current_site_id alone when it's still among the assigned sites" do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})

      assert {:ok, user, _encoded_token} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist,
                 site_ids: [site_a.id, site_b.id]
               })

      assert {:ok, updated} =
               Accounts.update_user(organization.id, user.id, %{
                 role: :pharmacist,
                 site_ids: [site_a.id, site_b.id]
               })

      assert updated.current_site_id == user.current_site_id
    end

    test "resets current_site_id to the first remaining site when it's removed from the assignment" do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})

      assert {:ok, user, _encoded_token} =
               Accounts.invite_user(organization.id, nil, %{
                 name: "New Hire",
                 email: valid_user_email(),
                 role: :pharmacist,
                 site_ids: [site_a.id]
               })

      assert user.current_site_id == site_a.id

      assert {:ok, updated} =
               Accounts.update_user(organization.id, user.id, %{
                 role: :pharmacist,
                 site_ids: [site_b.id]
               })

      assert updated.current_site_id == site_b.id
    end
  end

  describe "deliver_user_invite/5" do
    test "builds the invite URL from the encoded token and delivers the email" do
      organization = organization_fixture()
      admin = user_fixture(%{organization_id: organization.id, name: "Jane Admin"})

      {:ok, user, encoded_token} =
        Accounts.invite_user(organization.id, admin.id, %{
          name: "New Hire",
          email: valid_user_email(),
          role: :pharmacist
        })

      assert {:ok, email} =
               Accounts.deliver_user_invite(
                 user,
                 organization.name,
                 admin.name,
                 encoded_token,
                 fn token -> "http://localhost:4000/invites/#{token}" end
               )

      assert email.subject == "You've been invited to #{organization.name} on Thamani Dawa"
      assert email.text_body =~ "http://localhost:4000/invites/#{encoded_token}"
      assert email.text_body =~ "Jane Admin has invited you"
    end
  end

  describe "get_user_by_invite_token/1 and accept_invite/2" do
    test "resolves the invited user for a valid token, and lets them set a password" do
      organization = organization_fixture()

      {:ok, invited, encoded_token} =
        Accounts.invite_user(organization.id, nil, %{
          name: "New Hire",
          email: valid_user_email(),
          role: :pharmacist
        })

      assert %User{id: id} = Accounts.get_user_by_invite_token(encoded_token)
      assert id == invited.id

      assert {:ok, accepted} =
               Accounts.accept_invite(invited, %{
                 password: valid_user_password(),
                 accepted_legal_terms: true
               })

      assert is_binary(accepted.hashed_password)
    end

    test "returns nil for a reused token, once it's already been accepted" do
      organization = organization_fixture()

      {:ok, invited, encoded_token} =
        Accounts.invite_user(organization.id, nil, %{
          name: "New Hire",
          email: valid_user_email(),
          role: :pharmacist
        })

      assert {:ok, _accepted} =
               Accounts.accept_invite(invited, %{
                 password: valid_user_password(),
                 accepted_legal_terms: true
               })

      refute Accounts.get_user_by_invite_token(encoded_token)
    end

    test "returns nil for an expired token" do
      organization = organization_fixture()

      {:ok, invited, encoded_token} =
        Accounts.invite_user(organization.id, nil, %{
          name: "New Hire",
          email: valid_user_email(),
          role: :pharmacist
        })

      invited
      |> UserToken.by_user_and_context_query("invite")
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)])

      refute Accounts.get_user_by_invite_token(encoded_token)
    end

    test "returns nil for a bogus token" do
      refute Accounts.get_user_by_invite_token("bogus")
    end
  end

  describe "PIN (secondary auth)" do
    test "set_user_pin/2 hashes a valid 4-digit pin and valid_pin?/2 verifies it" do
      user = user_fixture()

      assert {:ok, user} = Accounts.set_user_pin(user, %{pin: "1234"})
      assert is_binary(user.hashed_pin)
      assert Accounts.valid_pin?(user, "1234")
      refute Accounts.valid_pin?(user, "0000")
    end

    test "set_user_pin/2 rejects a non-4-digit pin" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.set_user_pin(user, %{pin: "12"})
      assert %{pin: ["must be exactly 4 digits"]} = errors_on(changeset)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user when credentials are valid" do
      email = valid_user_email()
      password = valid_user_password()
      %{id: id} = user_fixture(%{email: email, password: password})

      assert %User{id: ^id} = Accounts.get_user_by_email_and_password(email, password)
    end

    test "returns nil for an invalid password" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong password")
    end

    test "returns nil for an unknown email" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "whatever123")
    end

    test "returns nil for a deactivated user, even with the correct password" do
      email = valid_user_email()
      password = valid_user_password()
      user = user_fixture(%{email: email, password: password})
      {:ok, _deactivated} = user |> change(is_active: false) |> Repo.update()

      refute Accounts.get_user_by_email_and_password(email, password)
    end
  end

  describe "set_user_active/4" do
    test "deactivates and reactivates another organization user" do
      admin = user_fixture()

      staff =
        staff_fixture(%{organization_id: admin.organization_id, invited_by_id: admin.id})

      assert {:ok, %User{is_active: false}} =
               Accounts.set_user_active(admin.organization_id, admin.id, staff.id, false)

      assert {:ok, %User{is_active: true}} =
               Accounts.set_user_active(admin.organization_id, admin.id, staff.id, true)
    end

    test "does not allow an administrator to deactivate themselves" do
      admin = user_fixture()

      assert {:error, :cannot_deactivate_self} =
               Accounts.set_user_active(admin.organization_id, admin.id, admin.id, false)
    end

    test "a deactivated administrator cannot change account access" do
      acting_admin = user_fixture()
      other_admin = user_fixture(%{organization_id: acting_admin.organization_id})

      assert {:ok, %User{is_active: false}} =
               Accounts.set_user_active(
                 acting_admin.organization_id,
                 acting_admin.id,
                 other_admin.id,
                 false
               )

      assert {:error, :unauthorized} =
               Accounts.set_user_active(
                 acting_admin.organization_id,
                 other_admin.id,
                 acting_admin.id,
                 false
               )
    end
  end

  describe "sessions" do
    test "generate_user_session_token/1 and get_user_by_session_token/1 round-trip" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert %User{id: id} = Accounts.get_user_by_session_token(token)
      assert id == user.id
    end

    test "get_user_by_session_token/1 returns nil for a bogus token" do
      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end

    test "get_user_by_session_token/1 returns nil once the user is deactivated" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.get_user_by_session_token(token)

      {:ok, _deactivated} = user |> change(is_active: false) |> Repo.update()

      refute Accounts.get_user_by_session_token(token)
    end

    test "delete_user_session_token/1 invalidates the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "list_sites_for_user" do
    test "returns assigned sites for staff with a single site" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      staff = staff_fixture(%{organization_id: org.id, site_id: site.id})

      assert [%{id: id}] = Accounts.list_sites_for_user(staff)
      assert id == site.id

      scope = ThamaniDawa.Accounts.Scope.for_user(staff)
      assert [%{id: ^id}] = Accounts.list_sites_for_user(scope)
      assert [%{id: ^id}] = Accounts.list_sites_for_user(org.id, staff.id)
    end

    test "returns only assigned sites for staff with multiple sites" do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id})
      site_b = site_fixture(%{organization_id: org.id})
      _other_site = site_fixture(%{organization_id: org.id})
      staff = staff_fixture(%{organization_id: org.id, site_ids: [site_a.id, site_b.id]})

      sites = Accounts.list_sites_for_user(staff)
      site_ids = Enum.map(sites, & &1.id)

      assert length(sites) == 2
      assert site_a.id in site_ids
      assert site_b.id in site_ids
    end

    test "returns all organization sites for an admin" do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id})
      site_b = site_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})

      sites = Accounts.list_sites_for_user(admin)
      site_ids = Enum.map(sites, & &1.id)

      assert length(sites) == 2
      assert site_a.id in site_ids
      assert site_b.id in site_ids

      scope = ThamaniDawa.Accounts.Scope.for_user(admin)
      assert length(Accounts.list_sites_for_user(scope)) == 2
    end
  end
end
