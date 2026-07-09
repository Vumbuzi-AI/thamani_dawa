defmodule ThamaniDawaWeb.SiteLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  def mount(_params, _session, socket) do
    {:ok, assign_sites(socket)}
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
    assign(socket, :sites, Sites.list_sites(organization_id))
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
      <.header>
        Sites
        <:actions>
          <.button variant="primary" navigate={~p"/org/sites/new"}>+ Add site</.button>
        </:actions>
      </.header>

      <div :if={@live_action in [:new, :edit]} class="card bg-base-200 mb-4">
        <div class="card-body">
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
              <.button navigate={~p"/org/sites"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <.table id="sites" rows={@sites}>
        <:col :let={site} label="Name">{site.name}</:col>
        <:col :let={site} label="Type">{Phoenix.Naming.humanize(site.site_type)}</:col>
        <:col :let={site} label="GLN">{site.gln}</:col>
        <:col :let={site} label="Address">{site.address}</:col>
        <:col :let={site} label="Active">{if site.is_active, do: "Yes", else: "No"}</:col>
        <:action :let={site}>
          <.link navigate={~p"/org/sites/#{site.id}/edit"} class="link">Edit</.link>
        </:action>
      </.table>
    </Layouts.org_shell>
    """
  end
end
