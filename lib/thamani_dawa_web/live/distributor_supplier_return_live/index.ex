defmodule ThamaniDawaWeb.DistributorSupplierReturnLive.Index do
  @moduledoc """
  Supplier returns for a distributor warehouse: stock going back to the
  supplier, held until an admin approves it. Customer returns are the
  other tab on this page.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  @inventory_type :medicine
  @kind :returned

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    sites =
      scope
      |> Accounts.list_sites_for_user()
      |> Enum.filter(&Site.distribution?/1)

    {:ok,
     socket
     |> assign(:sites, sites)
     |> assign(:sites_by_id, scope.organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1}))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> apply_action(socket.assigns.live_action)
     |> reload_returns()}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    sites = socket.assigns.sites

    default_site_id =
      case sites do
        [single_site] -> single_site.id
        _ -> SiteScoping.default_site_id(scope)
      end

    assign(socket,
      form:
        to_form(
          InventoryDisposals.change_disposal(%InventoryDisposal{}, %{
            requested_by_id: scope.user.id,
            inventory_type: @inventory_type,
            kind: @kind,
            site_id: default_site_id
          }),
          as: :disposal
        )
    )
  end

  defp apply_action(socket, :index) do
    assign(socket, form: nil)
  end

  def handle_event("validate", %{"disposal" => attrs}, socket) do
    changeset =
      %InventoryDisposal{}
      |> InventoryDisposals.change_disposal(attrs)
      |> validate_site_access(socket.assigns.sites)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :disposal))}
  end

  def handle_event("save", %{"disposal" => attrs}, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    attrs =
      attrs
      |> Map.put_new("requested_by_id", to_string(scope.user.id))
      |> Map.put("inventory_type", to_string(@inventory_type))
      |> Map.put("kind", to_string(@kind))
      |> force_locked_site(socket.assigns.sites, scope)

    changeset =
      %InventoryDisposal{}
      |> InventoryDisposals.change_disposal(attrs)
      |> validate_site_access(socket.assigns.sites)

    if changeset.valid? do
      case InventoryDisposals.create_disposal(org_id, attrs) do
        {:ok, disposal} ->
          {:noreply,
           socket
           |> put_flash(:info, "Supplier return started.")
           |> push_navigate(to: ~p"/distributor/returns/#{disposal.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: :disposal))}
      end
    else
      {:noreply,
       assign(socket, form: to_form(Map.put(changeset, :action, :validate), as: :disposal))}
    end
  end

  defp validate_site_access(changeset, allowed_sites) do
    allowed_ids = Enum.map(allowed_sites, & &1.id)

    case Ecto.Changeset.get_field(changeset, :site_id) do
      nil ->
        changeset

      site_id ->
        if site_id in allowed_ids do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :site_id, "is not a site you can act on")
        end
    end
  end

  defp reload_returns(socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    returns =
      case SiteScoping.default_site_id(scope) do
        nil ->
          org_id
          |> InventoryDisposals.list_disposals()
          |> Enum.filter(&(&1.inventory_type == @inventory_type and &1.kind == @kind))

        site_id ->
          InventoryDisposals.list_disposals_for_site(org_id, site_id, @kind, @inventory_type)
      end

    stream(socket, :supplier_returns, returns, reset: true)
  end

  defp locked_site(sites, scope) do
    case Enum.find(sites, &(&1.id == scope.current_site_id)) do
      %Site{} = site -> site
      nil -> if length(sites) == 1, do: hd(sites), else: nil
    end
  end

  defp force_locked_site(attrs, sites, scope) do
    case locked_site(sites, scope) do
      nil -> attrs
      site -> Map.put(attrs, "site_id", to_string(site.id))
    end
  end

  defp site_name(sites_by_id, site_id) do
    case sites_by_id[site_id] do
      nil -> "—"
      site -> site.name
    end
  end

  defp continue_label(:draft), do: "Continue editing"
  defp continue_label(_status), do: "View"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/distributor/returns"
    >
      <.header icon="hero-arrow-uturn-left">
        Returns
        <:subtitle>
          Stock moving back to suppliers or in from customers, tracked through to approval.
        </:subtitle>
        <:actions>
          <.button id="new-supplier-return" variant="primary" patch={~p"/distributor/returns/new"}>
            <.icon name="hero-plus" class="size-4" /> New supplier return
          </.button>
        </:actions>
      </.header>

      <.returns_tabs active={:supplier} />

      <.modal
        :if={@live_action == :new}
        id="supplier-return-modal"
        show
        on_cancel={JS.patch(~p"/distributor/returns")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
          Start a supplier return
        </h2>
        <.form
          for={@form}
          id="supplier-return-form"
          phx-submit="save"
          phx-change="validate"
          class="mt-4"
        >
          <input type="hidden" name="disposal[requested_by_id]" value={@current_scope.user.id} />
          <input type="hidden" name="disposal[kind]" value="returned" />
          <%= if site = locked_site(@sites, @current_scope) do %>
            <.input field={@form[:site_id]} type="hidden" value={site.id} />
          <% else %>
            <.input
              field={@form[:site_id]}
              type="select"
              label="Warehouse"
              options={Enum.map(@sites, &{&1.name, &1.id})}
              prompt="Choose a warehouse"
              required
            />
          <% end %>
          <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />
          <div class="mt-4">
            <.button variant="primary" class="w-full">Start supplier return</.button>
          </div>
        </.form>
      </.modal>

      <.table id="supplier-returns" rows={@streams.supplier_returns}>
        <:col
          :let={{_id, d}}
          :if={is_nil(locked_site(@sites, @current_scope))}
          label="Warehouse"
        >
          {site_name(@sites_by_id, d.site_id)}
        </:col>
        <:col :let={{_id, d}} label="Status">
          <.status_badge status={d.status} />
        </:col>
        <:col :let={{_id, d}} label="Started">
          {Calendar.strftime(d.inserted_at, "%d %b %Y")}
        </:col>
        <:action :let={{_id, d}}>
          <.button variant="ghost" navigate={~p"/distributor/returns/#{d.id}"} class="gap-2">
            <.icon
              name={if d.status == :draft, do: "hero-pencil-square", else: "hero-eye"}
              class="size-4"
            />
            {continue_label(d.status)}
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-arrow-uturn-left" title="No supplier returns yet">
            Start one when stock is going back to the supplier.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.distributor_shell>
    """
  end
end
