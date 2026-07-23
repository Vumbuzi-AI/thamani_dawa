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
     |> assign_sites()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, form: to_form(Site.changeset(%Site{}, %{}), as: :site), site: nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    organization_id = socket.assigns.current_scope.organization_id
    site = Sites.get_site!(organization_id, id)
    assign(socket, form: to_form(Site.changeset(site, %{}), as: :site), site: site)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, site: nil)
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
        {:noreply,
         socket
         |> put_flash(:info, "Site created.")
         |> assign_sites()
         |> push_patch(to: ~p"/org/sites")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp save_site(socket, :edit, attrs) do
    case Sites.update_site(socket.assigns.site, attrs) do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site updated.")
         |> assign_sites()
         |> push_patch(to: ~p"/org/sites")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp assign_sites(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites =
      organization_id
      |> Sites.list_sites()
      |> filter_by_search(socket.assigns.search)
      |> filter_by_type(socket.assigns.filters.site_type)
      |> filter_by_status(socket.assigns.filters.status)

    assign(socket, :sites, sites)
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
          <.button variant="primary" patch={~p"/org/sites/new"}>+ Add site</.button>
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
        on_cancel={JS.patch(~p"/org/sites")}
      >
        <h2 class="font-semibold mb-2">
          {if @live_action == :new, do: "Add a site", else: "Edit site"}
        </h2>
        <form id="site-form" phx-submit="save" phx-change="validate">
          <p class="text-xs text-base-content/60 mb-3">
            Fields marked <span class="text-error">*</span> are required.
          </p>
          <.input id="site-name" field={@form[:name]} label="Name" required />
          <.input id="site-gln" field={@form[:gln]} label="GLN" required />
          <.input id="site-address" field={@form[:address]} label="Address" required />
          <.capability_select field={@form[:site_type]} options={capability_options()} required />
          <.input id="site-active" field={@form[:is_active]} type="checkbox" label="Active" />
          <div class="grid grid-cols-2 gap-2">
            <.input id="site-lat" field={@form[:lat]} label="Latitude" type="number" step="any" />
            <.input id="site-long" field={@form[:long]} label="Longitude" type="number" step="any" />
          </div>
          <div class="flex gap-2 mt-2">
            <.button variant="primary">Save</.button>
            <.button patch={~p"/org/sites"}>Cancel</.button>
          </div>
        </form>
      </.modal>

      <.table
        id="sites"
        rows={@sites}
        row_click={fn site -> JS.navigate(~p"/org/sites/#{site.id}") end}
      >
        <:col :let={site} label="Name">{site.name}</:col>
        <:col :let={site} label="Type">{Phoenix.Naming.humanize(site.site_type)}</:col>
        <:col :let={site} label="GLN">{site.gln}</:col>
        <:col :let={site} label="Address">{site.address}</:col>
        <:col :let={site} label="Active">{if site.is_active, do: "Yes", else: "No"}</:col>
        <:action :let={site}>
          <.link patch={~p"/org/sites/#{site.id}/edit"} class="link">Edit</.link>
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
    </Layouts.org_shell>
    """
  end
end
