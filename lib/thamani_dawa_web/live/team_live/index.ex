defmodule ThamaniDawaWeb.TeamLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    {:ok, assign_lists(socket)}
  end

  def handle_params(_params, _url, socket) do
    form =
      if socket.assigns.live_action == :new do
        to_form(User.invite_changeset(%User{}, %{}), as: :user)
      end

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => attrs}, socket) do
    %{organization_id: organization_id, user: admin} = socket.assigns.current_scope

    case Accounts.invite_user(organization_id, admin.id, attrs) do
      {:ok, user, encoded_token} ->
        Accounts.deliver_user_invite(user, encoded_token, fn token ->
          url(~p"/invites/#{token}")
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Invite sent to #{user.email}.")
         |> assign_lists()
         |> push_patch(to: ~p"/org/team")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  defp assign_lists(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sites = Sites.list_sites(organization_id)
    sites_by_id = Map.new(sites, &{&1.id, &1})

    socket
    |> assign(:users, Accounts.list_users(organization_id))
    |> assign(:sites, sites)
    |> assign(:sites_by_id, sites_by_id)
  end

  defp site_name(sites_by_id, site_id) do
    case sites_by_id[site_id] do
      nil -> "—"
      site -> site.name
    end
  end

  defp status(%User{hashed_password: nil}), do: "Invited"
  defp status(%User{}), do: "Active"

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Team
        <:actions>
          <.button variant="primary" navigate={~p"/org/team/new"}>+ Invite staff</.button>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">Invite a staff member</h2>
          <form id="invite-form" phx-submit="save">
            <.input field={@form[:name]} label="Name" required />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input
              field={@form[:role]}
              type="select"
              label="Role"
              options={Enum.map(User.roles(), &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose a role"
              required
            />
            <.input
              field={@form[:site_id]}
              type="select"
              label="Home site"
              options={Enum.map(@sites, &{&1.name, &1.id})}
              prompt="No home site (org-wide)"
            />
            <div class="flex gap-2 mt-2">
              <.button variant="primary">Send invite</.button>
              <.button navigate={~p"/org/team"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <.table id="users" rows={@users}>
        <:col :let={user} label="Name">{user.name}</:col>
        <:col :let={user} label="Email">{user.email}</:col>
        <:col :let={user} label="Role">{Phoenix.Naming.humanize(user.role)}</:col>
        <:col :let={user} label="Home site">{site_name(@sites_by_id, user.site_id)}</:col>
        <:col :let={user} label="Status">{status(user)}</:col>
      </.table>
    </Layouts.app_shell>
    """
  end
end
