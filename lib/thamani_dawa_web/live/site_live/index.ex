defmodule ThamaniDawaWeb.SiteLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @default_filters %{site_type: "", status: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign_sites()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> assign_sites()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    socket
    |> assign(form: to_form(Site.changeset(%Site{}, %{}), as: :site), site: nil)
    |> assign(:back_path, back_path(params, ~p"/org/sites"))
  end

  defp apply_action(socket, :edit, %{"id" => id} = params) do
    organization_id = socket.assigns.current_scope.organization_id
    site = Sites.get_site!(organization_id, id)

    socket
    |> assign(form: to_form(Site.changeset(site, %{}), as: :site), site: site)
    |> assign(:back_path, back_path(params, ~p"/org/sites"))
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, site: nil, back_path: ~p"/org/sites")
  end

  def handle_event("validate", _, %{assigns: %{live_action: :index}} = socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"site" => attrs}, socket) do
    changeset = Site.changeset(socket.assigns.site || %Site{}, attrs)
    {:noreply, assign(socket, :form, to_form(changeset, as: :site, action: :validate))}
  end

  def handle_event("save", %{"site" => attrs}, socket) do
    save_site(socket, socket.assigns.live_action, attrs)
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign_sites()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      site_type: Map.get(filter_params, "site_type", ""),
      status: Map.get(filter_params, "status", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> assign_sites()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign_sites()}
  end

  def handle_event("clear_chip", %{"field" => field}, socket) do
    key = String.to_existing_atom(field)

    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | key => ""})
     |> assign_sites()}
  end

  defp save_site(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Sites.create_site(organization_id, attrs) do
      {:ok, _site} ->
        socket = socket |> put_flash(:info, "Site created.") |> assign_sites()
        {:noreply, return_after_save(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp save_site(socket, :edit, attrs) do
    case Sites.update_site(socket.assigns.site, attrs) do
      {:ok, _site} ->
        socket = socket |> put_flash(:info, "Site updated.") |> assign_sites()
        {:noreply, return_after_save(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp back_path(%{"return_to" => "dashboard"}, _default), do: ~p"/org/dashboard"
  defp back_path(_params, default), do: default

  defp return_after_save(socket) do
    if socket.assigns.back_path == ~p"/org/dashboard" do
      push_navigate(socket, to: ~p"/org/dashboard?tour=1")
    else
      push_patch(socket, to: socket.assigns.back_path)
    end
  end

  defp assign_sites(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = Sites.list_sites_paginated(organization_id, page)
    sites = page_result.entries

    filtered =
      sites
      |> filter_by_search(socket.assigns.search)
      |> filter_by_type(socket.assigns.filters.site_type)
      |> filter_by_status(socket.assigns.filters.status)

    socket
    |> assign(:sites, filtered)
    |> assign(:page_info, page_result)
  end

  defp filter_by_search(sites, ""), do: sites

  defp filter_by_search(sites, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(sites, fn site ->
      [site.name, site.address]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_type(sites, ""), do: sites

  defp filter_by_type(sites, site_type) do
    site_type = String.to_existing_atom(site_type)
    Enum.filter(sites, &(&1.site_type == site_type))
  end

  defp filter_by_status(sites, ""), do: sites
  defp filter_by_status(sites, "active"), do: Enum.filter(sites, & &1.is_active)
  defp filter_by_status(sites, "inactive"), do: Enum.filter(sites, &(!&1.is_active))

  defp active_filter_count(filters) do
    Enum.count([filters.site_type != "", filters.status != ""], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.site_type != "" &&
        %{label: "Type: #{Phoenix.Naming.humanize(filters.site_type)}", field: "site_type"},
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"}
    ]
    |> Enum.filter(& &1)
  end

  defp capability_options do
    [
      {"Pharmacy", "Dispensing & stock", :pharmacy},
      {"Lab", "Orders & results", :lab},
      {"Pharmacy + Lab", "Both workflows", :pharmacy_lab},
      {"Warehouse", "Stock holding only", :warehouse}
    ]
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/sites"}>
      <.header icon="hero-building-office-2">
        Sites
        <:subtitle>Search, filter, and manage your sites.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/org/sites/new"}>
            <.icon name="hero-plus" class="size-4" /> Add site
          </.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by name or address" />
          </form>

          <.filter_drawer
            id="sites-filters"
            title="Filter sites"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Type">
              <.input
                type="select"
                name="filters[site_type]"
                value={@filters.site_type}
                options={
                  Enum.map(capability_options(), fn {label, _desc, value} -> {label, value} end)
                }
                prompt="All types"
              />
            </:group>
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={[{"Active", "active"}, {"Inactive", "inactive"}]}
                prompt="All statuses"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="site-modal"
        show
        on_cancel={
          if @back_path == ~p"/org/dashboard",
            do: JS.navigate(@back_path),
            else: JS.patch(@back_path)
        }
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          {if @live_action == :new, do: "Add a site", else: "Edit site"}
        </h2>
        <form id="site-form" phx-submit="save" phx-change="validate">
          <p class="text-xs text-base-content/60 mb-3">
            Fields marked <span class="text-error">*</span> are required.
          </p>
          <.input id="site-name" field={@form[:name]} label="Name" required />
          <.capability_select field={@form[:site_type]} options={capability_options()} required />
          <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 mb-3">
            <div>
              <p class="text-sm font-medium text-thamani-forest">Active</p>
              <p class="text-xs text-thamani-pewter">Enable this site</p>
            </div>
            <.input
              id="site-active"
              field={@form[:is_active]}
              type="checkbox"
              label=""
              class="size-5 rounded accent-thamani-forest cursor-pointer"
            />
          </div>
          <.input id="site-address" field={@form[:address]} label="Address" required />
          <div class="grid grid-cols-2 gap-2">
            <.input id="site-lat" field={@form[:lat]} label="Latitude" type="number" step="any" />
            <.input id="site-long" field={@form[:long]} label="Longitude" type="number" step="any" />
          </div>
          <div
            id="site-map"
            phx-hook="GoogleMaps"
            phx-update="ignore"
            data-lat-input="site-lat"
            data-lng-input="site-long"
            data-address-input="site-address"
            data-lat={@form[:lat].value}
            data-lng={@form[:long].value}
            class="w-full h-40 rounded-xl mt-1 overflow-hidden border border-thamani-stone bg-thamani-canvas"
          >
          </div>
          <div class="mt-2">
            <.button variant="primary" class="w-full">Save</.button>
          </div>
        </form>
      </.modal>

      <section id="sites" aria-label="Sites" class="space-y-3 sm:hidden">
        <article
          :for={site <- @sites}
          id={"site-card-#{site.id}"}
          class="group overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-snow shadow-[0_1px_3px_rgba(28,58,19,0.08)] transition-all duration-200"
        >
          <div class="p-4">
            <div class="flex items-start gap-3.5">
              <div class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-thamani-canvas text-thamani-forest ring-1 ring-thamani-stone transition-colors duration-200 group-hover:bg-thamani-lime/40">
                <.icon name="hero-building-office-2" class="size-6" />
              </div>
              <div class="min-w-0 flex-1 pt-0.5">
                <h2 class="truncate text-base font-semibold leading-6 text-thamani-forest">
                  {site.name}
                </h2>
                <p class="mt-0.5 text-sm text-thamani-pewter">
                  {Phoenix.Naming.humanize(site.site_type)}
                </p>
              </div>
              <.status_badge
                status={if site.is_active, do: :active, else: :inactive}
                class="shrink-0"
              />
            </div>

            <dl class="mt-4 grid grid-cols-2 border-t border-thamani-stone/80 pt-4">
              <div class="min-w-0 pr-4">
                <dt class="text-sm text-thamani-pewter">GLN</dt>
                <dd class="mt-1 truncate text-sm font-medium tabular-nums text-slate-900">
                  {site.gln}
                </dd>
              </div>
              <div class="min-w-0 border-l border-thamani-stone/80 pl-4">
                <dt class="text-sm text-thamani-pewter">Address</dt>
                <dd class="mt-1 line-clamp-2 text-sm font-medium leading-5 text-slate-900">
                  {site.address}
                </dd>
              </div>
            </dl>
          </div>

          <div class="grid grid-cols-2 gap-2 border-t border-thamani-stone bg-thamani-canvas/60 p-3">
            <.button
              variant="ghost"
              navigate={~p"/org/sites/#{site.id}"}
              class="min-h-10 gap-2 px-4 py-2 text-sm"
              id={"btn-view-site-#{site.id}"}
            >
              <.icon name="hero-eye" class="size-4" /> View
            </.button>
            <.button
              variant="ghost-edit"
              patch={~p"/org/sites/#{site.id}/edit"}
              class="min-h-10 gap-2 px-4 py-2 text-sm"
              id={"btn-edit-site-#{site.id}"}
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
          </div>
        </article>

        <div :if={@sites == []} id="sites-empty">
          <.blank_state
            icon="hero-building-office-2"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No sites match your search or filters",
                else: "No sites yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Sites you add to your organization will appear here."}
          </.blank_state>
        </div>
      </section>

      <div class="hidden sm:block">
        <.table
          id="sites-table"
          rows={@sites}
          row_id={fn site -> "site-row-#{site.id}" end}
          row_click={fn site -> JS.navigate(~p"/org/sites/#{site.id}") end}
        >
          <:col :let={site} label="Name">{site.name}</:col>
          <:col :let={site} label="Type">{Phoenix.Naming.humanize(site.site_type)}</:col>
          <:col :let={site} label="GLN"><span class="tabular-nums">{site.gln}</span></:col>
          <:col :let={site} label="Address">{site.address}</:col>
          <:col :let={site} label="Status" mobile="aside">
            <.status_badge status={if site.is_active, do: :active, else: :inactive} />
          </:col>
          <:action :let={site}>
            <.button
              variant="ghost"
              navigate={~p"/org/sites/#{site.id}"}
              class="min-h-10 gap-2 px-4 py-2 text-sm"
              id={"btn-view-site-desktop-#{site.id}"}
            >
              <.icon name="hero-eye" class="size-4" /> View
            </.button>
          </:action>
          <:action :let={site}>
            <.button
              variant="ghost-edit"
              patch={~p"/org/sites/#{site.id}/edit"}
              class="min-h-10 gap-2 px-4 py-2 text-sm"
              id={"btn-edit-site-desktop-#{site.id}"}
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
          </:action>
          <:empty_state>
            <.blank_state
              icon="hero-building-office-2"
              title={
                if @search != "" or active_filter_count(@filters) > 0,
                  do: "No sites match your search or filters",
                  else: "No sites yet"
              }
            >
              {if @search != "" or active_filter_count(@filters) > 0,
                do: "Try a different search term, or clear the applied filters.",
                else: "Sites you add to your organization will appear here."}
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <.pagination page={@page_info} path={~p"/org/sites"} />
    </Layouts.org_shell>
    """
  end
end
