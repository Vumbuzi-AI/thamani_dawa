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

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Sites
        <:actions>
          <.button variant="primary" navigate={~p"/org/sites/new"}>+ Add site</.button>
        </:actions>
      </.header>

      <div :if={@live_action in [:new, :edit]} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">{if @live_action == :new, do: "Add a site", else: "Edit site"}</h2>
          <form phx-submit="save">
            <.input field={@form[:name]} label="Name" required />
            <.input
              field={@form[:site_type]}
              type="select"
              label="Type"
              options={Enum.map(Site.site_types(), &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose a type"
              required
            />
            <.input field={@form[:gln]} label="GLN" />
            <.input field={@form[:address]} label="Address" />
            <.input field={@form[:is_active]} type="checkbox" label="Active" />
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
    </Layouts.app_shell>
    """
  end
end
