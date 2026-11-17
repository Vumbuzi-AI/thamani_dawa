defmodule ThamaniDawa.DistributorMobileUserPhoneTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures,
    only: [distributor_organization_fixture: 0, mobile_user_fixture: 1]

  alias ThamaniDawa.Distributor

  describe "mobile user phone validation" do
    for phone <- ["12345678", "+1 212 555 0100", "+44 (0)20-1234-5678"] do
      test "accepts #{phone}" do
        changeset =
          Distributor.change_mobile_user(%ThamaniDawa.Distributor.MobileUser{}, %{
            name: "Packer",
            username: "packer",
            email: "packer@example.com",
            phone: unquote(phone)
          })

        assert changeset.valid?
      end
    end

    test "rejects alphabetic characters" do
      changeset =
        Distributor.change_mobile_user(%ThamaniDawa.Distributor.MobileUser{}, %{
          name: "Packer",
          username: "packer",
          email: "packer@example.com",
          phone: "12345678n"
        })

      assert "Enter a phone number using digits, spaces, hyphens, parentheses, and an optional leading +" in errors_on(
               changeset
             ).phone
    end

    test "keeps phone optional" do
      changeset =
        Distributor.change_mobile_user(%ThamaniDawa.Distributor.MobileUser{}, %{
          name: "Packer",
          username: "packer",
          email: "packer@example.com",
          phone: ""
        })

      assert changeset.valid?
    end

    test "update operation rejects invalid phone values" do
      organization = distributor_organization_fixture()
      mobile_user = mobile_user_fixture(organization.id)

      assert {:error, changeset} =
               Distributor.update_mobile_user(mobile_user, %{phone: "abc123"})

      assert "Enter a phone number using digits, spaces, hyphens, parentheses, and an optional leading +" in errors_on(
               changeset
             ).phone
    end
  end
end
