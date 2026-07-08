defmodule ThamaniDawa.Accounts.UserNotifier do
  @moduledoc "Delivers account-related emails (invites, password resets) via Swoosh."

  import Swoosh.Email

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Accounts.UserToken
  alias ThamaniDawa.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Thamani Dawa", "noreply@thamanidawa.example"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Delivers an invite email carrying the one-time invite link."
  def deliver_invite(%User{} = user, organization_name, invited_by_name, url) do
    deliver(user.email, "You've been invited to #{organization_name} on Thamani Dawa", """

    Hi #{user.name},

    #{invited_by_name} has invited you to join #{organization_name} on Thamani Dawa as a #{Phoenix.Naming.humanize(user.role)}.

    Set your password to get started:

    #{url}

    This link expires in #{UserToken.invite_validity_in_days()} days. If you didn't expect this invite, you can safely ignore this email.

    — The Thamani Dawa Team
    """)
  end
end
