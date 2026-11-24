defmodule ThamaniDawaWeb.AcceptInviteLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      nil ->
        {:ok,
         assign(socket,
           invalid: true,
           user: nil,
           organization: nil,
           form: to_form(%{}, as: :user)
         )}

      user ->
        user = Repo.preload(user, [:invited_by, :sites])
        organization = Organizations.get_organization!(user.organization_id)
        form = to_form(User.accept_invite_changeset(user, %{}), as: :user)

        {:ok, assign(socket, invalid: false, user: user, organization: organization, form: form)}
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
    <div class="td-auth">
      <div class="td-auth-corner">
        <.td_button
          variant="secondary"
          label="Back to log in"
          navigate={~p"/login"}
          glyph="arrow-left"
        />
      </div>

      <div class="td-auth-col">
        <a href="/" aria-label="Thamani Dawa home" class="td-auth-logo">
          <img src="/images/logo-transparent.png" alt="Thamani Dawa" />
        </a>

        <div :if={@invalid} class="td-auth-panel">
          <h1>This invite link has expired</h1>
          <p class="td-auth-lead">
            This invite link is invalid or has expired. Ask your administrator to send a new one.
          </p>
          <.td_button variant="secondary" size="lg" label="Back to log in" navigate={~p"/login"} />
        </div>

        <div :if={not @invalid} class="td-auth-panel">
          <h1>Join {@organization.name}</h1>
          <p class="td-auth-lead">{invite_lead(@user)}</p>

          <form phx-submit="save" id="accept-invite-form" class="td-auth-form">
            <.td_input
              field={@form[:password]}
              type="password"
              label="Password"
              hint="At least 6 characters"
              placeholder="••••••••"
              autocomplete="new-password"
              required
            />

            <label class="td-check">
              <input type="hidden" name={@form[:accepted_legal_terms].name} value="false" />
              <input
                id={@form[:accepted_legal_terms].id}
                type="checkbox"
                name={@form[:accepted_legal_terms].name}
                value="true"
                checked={@form[:accepted_legal_terms].value in [true, "true"]}
                required
              />
              <span>
                I agree to the
                <a href={~p"/terms"} target="_blank" rel="noopener noreferrer">Terms of Service</a>
                and acknowledge the <a href={~p"/privacy"} target="_blank" rel="noopener noreferrer">Privacy Policy</a>.
              </span>
            </label>
            <p :for={error <- @form[:accepted_legal_terms].errors} class="td-field-error">
              {translate_error(error)}
            </p>

            <.td_button
              id="accept-invite-submit"
              type="submit"
              variant="primary"
              size="lg"
              label="Set password"
            />
          </form>
        </div>
      </div>

      <div class="td-auth-page-foot">
        <.link navigate={~p"/privacy"}>Privacy</.link>
        <.link navigate={~p"/terms"}>Terms</.link>
      </div>
    </div>
    """
  end

  defp invite_lead(user) do
    role = User.humanize_roles(user)
    site = user.sites |> List.first()
    inviter = user.invited_by && user.invited_by.name

    if inviter && site do
      "#{inviter} invited #{user.email} as a #{role} at #{site.name}. Set a password to activate your account."
    else
      "Set a password to activate your account as a #{role}."
    end
  end
end
