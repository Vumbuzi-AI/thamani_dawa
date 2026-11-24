defmodule ThamaniDawaWeb.TeamLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @default_filters %{role: "", site_id: "", status: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:editing_user, nil)
     |> assign(:confirming_user, nil)
     |> assign(:selected_roles, [])
     |> assign(:onboarding_invited, [])
     |> assign(:onboarding_progress, {0, 0})
     |> assign(:show_onboarding_invite_form?, false)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign_lists()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> assign_lists()
      |> maybe_restore_onboarding_invites(params)

    {form, user, checked_site_ids, selected_roles} =
      case socket.assigns.live_action do
        :new ->
          {to_form(User.invite_changeset(%User{}, %{}), as: :user), nil, [], []}

        :edit ->
          user_id = String.to_integer(params["id"])
          organization_id = socket.assigns.current_scope.organization_id
          user = Accounts.get_user!(organization_id, user_id)

          {to_form(User.edit_changeset(user, %{}), as: :user), user,
           Enum.map(user.sites, & &1.id), Enum.map(user.roles, &to_string/1)}

        _ ->
          {nil, nil, [], []}
      end

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:editing_user, user)
     |> assign(:checked_site_ids, checked_site_ids)
     |> assign(:selected_roles, selected_roles)
     |> assign(:replay_next, params["replay_next"])
     |> assign(:back_path, back_path(params))}
  end

  def handle_event("save", %{"user" => attrs}, socket) do
    %{organization_id: organization_id, user: admin} = socket.assigns.current_scope
    attrs = maybe_assign_onboarding_site(attrs, socket)

    if missing_onboarding_site_selection?(attrs, socket) do
      changeset =
        %User{}
        |> User.invite_changeset(attrs)
        |> Ecto.Changeset.add_error(:sites, "select at least one branch")

      {:noreply,
       socket
       |> assign(:form, to_form(changeset, as: :user))
       |> put_flash(:error, "Select at least one branch.")}
    else
      invite_user(socket, organization_id, admin, attrs)
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

  def handle_event("form_change", %{"user" => attrs}, socket) do
    selected_roles = attrs |> Map.get("roles", []) |> Enum.reject(&(&1 == ""))

    checked_site_ids =
      attrs
      |> Map.get("site_ids", [])
      |> List.wrap()
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_integer/1)

    {:noreply,
     socket
     |> assign(:selected_roles, selected_roles)
     |> assign(:checked_site_ids, checked_site_ids)}
  end

  def handle_event("continue_onboarding", _params, socket) do
    destination =
      if socket.assigns.replay_next == "first_product",
        do: ~p"/onboarding?replay=first_product",
        else: ~p"/onboarding?complete=1"

    {:noreply, push_navigate(socket, to: destination)}
  end

  def handle_event("open_onboarding_invite", _params, socket) do
    {:noreply, assign(socket, :show_onboarding_invite_form?, true)}
  end

  def handle_event("close_onboarding_invite", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_onboarding_invite_form?, false)
     |> assign(:form, to_form(User.invite_changeset(%User{}, %{}), as: :user))
     |> assign(:selected_roles, [])}
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

  def handle_event("toggle_active", %{"id" => id}, socket) do
    %{organization_id: organization_id, user: admin} = socket.assigns.current_scope
    user = Accounts.get_user!(organization_id, String.to_integer(id))
    active? = not user.is_active

    case Accounts.set_user_active(organization_id, admin.id, user.id, active?) do
      {:ok, updated_user} ->
        action = if updated_user.is_active, do: "reactivated", else: "deactivated"

        socket =
          socket
          |> assign(:confirming_user, nil)
          |> put_flash(:info, "#{updated_user.name} #{action}.")
          |> assign_lists()

        socket =
          if socket.assigns.live_action == :edit do
            if updated_user.is_active do
              assign(socket, :editing_user, updated_user)
            else
              push_patch(socket, to: ~p"/org/team")
            end
          else
            socket
          end

        {:noreply, socket}

      {:error, :cannot_deactivate_self} ->
        {:noreply, put_flash(socket, :error, "You cannot deactivate your own account.")}

      {:error, :last_active_admin} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Assign another active admin before deactivating this account."
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to change account access.")}
    end
  end

  def handle_event("prompt_deactivate", %{"id" => id}, socket) do
    user = Accounts.get_user!(socket.assigns.current_scope.organization_id, String.to_integer(id))
    {:noreply, assign(socket, :confirming_user, user)}
  end

  def handle_event("cancel_deactivate", _params, socket) do
    {:noreply, assign(socket, :confirming_user, nil)}
  end

  defp invite_user(socket, organization_id, admin, attrs) do
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

        socket =
          socket
          |> put_flash(:info, "Invite sent to #{user.email}.")
          |> assign_lists()

        if socket.assigns.back_path == ~p"/onboarding" do
          {:noreply,
           socket
           |> update(:onboarding_invited, &(&1 ++ [user]))
           |> assign(:form, to_form(User.invite_changeset(%User{}, %{}), as: :user))
           |> assign(:selected_roles, [])
           |> assign(:checked_site_ids, [])
           |> assign(:show_onboarding_invite_form?, false)}
        else
          {:noreply, return_after_invite(socket)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  defp missing_onboarding_site_selection?(attrs, socket) do
    roles = attrs |> Map.get("roles", []) |> Enum.reject(&(&1 == ""))
    site_ids = attrs |> Map.get("site_ids", []) |> List.wrap() |> Enum.reject(&(&1 == ""))

    socket.assigns.back_path == ~p"/onboarding" and length(socket.assigns.sites) > 1 and
      "admin" not in roles and site_ids == []
  end

  defp onboarding_progress_pct({current, total}) when total > 0, do: current / total * 100
  defp onboarding_progress_pct(_progress), do: 0

  defp back_path(%{"return_to" => "onboarding"}), do: ~p"/onboarding"
  defp back_path(%{"return_to" => "dashboard"}), do: ~p"/org/dashboard"
  defp back_path(_params), do: ~p"/org/team"

  defp return_after_invite(socket) do
    if socket.assigns.back_path in [~p"/org/dashboard", ~p"/onboarding"] do
      push_navigate(socket, to: socket.assigns.back_path)
    else
      push_patch(socket, to: socket.assigns.back_path)
    end
  end

  defp maybe_assign_onboarding_site(attrs, socket) do
    roles = attrs |> Map.get("roles", []) |> Enum.reject(&(&1 == ""))

    if socket.assigns.back_path == ~p"/onboarding" and "admin" not in roles and
         match?([_], socket.assigns.sites) do
      [site] = socket.assigns.sites
      Map.put(attrs, "site_ids", [to_string(site.id)])
    else
      attrs
    end
  end

  defp maybe_restore_onboarding_invites(socket, %{"return_to" => "onboarding"}) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)

    socket
    |> assign(:onboarding_invited, Accounts.list_invited_users(organization_id))
    |> assign(:onboarding_progress, Organizations.onboarding_progress(organization))
  end

  defp maybe_restore_onboarding_invites(socket, _params), do: socket

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
    Enum.filter(users, &(role in &1.roles))
  end

  defp filter_by_site(users, ""), do: users

  defp filter_by_site(users, site_id) do
    Enum.filter(users, fn user -> Enum.any?(user.sites, &(to_string(&1.id) == site_id)) end)
  end

  defp filter_by_status(users, ""), do: users
  defp filter_by_status(users, "invited"), do: Enum.filter(users, &(status(&1) == :invited))
  defp filter_by_status(users, "active"), do: Enum.filter(users, &(status(&1) == :active))
  defp filter_by_status(users, "inactive"), do: Enum.filter(users, &(status(&1) == :inactive))

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

  defp compatible_sites(_sites, roles) when roles in [[], nil], do: []
  defp compatible_sites(_sites, ["admin"]), do: []

  defp compatible_sites(sites, roles) do
    clinical_roles = Enum.reject(roles, &(&1 == "admin"))

    if clinical_roles == [] do
      []
    else
      Enum.filter(sites, fn site ->
        Enum.any?(clinical_roles, &site_matches_role?(site, &1))
      end)
    end
  end

  defp site_matches_role?(site, "pharmacist"), do: Site.pharmacy?(site)
  defp site_matches_role?(site, "lab_technician"), do: Site.lab?(site)
  defp site_matches_role?(site, "distributor"), do: Site.distribution?(site)
  defp site_matches_role?(_site, _role), do: true

  defp role_copy(role) when not is_binary(role), do: role_copy(to_string(role))
  defp role_copy("pharmacist"), do: "Dispense and sell at pharmacy sites."
  defp role_copy("lab_technician"), do: "Run orders at lab sites."
  defp role_copy("admin"), do: "Every site in the organization."
  defp role_copy("distributor"), do: "Receive, pack, and ship at warehouse sites."
  defp role_copy("manufacturer"), do: "Commission, pack, and ship from manufacturing sites."
  defp role_copy(_role), do: nil

  attr :selected_roles, :list, required: true
  attr :errors, :list, default: []
  attr :organization, :map, required: true

  defp role_checkboxes(assigns) do
    ~H"""
    <div class="mt-3">
      <label class="block text-sm font-medium mb-2">Roles</label>
      <input type="hidden" name="user[roles][]" value="" />
      <div class="grid gap-1.5">
        <label
          :for={role <- User.assignable_roles(@organization.operating_models)}
          class={["td-role-card", to_string(role) in @selected_roles && "is-selected"]}
        >
          <input
            type="checkbox"
            name="user[roles][]"
            value={role}
            checked={to_string(role) in @selected_roles}
            class="size-4 shrink-0 rounded accent-[var(--color-td-accent)] cursor-pointer mt-0.5"
          />
          <span>
            <b>{Phoenix.Naming.humanize(role)}</b>
            <span>{role_copy(role)}</span>
          </span>
        </label>
      </div>
      <p :for={error <- @errors} class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
    </div>
    """
  end

  attr :sites, :list, required: true
  attr :all_sites, :list, default: []
  attr :checked_site_ids, :list, required: true
  attr :selected_roles, :list, default: []
  attr :errors, :list, default: []

  defp site_checkboxes(assigns) do
    assigns = assign_new(assigns, :selected_roles, fn -> [] end)

    ~H"""
    <div id="user-site-checkboxes" class="mt-3">
      <label class="block text-sm font-medium mb-2 text-thamani-forest">Sites</label>

      <select name="user[site_ids][]" class="hidden" multiple>
        <option value="">None</option>
        <option
          :for={site <- if @all_sites != [], do: @all_sites, else: @sites}
          value={to_string(site.id)}
        >
          {site.name}
        </option>
      </select>

      <div :if={@selected_roles == []}>
        <div class="flex items-center gap-2.5 text-xs text-thamani-pewter bg-thamani-stone/30 border border-dashed border-thamani-stone rounded-xl p-3.5">
          <.icon name="hero-lock-closed" class="size-4 shrink-0 text-thamani-pewter" />
          <span>Select a role above to view and assign compatible sites.</span>
        </div>
      </div>

      <div :if={@selected_roles != [] and @selected_roles != ["admin"]}>
        <div
          :if={@sites == []}
          class="text-xs text-thamani-pewter bg-thamani-stone/30 border border-thamani-stone rounded-xl p-3 text-center"
        >
          No compatible sites available for this role.
        </div>

        <label
          :for={site <- @sites}
          :if={match?([_], @sites)}
          title={site.name}
          class="flex items-center gap-3 rounded-lg border border-thamani-stone bg-thamani-canvas px-3 py-2 text-sm text-thamani-forest"
        >
          <input
            type="checkbox"
            id={"user_site_ids_#{site.id}"}
            name="user[site_ids][]"
            value={site.id}
            checked
            class="size-4 shrink-0 rounded accent-thamani-forest cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
          />
          <span class="font-medium truncate min-w-0">{site.name}</span>
        </label>

        <div :if={length(@sites) > 1}>
          <input
            type="text"
            id="site-search"
            placeholder="Search compatible sites…"
            oninput="
              const q = this.value.toLowerCase();
              document.querySelectorAll('#site-checkbox-list label').forEach(lbl => {
                lbl.style.display = lbl.querySelector('span').textContent.toLowerCase().includes(q) ? '' : 'none';
              });
            "
            class="thamani-input mb-2 h-9 w-full rounded-lg px-3 text-sm focus:border-thamani-forest focus:outline-none focus:ring-0 transition-colors"
            autocomplete="off"
          />

          <div
            id="site-checkbox-list"
            class="grid grid-cols-1 gap-1.5 max-h-48 overflow-y-auto pr-1"
          >
            <label
              :for={site <- @sites}
              title={site.name}
              class="flex items-center gap-3 rounded-lg border border-thamani-stone bg-thamani-canvas px-3 py-2 text-sm text-thamani-forest cursor-pointer hover:bg-thamani-stone/50 transition-colors"
            >
              <input
                type="checkbox"
                id={"user_site_ids_#{site.id}"}
                name="user[site_ids][]"
                value={site.id}
                checked={site.id in @checked_site_ids}
                class="size-4 shrink-0 rounded accent-thamani-forest cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
              />
              <span class="font-medium truncate min-w-0">{site.name}</span>
            </label>
          </div>
        </div>
      </div>
      <p :for={error <- @errors} class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
    </div>
    """
  end

  defp status(%User{is_active: false}), do: :inactive
  defp status(%User{hashed_password: nil}), do: :invited
  defp status(%User{}), do: :active

  def render(assigns) do
    ~H"""
    <%= if @live_action == :new and @back_path == ~p"/onboarding" do %>
      <Layouts.app flash={@flash} current_scope={@current_scope} navigation={false}>
        <div id="onboarding-invite-shell" class="flex min-h-svh flex-col bg-[var(--thamani-surface)]">
          <header class="border-b border-[color-mix(in_srgb,var(--thamani-stone)_70%,transparent)]">
            <div class="mx-auto flex h-20 w-full max-w-7xl items-center justify-between gap-6 px-5 sm:px-8 lg:px-12">
              <.link
                navigate={~p"/onboarding"}
                aria-label="Back to onboarding"
                class="w-36 sm:w-[148px]"
              >
                <img src="/images/logo-transparent.png" alt="" class="h-auto w-full" />
              </.link>

              <div id="onboarding-invite-user" class="flex min-w-0 items-center gap-3">
                <.td_orb seed={@current_scope.user.email} size={36} />
                <span class="max-w-44 truncate text-sm font-medium text-[var(--thamani-forest)]">
                  {@current_scope.user.name}
                </span>
              </div>
            </div>
          </header>

          <div
            class="h-1 w-full overflow-hidden bg-[var(--thamani-stone)]"
            aria-label="Setup progress"
          >
            <div
              class="h-full bg-[var(--thamani-forest)] transition-[width] duration-300 ease-out"
              style={"width: #{onboarding_progress_pct(@onboarding_progress)}%"}
            />
          </div>

          <main class="mx-auto grid w-full max-w-6xl flex-1 items-start gap-10 px-5 pb-16 pt-10 sm:px-8 sm:pt-12 md:grid-cols-[0.7fr_1.3fr] md:gap-10 md:pt-16 lg:gap-16 lg:pt-20">
            <section class="thamani-step-enter flex flex-col items-center text-center md:block md:text-left">
              <div class="mb-7 flex size-12 items-center justify-center rounded-2xl bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] text-[var(--thamani-forest)]">
                <.td_icon name="users-three" class="size-6" />
              </div>
              <h1 class="w-full max-w-md text-[30px] font-light leading-[1.08] tracking-[-0.7px] text-[var(--thamani-forest)] sm:text-[38px]">
                Invite your team
              </h1>
              <p class="mt-6 w-full max-w-md text-base leading-7 text-[var(--thamani-pewter)] sm:text-[17px]">
                Bring in the staff who will help run day-to-day operations at your locations.
              </p>
            </section>

            <section class="thamani-step-enter rounded-3xl border border-[var(--thamani-stone)] bg-[var(--thamani-canvas)]/50 p-6 sm:p-8">
              <div class="flex items-start justify-between gap-5">
                <div>
                  <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
                    Invited teammates
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-thamani-pewter">
                    Review invitations sent during setup.
                  </p>
                </div>
                <button
                  id="onboarding-open-invite"
                  type="button"
                  phx-click="open_onboarding_invite"
                  class="inline-flex min-h-11 shrink-0 items-center justify-center rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md"
                >
                  <.icon name="hero-plus" class="mr-2 size-4" /> Invite teammate
                </button>
              </div>

              <div
                :if={@onboarding_invited == []}
                id="onboarding-invited-empty"
                class="mt-8 flex min-h-52 flex-col items-center justify-center rounded-2xl border border-dashed border-[var(--thamani-stone)] bg-transparent px-6 text-center"
              >
                <span class="flex size-12 items-center justify-center rounded-2xl bg-td-surface text-[var(--thamani-forest)] shadow-sm ring-1 ring-black/[0.04]">
                  <.icon name="hero-envelope" class="size-6" />
                </span>
                <h3 class="mt-4 text-base font-semibold text-thamani-forest">No invitations yet</h3>
                <p class="mt-1 max-w-xs text-sm leading-6 text-thamani-pewter">
                  Invite the first teammate who will help operate your locations.
                </p>
              </div>

              <div :if={@onboarding_invited != []} id="onboarding-invited-list" class="mt-8">
                <h3 class="mb-3 text-sm font-semibold text-thamani-forest">
                  Invited ({length(@onboarding_invited)})
                </h3>

                <div class="overflow-hidden rounded-2xl border border-[var(--thamani-stone)]">
                  <div class="grid grid-cols-[1fr_1fr_auto] gap-4 bg-[var(--thamani-stone)]/60 px-4 py-2.5 text-xs font-medium text-thamani-pewter">
                    <span>Email</span>
                    <span>Role</span>
                    <span class="w-24 text-right">Status</span>
                  </div>

                  <div class="divide-y divide-[var(--thamani-stone)]">
                    <div
                      :for={user <- @onboarding_invited}
                      id={"onboarding-invited-#{user.id}"}
                      class="grid grid-cols-[1fr_1fr_auto] items-center gap-4 px-4 py-3"
                    >
                      <span class="min-w-0 truncate text-sm text-thamani-forest">
                        {user.email}
                      </span>
                      <span class="min-w-0 truncate text-sm text-thamani-pewter">
                        {User.humanize_roles(user)}
                      </span>
                      <span class="flex w-24 justify-end">
                        <span
                          :if={status(user) == :invited}
                          class="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-semibold text-amber-900"
                        >
                          Invited
                        </span>
                        <span
                          :if={status(user) == :active}
                          class="inline-flex items-center gap-1 rounded-full bg-td-accent-tint px-2.5 py-1 text-xs font-semibold text-thamani-forest"
                        >
                          <.icon name="hero-check-circle" class="size-3.5" /> Accepted
                        </span>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </section>

            <div class="flex items-center justify-between gap-4 md:col-span-2">
              <div class="flex items-center gap-4">
                <.link
                  id="onboarding-invite-back"
                  navigate={~p"/onboarding"}
                  class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:text-[var(--thamani-forest)]"
                >
                  <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
                </.link>
                <.link
                  id="onboarding-invite-skip"
                  navigate={
                    if @replay_next == "first_product",
                      do: ~p"/onboarding?replay=first_product",
                      else: ~p"/onboarding?skip=invite_team"
                  }
                  class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] underline decoration-[color-mix(in_srgb,var(--thamani-pewter)_45%,transparent)] underline-offset-4 transition-colors hover:text-[var(--thamani-forest)]"
                >
                  Skip this step
                </.link>
              </div>
              <button
                id="onboarding-invite-continue"
                type="button"
                phx-click="continue_onboarding"
                disabled={@onboarding_invited == []}
                class="inline-flex min-h-12 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg disabled:pointer-events-none disabled:opacity-40"
              >
                Continue <.icon name="hero-arrow-right" class="ml-3 size-4" />
              </button>
            </div>
          </main>

          <.modal
            :if={@show_onboarding_invite_form?}
            id="onboarding-invite-modal"
            show
            on_cancel={JS.push("close_onboarding_invite")}
            close_on_click_away={false}
          >
            <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
              Invite a teammate
            </h2>
            <p class="mt-2 text-sm leading-6 text-thamani-pewter">
              We will email them a secure invitation to join your workspace.
            </p>

            <form
              id="onboarding-invite-form"
              phx-submit="save"
              phx-change="form_change"
              class="mt-6"
            >
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@form[:name]} label="Name" required />
                <.input field={@form[:email]} type="email" label="Email" required />
              </div>
              <.role_checkboxes
                selected_roles={@selected_roles}
                errors={@form[:roles].errors}
                organization={@organization}
              />
              <.site_checkboxes
                :if={@selected_roles != ["admin"]}
                sites={compatible_sites(@sites, @selected_roles)}
                all_sites={@sites}
                checked_site_ids={@checked_site_ids}
                selected_roles={@selected_roles}
                errors={@form[:sites].errors}
              />
              <div
                :if={"admin" in @selected_roles}
                class="mt-3 flex items-center gap-2.5 rounded-xl border border-thamani-stone bg-thamani-stone/40 p-3 text-xs text-thamani-pewter"
              >
                <.icon name="hero-information-circle" class="size-4 shrink-0 text-thamani-forest" />
                Admins can access every branch in the organization.
              </div>
              <div class="mt-5 flex justify-end gap-3">
                <button
                  id="onboarding-invite-cancel"
                  type="button"
                  phx-click="close_onboarding_invite"
                  class="inline-flex min-h-11 items-center justify-center rounded-full px-5 text-sm font-medium text-thamani-pewter transition-colors hover:bg-thamani-canvas hover:text-thamani-forest"
                >
                  Cancel
                </button>
                <.button variant="primary" class="min-w-40">Send invite</.button>
              </div>
            </form>
          </.modal>
        </div>
      </Layouts.app>
    <% else %>
      <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/team"}>
        <.td_list_page title="Team" subtitle="Search, filter, and manage your team.">
          <:actions>
            <.td_button variant="primary" label="Invite staff" glyph="plus" patch={~p"/org/team/new"} />
          </:actions>
          <:filters>
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
                  options={Enum.map(User.assignable_roles(), &{Phoenix.Naming.humanize(&1), &1})}
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
                  options={[{"Active", "active"}, {"Invited", "invited"}, {"Inactive", "inactive"}]}
                  prompt="All statuses"
                />
              </:group>
              <:chip
                :for={chip <- filter_chips(@filters, @sites_by_id)}
                label={chip.label}
                clear={JS.push("clear_chip", value: %{"field" => chip.field})}
              />
            </.filter_drawer>
          </:filters>

        <.td_overlay_form
          :if={@live_action == :new}
          id="invite"
          title="Invite a staff member"
          submit="Send invite"
          on_cancel={
            if @back_path in [~p"/org/dashboard", ~p"/onboarding"],
              do: JS.navigate(@back_path),
              else: JS.patch(@back_path)
          }
        >
          <form id="invite-form" phx-submit="save" phx-change="form_change">
            <.input field={@form[:name]} label="Name" required />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.role_checkboxes
              selected_roles={@selected_roles}
              errors={@form[:roles].errors}
              organization={@organization}
            />
            <.site_checkboxes
              :if={@selected_roles != ["admin"]}
              sites={compatible_sites(@sites, @selected_roles)}
              all_sites={@sites}
              checked_site_ids={@checked_site_ids}
              selected_roles={@selected_roles}
            />
            <div
              :if={"admin" in @selected_roles}
              class="flex items-center gap-2.5 text-xs text-thamani-pewter bg-thamani-stone/40 border border-thamani-stone rounded-xl p-3 mt-3"
            >
              <.icon name="hero-information-circle" class="size-4 shrink-0 text-thamani-forest" />
              <span>Admins automatically have organization-wide access across all sites.</span>
            </div>
          </form>
        </.td_overlay_form>

        <.td_modal
          :if={@live_action == :edit}
          id="edit-modal"
          show
          title="Edit team member"
          subtitle="Change roles and site access."
          on_cancel={JS.patch(~p"/org/team")}
        >
          <:body>
            <form id="edit-form" phx-submit="save_edit" phx-change="form_change">
              <div class="td-member-hd">
                <.td_orb seed={@editing_user.email} size={32} />
                <div>
                  <span class="td-am-name">{@editing_user.name}</span>
                  <span class="td-am-role">{@editing_user.email}</span>
                </div>
                <.status_badge status={status(@editing_user)} class="td-status" />
              </div>
              <.role_checkboxes
                selected_roles={@selected_roles}
                errors={@form[:roles].errors}
                organization={@organization}
              />
              <.site_checkboxes
                :if={@selected_roles != ["admin"]}
                sites={compatible_sites(@sites, @selected_roles)}
                all_sites={@sites}
                checked_site_ids={@checked_site_ids}
                selected_roles={@selected_roles}
              />
              <div
                :if={"admin" in @selected_roles}
                class="flex items-center gap-2.5 text-xs text-thamani-pewter mt-3"
              >
                <.td_icon name="info" />
                <span>Admins automatically have organization-wide access across all sites.</span>
              </div>
              <div class="td-access-row">
                <%= if @editing_user.id == @current_scope.user.id do %>
                  <p>This is your account. You cannot deactivate your own account.</p>
                <% else %>
                  <%= if status(@editing_user) == :inactive do %>
                    <div>
                      <b>Account deactivated</b>
                      <p>Reactivate to restore access.</p>
                    </div>
                    <.td_button
                      id={"btn-toggle-active-user-#{@editing_user.id}"}
                      type="button"
                      variant="secondary"
                      label="Reactivate"
                      phx-click="toggle_active"
                      phx-value-id={@editing_user.id}
                    />
                  <% else %>
                    <div>
                      <b>Deactivate account</b>
                      <p>
                        {if status(@editing_user) == :invited,
                          do: "Not accepted yet. Deactivate to stop them joining.",
                          else: "They lose access straight away. You can reactivate later."}
                      </p>
                    </div>
                    <.td_button
                      id={"btn-prompt-deactivate-#{@editing_user.id}"}
                      type="button"
                      variant="danger"
                      label="Deactivate"
                      phx-click="prompt_deactivate"
                      phx-value-id={@editing_user.id}
                    />
                  <% end %>
                <% end %>
              </div>
            </form>
          </:body>
          <:footer>
            <.td_button variant="secondary" label="Cancel" patch={~p"/org/team"} />
            <.td_button variant="primary" label="Save changes" glyph="check" form="edit-form" type="submit" />
          </:footer>
        </.td_modal>

        <.table id="users" rows={@users} row_click={fn user -> JS.patch(~p"/org/team/#{user.id}/edit") end}>
          <:col :let={user} label="Name">{user.name}</:col>
          <:col :let={user} label="Email">{user.email}</:col>
          <:col :let={user} label="Role">
            <span class="sm:line-clamp-2" title={User.humanize_roles(user)}>
              {User.humanize_roles(user)}
            </span>
          </:col>
          <:col :let={user} label="Sites">
            <span class="sm:line-clamp-2" title={sites_summary(user.sites)}>
              {sites_summary(user.sites)}
            </span>
          </:col>
          <:col :let={user} label="Status">
            <.status_badge status={status(user)} />
          </:col>
          <:action :let={user}>
            <div class="td-row-menu">
              <.td_icon_button
                id={"btn-row-menu-#{user.id}"}
                label="Row actions"
                phx-click={JS.toggle(to: "#team-row-menu-#{user.id}")}
              >
                <:icon><.td_icon name="dots-three" /></:icon>
              </.td_icon_button>
              <div id={"team-row-menu-#{user.id}"} class="td-row-menu-list" hidden>
                <.td_menu_item
                  id={"btn-edit-user-#{user.id}"}
                  label="Edit"
                  patch={~p"/org/team/#{user.id}/edit"}
                />
                <.td_menu_item
                  :if={user.id != @current_scope.user.id and user.is_active}
                  id={"btn-prompt-deactivate-row-#{user.id}"}
                  label="Deactivate"
                  tone="danger"
                  phx-click="prompt_deactivate"
                  phx-value-id={user.id}
                />
                <.td_menu_item
                  :if={user.id != @current_scope.user.id and not user.is_active}
                  id={"btn-toggle-active-user-#{user.id}"}
                  label="Reactivate"
                  phx-click="toggle_active"
                  phx-value-id={user.id}
                />
              </div>
            </div>
          </:action>
          <:empty_state>
            <.blank_state
              icon="users-three"
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

        <.td_confirm
          :if={@confirming_user}
          id="deactivate-confirm"
          title="Deactivate this account?"
          subtitle={@confirming_user.name}
          body="They lose access straight away. You can reactivate later."
          confirm="Deactivate"
          confirm_click="toggle_active"
          confirm_id={"btn-toggle-active-user-#{@confirming_user.id}"}
          confirm_value_id={@confirming_user.id}
          on_cancel={JS.push("cancel_deactivate")}
        />
        </.td_list_page>
      </Layouts.org_shell>
    <% end %>
    """
  end
end
