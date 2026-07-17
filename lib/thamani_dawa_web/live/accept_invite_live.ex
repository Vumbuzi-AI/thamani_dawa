defmodule ThamaniDawaWeb.AcceptInviteLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Organizations

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This invite link is invalid or has expired.")
         |> redirect(to: ~p"/login")}

      user ->
        organization = Organizations.get_organization!(user.organization_id)
        form = to_form(ThamaniDawa.Accounts.User.accept_invite_changeset(user, %{}), as: :user)
        {:ok, assign(socket, user: user, organization: organization, form: form)}
    end
  end

  def handle_event("save", %{"user" => attrs}, socket) do
    case Accounts.accept_invite(socket.assigns.user, attrs) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password set — log in below.")
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; display: flex; flex-direction: row;">
      <div
        class="hidden lg:flex"
        style="width: 46%; background: var(--thamani-forest); flex-direction: column; justify-content: space-between; padding: 48px 52px; position: relative; overflow: hidden;"
      >
        <div
          aria-hidden="true"
          style="position: absolute; top: -120px; right: -120px; width: 420px; height: 420px; border-radius: 50%; background: var(--thamani-lime); opacity: 0.08; pointer-events: none;"
        >
        </div>
        <div
          aria-hidden="true"
          style="position: absolute; bottom: -80px; left: -80px; width: 280px; height: 280px; border-radius: 50%; background: var(--thamani-lime); opacity: 0.06; pointer-events: none;"
        >
        </div>

        <.link
          navigate={~p"/"}
          style="font-size: 17px; font-weight: 500; color: var(--thamani-snow); text-decoration: none; letter-spacing: -0.01em; position: relative;"
        >
          Thamani Dawa
        </.link>

        <div style="position: relative;">
          <span
            class="thamani-badge"
            style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px; margin-bottom: 24px; display: inline-flex;"
          >
            You've been invited
          </span>
          <h2 style="font-size: clamp(28px, 2.8vw, 40px); font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-snow); text-wrap: balance; margin: 16px 0 20px;">
            Join {@organization.name} on Thamani Dawa.
          </h2>
          <p style="font-size: 16px; line-height: 1.65; color: rgba(252,252,247,0.55); max-width: 340px;">
            Set your password to activate your account as a {Phoenix.Naming.humanize(@user.role)} and get straight into stock, prescriptions, and lab orders.
          </p>
        </div>

        <div style="position: relative; border-top: 1px solid rgba(252,252,247,0.1); padding-top: 28px;">
          <p style="font-size: 13px; font-weight: 500; color: rgba(252,252,247,0.45);">
            Invited to {@organization.name}
          </p>
        </div>
      </div>

      <div style="flex: 1; background: var(--thamani-snow); display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 48px 24px;">
        <.link
          navigate={~p"/"}
          class="lg:hidden"
          style="font-size: 16px; font-weight: 500; color: var(--thamani-forest); text-decoration: none; letter-spacing: -0.01em; margin-bottom: 40px; align-self: flex-start;"
        >
          Thamani Dawa
        </.link>

        <div style="width: 100%; max-width: 380px;">
          <Layouts.flash_group flash={@flash} />

          <h1 style="font-size: 32px; font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-forest); margin-bottom: 8px;">
            Welcome, {@user.name}
          </h1>
          <p style="font-size: 15px; color: var(--thamani-pewter); line-height: 1.5; margin-bottom: 40px;">
            Set a password to activate your account.
          </p>

          <form phx-submit="save" id="accept-invite-form">
            <.thamani_input
              field={@form[:password]}
              type="password"
              label="Password"
              placeholder="••••••••"
              autocomplete="new-password"
              class="mb-8"
              required
            />

            <.thamani_btn id="accept-invite-submit" type="submit" variant="primary">
              Set password
            </.thamani_btn>
          </form>
        </div>

        <div
          class="lg:hidden"
          style="margin-top: 48px; display: flex; gap: 20px; align-items: center;"
        >
          <.link
            navigate={~p"/privacy"}
            style="font-size: 12px; color: var(--thamani-subtle); text-decoration: none;"
          >
            Privacy
          </.link>
          <span style="font-size: 12px; color: var(--thamani-stone);">·</span>
          <.link
            navigate={~p"/terms"}
            style="font-size: 12px; color: var(--thamani-subtle); text-decoration: none;"
          >
            Terms
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
