defmodule ThamaniDawaWeb.AccountSettingsComponent do
  @moduledoc """
  Account settings modal from the sidebar account menu (Doop e_aY6bJVmi).
  Name and email are saved here; a new password is set through the existing
  emailed reset link, not in this modal.
  """
  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Accounts

  def update(assigns, socket) do
    user = assigns.current_scope.user

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(Accounts.User.profile_changeset(user, %{}), as: :user))}
  end

  def handle_event("save_profile", %{"user" => attrs}, socket) do
    case Accounts.update_profile(socket.assigns.current_scope.user, attrs) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account settings saved.")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("send_reset", _params, socket) do
    user = socket.assigns.current_scope.user

    _ =
      Accounts.deliver_password_reset_instructions(
        user.email,
        &url(~p"/reset-password/#{&1}")
      )

    {:noreply,
     socket
     |> put_flash(:info, "We've emailed you a link to set a new password.")
     |> push_navigate(to: socket.assigns.return_to)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.td_modal
        id="account-settings-modal"
        title="Account settings"
        subtitle="Your name, email, and password."
        on_cancel={ThamaniDawaWeb.CoreComponents.hide_modal("account-settings-modal")}
      >
        <:body>
          <form
            id="account-settings-form"
            phx-submit="save_profile"
            phx-target={@myself}
            class="td-settings-form"
          >
            <div class="td-member-hd">
              <.td_orb seed={@current_scope.user.email} size={32} />
              <div>
                <span class="td-am-name">{@current_scope.user.name}</span>
                <span class="td-am-role">
                  {@role_label}{if @context, do: " · #{@context}"}
                </span>
              </div>
            </div>
            <.td_input field={@form[:name]} label="Full name" required />
            <.td_input field={@form[:email]} type="email" label="Email" required />
            <div class="td-access-row">
              <div>
                <b>Password</b>
                <p>We email you a link to set a new password.</p>
              </div>
              <.td_button
                id="account-settings-send-reset"
                type="button"
                variant="secondary"
                label="Send reset link"
                phx-click="send_reset"
                phx-target={@myself}
              />
            </div>
          </form>
        </:body>
        <:footer>
          <.td_button
            type="button"
            variant="secondary"
            label="Cancel"
            phx-click={ThamaniDawaWeb.CoreComponents.hide_modal("account-settings-modal")}
          />
          <.td_button
            id="account-settings-save"
            type="submit"
            variant="primary"
            label="Save changes"
            form="account-settings-form"
          />
        </:footer>
      </.td_modal>
    </div>
    """
  end
end
