defmodule ThamaniDawa.Accounts.UserNotifierTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Accounts.UserNotifier
  alias ThamaniDawa.Accounts.UserToken

  import ThamaniDawa.AccountsFixtures

  describe "deliver_invite/4" do
    test "names the organization, inviter, and role, and states the link expiry" do
      user = staff_fixture(%{name: "New Hire", role: :pharmacist})

      assert {:ok, email} =
               UserNotifier.deliver_invite(
                 user,
                 "Acme Pharmacy",
                 "Jane Admin",
                 "http://localhost:4000/invites/abc123"
               )

      assert email.subject == "You've been invited to Acme Pharmacy on Thamani Dawa"
      assert email.text_body =~ "Hi New Hire,"
      assert email.text_body =~ "Jane Admin has invited you to join Acme Pharmacy"
      assert email.text_body =~ "as a Pharmacist"
      assert email.text_body =~ "http://localhost:4000/invites/abc123"
      assert email.text_body =~ "expires in #{UserToken.invite_validity_in_days()} days"
    end

    test "strips control characters from organization/inviter names so a crafted value can't inject extra email headers or lines" do
      user = staff_fixture(%{name: "New Hire", role: :pharmacist})

      assert {:ok, email} =
               UserNotifier.deliver_invite(
                 user,
                 "Acme\r\nBcc: attacker@evil.com",
                 "Jane\r\nAdmin",
                 "http://localhost:4000/invites/abc123"
               )

      refute email.subject =~ "\r"
      refute email.subject =~ "\n"
      assert email.subject == "You've been invited to Acme Bcc: attacker@evil.com on Thamani Dawa"

      refute email.text_body =~ "\r"
      assert email.text_body =~ "Jane Admin has invited you to join Acme Bcc: attacker@evil.com"
    end

    test "coerces nil organization/inviter names to blank instead of the literal word \"nil\"" do
      user = staff_fixture(%{name: "New Hire", role: :pharmacist})

      assert {:ok, email} =
               UserNotifier.deliver_invite(
                 user,
                 nil,
                 nil,
                 "http://localhost:4000/invites/abc123"
               )

      refute email.subject =~ "nil"
      refute email.text_body =~ "nil"
      assert email.subject == "You've been invited to  on Thamani Dawa"
    end
  end

  describe "deliver_mobile_pin/3" do
    test "uses an organization-neutral footer note" do
      mobile_user = %ThamaniDawa.Distributor.MobileUser{
        name: "Sample User",
        username: "sample-user",
        email: "sample@example.com"
      }

      assert {:ok, email} =
               UserNotifier.deliver_mobile_pin(mobile_user, "Acme Manufacturing", "1234")

      assert email.html_body =~ "contact your organization administrator"
      refute email.html_body =~ "distributor administrator"
    end

    test "uses the public platform domain for the logo image" do
      mobile_user = %ThamaniDawa.Distributor.MobileUser{
        name: "Sample User",
        username: "sample-user",
        email: "sample@example.com"
      }

      assert {:ok, email} =
               UserNotifier.deliver_mobile_pin(mobile_user, "Acme Manufacturing", "1234")

      assert email.html_body =~ ~s(src="https://thamanidawa.com/images/logo.png")
      refute email.html_body =~ "localhost"
    end
  end

  describe "email branding" do
    test "every email type includes the Thamani Dawa logo header" do
      user = staff_fixture()

      mobile_user = %ThamaniDawa.Distributor.MobileUser{
        name: "Sample User",
        username: "sample-user",
        email: "sample@example.com"
      }

      emails = [
        UserNotifier.deliver_invite(user, "Acme Pharmacy", "Jane Admin", "http://example.com/i"),
        UserNotifier.deliver_confirmation_instructions(user, "http://example.com/c"),
        UserNotifier.deliver_password_reset(user, "http://example.com/p"),
        UserNotifier.deliver_mobile_pin(mobile_user, "Acme Pharmacy", "1234"),
        UserNotifier.deliver_recall_notice(user, "1234567890123", "BATCH-1", "INC-1")
      ]

      for {:ok, email} <- emails do
        assert email.html_body =~ ~s(alt="Thamani Dawa")
        assert email.html_body =~ ~s(src="https://thamanidawa.com/images/logo.png")
        refute email.html_body =~ "localhost"
      end
    end
  end
end
