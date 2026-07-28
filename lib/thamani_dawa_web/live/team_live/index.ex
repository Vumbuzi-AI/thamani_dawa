defmodule ThamaniDawaWeb.TeamLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites

  @default_filters %{role: "", site_id: "", status: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:editing_user, nil)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign_lists()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    socket = socket |> assign(:page, page) |> assign_lists()

    {form, user, checked_site_ids} =
      case socket.assigns.live_action do
        :new ->
          {to_form(User.invite_changeset(%User{}, %{}), as: :user), nil, []}

        :edit ->
          user_id = String.to_integer(params["id"])
          organization_id = socket.assigns.current_scope.organization_id
          user = Accounts.get_user!(organization_id, user_id)

          {to_form(User.edit_changeset(user, %{}), as: :user), user,
           Enum.map(user.sites, & &1.id)}

        _ ->
          {nil, nil, []}
      end

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:editing_user, user)
     |> assign(:checked_site_ids, checked_site_ids)}
  end

  def handle_event("save", %{"user" => attrs}, socket) do
    %{organization_id: organization_id, user: admin} = socket.assigns.current_scope

    case Accounts.invite_user(organization_id, admin.id, attrs) do
      {:ok, user, encoded_token} ->
        Accounts.deliver_user_invite(
          user,
          socket.assigns.organization.name,
          admin.name,
          encoded_token,
          fn token ->
            url(~p"/invites/#{token}")
          end
        )

        {:noreply,
         socket
         |> put_flash(:info, "Invite sent to #{user.email}.")
         |> assign_lists()
         |> push_patch(to: ~p"/org/team")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("save_edit", %{"user" => attrs}, socket) do
    %{organization_id: organization_id} = socket.assigns.current_scope
    user_id = socket.assigns.editing_user.id

    case Accounts.update_user(organization_id, user_id, attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.name} updated successfully.")
         |> assign_lists()
         |> push_patch(to: ~p"/org/team")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign_lists()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      role: Map.get(filter_params, "role", ""),
      site_id: Map.get(filter_params, "site_id", ""),
      status: Map.get(filter_params, "status", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> assign_lists()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign_lists()}
  end

  def handle_event("clear_chip", %{"field" => field}, socket) do
    key = String.to_existing_atom(field)

    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | key => ""})
     |> assign_lists()}
  end

  defp assign_lists(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page
    sites = Sites.list_sites(organization_id)
    sites_by_id = Map.new(sites, &{&1.id, &1})

    page_result = Accounts.list_users_paginated(organization_id, page)
    users = page_result.entries

    filtered =
      users
      |> filter_by_search(socket.assigns.search)
      |> filter_by_role(socket.assigns.filters.role)
      |> filter_by_site(socket.assigns.filters.site_id)
      |> filter_by_status(socket.assigns.filters.status)

    socket
    |> assign(:users, filtered)
    |> assign(:sites, sites)
    |> assign(:sites_by_id, sites_by_id)
    |> assign(:page_info, page_result)
    |> assign_new(:organization, fn -> Organizations.get_organization!(organization_id) end)
  end

  defp filter_by_search(users, ""), do: users

  defp filter_by_search(users, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(users, fn user ->
      [user.name, user.email]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_role(users, ""), do: users

  defp filter_by_role(users, role) do
    role = String.to_existing_atom(role)
    Enum.filter(users, &(&1.role == role))
  end

  defp filter_by_site(users, ""), do: users

  defp filter_by_site(users, site_id) do
    Enum.filter(users, fn user -> Enum.any?(user.sites, &(to_string(&1.id) == site_id)) end)
  end

  defp filter_by_status(users, ""), do: users
  defp filter_by_status(users, "invited"), do: Enum.filter(users, &(status(&1) == :invited))
  defp filter_by_status(users, "active"), do: Enum.filter(users, &(status(&1) == :active))

  defp active_filter_count(filters) do
    Enum.count([filters.role != "", filters.site_id != "", filters.status != ""], & &1)
  end

  defp filter_chips(filters, sites_by_id) do
    [
      filters.role != "" &&
        %{label: "Role: #{Phoenix.Naming.humanize(filters.role)}", field: "role"},
      filters.site_id != "" &&
        %{
          label: "Site: #{site_name(sites_by_id, String.to_integer(filters.site_id))}",
          field: "site_id"
        },
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"}
    ]
    |> Enum.filter(& &1)
  end

  defp site_name(sites_by_id, site_id) do
    case sites_by_id[site_id] do
      nil -> "—"
      site -> site.name
    end
  end

  defp sites_summary([]), do: "—"
  defp sites_summary(sites), do: Enum.map_join(sites, ", ", & &1.name)

  attr :sites, :list, required: true
  attr :checked_site_ids, :list, required: true

  defp site_checkboxes(assigns) do
    ~H"""
    <div id="user-site-checkboxes">
      <label class="block text-sm font-medium mb-1">Sites</label>
      <input type="hidden" name="user[site_ids][]" value="" />
      <div class="flex flex-col gap-1">
        <label :for={site <- @sites} class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            id={"user_site_ids_#{site.id}"}
            name="user[site_ids][]"
            value={site.id}
            checked={site.id in @checked_site_ids}
            class="checkbox checkbox-sm accent-thamani-forest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
          />
          {site.name}
        </label>
      </div>
      <p class="text-xs text-gray-500 mt-1">Leave all unchecked for org-wide (admin) access.</p>
    </div>
    """
  end

  defp status(%User{hashed_password: nil}), do: :invited
  defp status(%User{}), do: :active

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/team"}>
      <.header icon="hero-users">
        Team
        <:subtitle>Search, filter, and manage your team.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/org/team/new"}>+ Invite staff</.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by name or email" />
          </form>

          <.filter_drawer
            id="team-filters"
            title="Filter team"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Role">
              <.input
                type="select"
                name="filters[role]"
                value={@filters.role}
                options={Enum.map(User.roles(), &{Phoenix.Naming.humanize(&1), &1})}
                prompt="All roles"
              />
            </:group>
            <:group label="Home site">
              <.input
                type="select"
                name="filters[site_id]"
                value={@filters.site_id}
                options={Enum.map(@sites, &{&1.name, &1.id})}
                prompt="All sites"
              />
            </:group>
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={[{"Active", "active"}, {"Invited", "invited"}]}
                prompt="All statuses"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters, @sites_by_id)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal :if={@live_action == :new} id="invite-modal" show on_cancel={JS.patch(~p"/org/team")}>
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Invite a staff member
        </h2>
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
          <.site_checkboxes sites={@sites} checked_site_ids={@checked_site_ids} />
          <div class="mt-2">
            <.button variant="primary" class="w-full">Send invite</.button>
          </div>
        </form>
      </.modal>

      <.modal :if={@live_action == :edit} id="edit-modal" show on_cancel={JS.patch(~p"/org/team")}>
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">Edit team member</h2>
        <form id="edit-form" phx-submit="save_edit">
          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium mb-1">Name</label>
              <p class="text-gray-600">{@editing_user.name}</p>
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Email</label>
              <p class="text-gray-600">{@editing_user.email}</p>
            </div>
            <.input
              field={@form[:role]}
              type="select"
              label="Role"
              options={Enum.map(User.roles(), &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose a role"
              required
            />
            <.site_checkboxes sites={@sites} checked_site_ids={@checked_site_ids} />
          </div>
          <div class="mt-4">
            <.button variant="primary" class="w-full">Save changes</.button>
          </div>
        </form>
      </.modal>

      <.table id="users" rows={@users}>
        <:col :let={user} label="Name">{user.name}</:col>
        <:col :let={user} label="Email">{user.email}</:col>
        <:col :let={user} label="Role">{Phoenix.Naming.humanize(user.role)}</:col>
        <:col :let={user} label="Sites">{sites_summary(user.sites)}</:col>
        <:col :let={user} label="Status">
          <.status_badge status={status(user)} />
        </:col>
        <:action :let={user}>
          <.button
            variant="ghost-edit"
            patch={~p"/org/team/#{user.id}/edit"}
            class="px-3 py-1.5 text-xs"
            id={"btn-edit-user-#{user.id}"}
          >
            Edit
          </.button>
        </:action>
        <:empty_state>
          <.blank_state
            icon="hero-users"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No team members match your search or filters",
                else: "No team members yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Invite teammates to get them access to your organization."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.pagination page={@page_info} path={~p"/org/team"} />
    </Layouts.org_shell>
    """
  end
end
