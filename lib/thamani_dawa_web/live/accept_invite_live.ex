defmodule ThamaniDawaWeb.AcceptInviteLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This invite link is invalid or has expired.")
         |> redirect(to: ~p"/login")}

      user ->
        form = to_form(ThamaniDawa.Accounts.User.accept_invite_changeset(user, %{}), as: :user)
        {:ok, assign(socket, user: user, form: form)}
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
    <Layouts.unauthenticated flash={@flash}>
      <h1 class="text-lg font-semibold mb-4">Welcome, {@user.name}</h1>
      <p class="text-sm text-base-content/70 mb-4">Set a password to activate your account.</p>

      <form phx-submit="save">
        <.input field={@form[:password]} type="password" label="Password" required />
        <.button variant="primary" class="w-full mt-2">Set password</.button>
      </form>
    </Layouts.unauthenticated>
    """
  end
end
