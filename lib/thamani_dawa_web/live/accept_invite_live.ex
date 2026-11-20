defmodule ThamaniDawaWeb.AcceptInviteLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
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
        socket = put_flash(socket, :invite_accepted, true)

        # A hard redirect is required (not push_navigate) when the browser
        # already holds another user's session, since only a real page load
        # reaches SessionController.new/2, which ends that session.
        if socket.assigns.current_scope && socket.assigns.current_scope.user do
          {:noreply, redirect(socket, to: ~p"/login")}
        else
          {:noreply, push_navigate(socket, to: ~p"/login")}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="auth-shell lg:h-svh lg:overflow-hidden">
      <div class="auth-aside hidden lg:flex lg:h-svh">
        <div class="auth-aside-main">
          <a href="/" aria-label="Thamani Dawa home" class="auth-aside-logo">
            <img
              src="/images/logo-transparent.png"
              alt=""
              class="h-auto w-full brightness-0 invert"
            />
          </a>

          <div>
            <span
              class="thamani-badge"
              style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px; margin-bottom: 24px; display: inline-flex; align-items: center; gap: 7px;"
            >
              <svg
                viewBox="0 0 24 24"
                width="14"
                height="14"
                aria-hidden="true"
                style="stroke: currentColor; stroke-width: 1.6; fill: none;"
              >
                <path d="M4 5v14M8 5v14M11 5v14M15 5v14M17 5v14M20 5v14" />
              </svg>
              GS1 Compliant · Built for Kenya
            </span>
            <h2 style="font-size: clamp(28px, 2.8vw, 40px); font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-snow); text-wrap: balance; margin: 16px 0 20px;">
              Join {@organization.name} on Thamani Dawa.
            </h2>
            <p style="font-size: 16px; line-height: 1.65; color: rgba(252,252,247,0.55); max-width: 340px;">
              Set your password to activate your account as a {User.humanize_roles(@user)} and get straight into stock, prescriptions, and lab orders.
            </p>
          </div>
        </div>

        <div style="border-top: 1px solid rgba(252,252,247,0.1); padding-top: 28px;">
          <p style="font-size: 13px; font-weight: 500; color: rgba(252,252,247,0.45);">
            Invited to {@organization.name}
          </p>
        </div>
      </div>

      <div class="auth-form-panel lg:h-svh lg:overflow-y-auto" style="justify-content: center;">
        <div class="auth-form-inner" style="max-width: 380px;">
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

            <div class="mb-7">
              <label class="grid cursor-pointer grid-cols-[1rem_minmax(0,1fr)] items-start gap-x-3">
                <input
                  type="hidden"
                  name={@form[:accepted_legal_terms].name}
                  value="false"
                />
                <input
                  id={@form[:accepted_legal_terms].id}
                  type="checkbox"
                  name={@form[:accepted_legal_terms].name}
                  value="true"
                  checked={@form[:accepted_legal_terms].value in [true, "true"]}
                  required
                  class="mt-1 size-4 rounded border-[var(--thamani-stone)] bg-transparent text-[var(--thamani-forest)] accent-[var(--thamani-forest)] focus:ring-2 focus:ring-[var(--thamani-lime)]"
                />
                <span class="min-w-0 text-xs leading-5 text-[var(--thamani-pewter)]">
                  I agree to the
                  <a
                    href={~p"/terms"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="font-semibold text-[var(--thamani-forest)] underline underline-offset-2 transition hover:text-[var(--thamani-moss)]"
                  >Terms of Service</a>
                  and acknowledge the <a
                    href={~p"/privacy"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="font-semibold text-[var(--thamani-forest)] underline underline-offset-2 transition hover:text-[var(--thamani-moss)]"
                  >Privacy Policy</a>.
                </span>
              </label>
              <%= for error <- @form[:accepted_legal_terms].errors do %>
                <p class="mt-1.5 pl-7 text-xs text-red-700">{translate_error(error)}</p>
              <% end %>
            </div>

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
