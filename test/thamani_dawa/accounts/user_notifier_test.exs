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
  end
end
