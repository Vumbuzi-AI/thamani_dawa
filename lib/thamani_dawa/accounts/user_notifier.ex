defmodule ThamaniDawa.Accounts.UserNotifier do
  @moduledoc "Delivers account-related emails (invites, password resets) via Swoosh."

  import Swoosh.Email

  alias ThamaniDawa.Accounts.User
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
  def deliver_invite(%User{} = user, url) do
    deliver(user.email, "You've been invited to Thamani Dawa", """

    Hi #{user.name},

    You've been invited to join your organization's Thamani Dawa account.
    Set your password by visiting the URL below:

    #{url}

    If you didn't expect this invite, you can safely ignore this email.
    """)
  end
end
