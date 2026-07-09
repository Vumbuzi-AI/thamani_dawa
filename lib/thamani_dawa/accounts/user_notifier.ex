defmodule ThamaniDawa.Accounts.UserNotifier do
  @moduledoc "Delivers account-related emails (invites, password resets) via Swoosh."

  import Swoosh.Email

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Accounts.UserToken
  alias ThamaniDawa.Mailer

  defp deliver(recipient, subject, body) do
    config = Application.get_env(:thamani_dawa, __MODULE__)

    email =
      new()
      |> to(recipient)
      |> from({config[:sender_name], config[:sender_email]})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Delivers an invite email carrying the one-time invite link."
  def deliver_invite(%User{} = user, organization_name, invited_by_name, url) do
    organization_name = sanitize_header_value(organization_name)
    invited_by_name = sanitize_header_value(invited_by_name)

    deliver(user.email, "You've been invited to #{organization_name} on Thamani Dawa", """

    Hi #{user.name},

    #{invited_by_name} has invited you to join #{organization_name} on Thamani Dawa as a #{Phoenix.Naming.humanize(user.role)}.

    Set your password to get started:

    #{url}

    This link expires in #{UserToken.invite_validity_in_days()} days. If you didn't expect this invite, you can safely ignore this email.

    — The Thamani Dawa Team
    """)
  end

  defp sanitize_header_value(nil), do: ""

  defp sanitize_header_value(value) do
    value
    |> to_string()
    |> String.replace(~r/[\x00-\x1F\x7F]+/u, " ")
    |> String.trim()
  end
end
