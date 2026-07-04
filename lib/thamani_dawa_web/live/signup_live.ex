defmodule ThamaniDawaWeb.SignupLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:org_form, to_form(Organization.changeset(%Organization{}, %{}), as: :organization))
      |> assign(:admin_form, to_form(User.registration_changeset(%User{}, %{}), as: :user))

    {:ok, socket}
  end

  def handle_event("save", %{"organization" => org_params, "user" => admin_params}, socket) do
    case Organizations.signup(org_params, admin_params) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created — log in with the password you just set.")
         |> push_navigate(to: ~p"/login")}

      {:error, %Ecto.Changeset{data: %Organization{}} = changeset} ->
        {:noreply, assign(socket, :org_form, to_form(changeset, as: :organization))}

      {:error, %Ecto.Changeset{data: %User{}} = changeset} ->
        {:noreply, assign(socket, :admin_form, to_form(changeset, as: :user))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Something went wrong setting up your organization. Please try again.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.unauthenticated flash={@flash}>
      <h1 class="text-lg font-semibold mb-4">Set up your organization</h1>

      <form phx-submit="save">
        <.input field={@org_form[:name]} label="Organization / pharmacy name" required />

        <div class="divider" />

        <.input field={@admin_form[:name]} label="Your name" required />
        <.input field={@admin_form[:email]} type="email" label="Email" required />
        <.input field={@admin_form[:password]} type="password" label="Password" required />

        <.button variant="primary" class="w-full mt-2">Create account</.button>
      </form>

      <p class="text-sm mt-4">
        Already have an account? <.link navigate={~p"/login"} class="link">Log in</.link>
      </p>
    </Layouts.unauthenticated>
    """
  end
end
