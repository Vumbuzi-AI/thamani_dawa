defmodule ThamaniDawaWeb.DisposalLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.CarePortal
  alias ThamaniDawaWeb.SiteScoping

  defp inventory_type(socket), do: CarePortal.inventory_type(socket.assigns.portal)

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    sites =
      scope
      |> Accounts.list_sites_for_user()
      |> Enum.filter(&CarePortal.site?(socket.assigns.portal, &1))

    {:ok,
     socket
     |> assign(:sites, sites)
     |> assign(:sites_by_id, scope.organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1}))
     |> assign(:list_kind, "expiry")
     |> assign(:disposal_count, 0)}
  end

  def handle_params(params, _url, socket) do
    kind = if params["kind"] == "returned", do: "returned", else: "expiry"

    {:noreply,
     socket
     |> assign(:list_kind, kind)
     |> apply_action(socket.assigns.live_action, params)
     |> reload_disposals()}
  end

  defp apply_action(socket, :new, _params) do
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
            inventory_type: inventory_type(socket),
            site_id: default_site_id
          }),
          as: :disposal
        )
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil)
  end

  def handle_event("switch_kind", %{"tab" => kind}, socket) when kind in ["expiry", "returned"] do
    {:noreply,
     push_patch(socket, to: kind_path(socket.assigns.portal, socket.assigns.live_action, kind))}
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
      |> Map.put("inventory_type", to_string(inventory_type(socket)))
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
           |> put_flash(:info, "Disposal request started.")
           |> push_navigate(
             to:
               ThamaniDawaWeb.ReturnTo.with_query(
                 CarePortal.disposal(socket.assigns.portal, disposal.id),
                 kind_path(socket.assigns.portal, :index, socket.assigns.list_kind)
               )
           )}

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

  defp reload_disposals(socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    disposals =
      case SiteScoping.default_site_id(scope) do
        nil ->
          org_id
          |> InventoryDisposals.list_disposals()
          |> Enum.filter(
            &(&1.inventory_type == inventory_type(socket) and
                &1.kind == kind_atom(socket.assigns.list_kind))
          )

        site_id ->
          InventoryDisposals.list_disposals_for_site(
            org_id,
            site_id,
            kind_atom(socket.assigns.list_kind),
            inventory_type(socket)
          )
      end

    socket
    |> assign(:disposal_count, length(disposals))
    |> stream(:disposals, disposals, reset: true)
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

  defp kind_atom("returned"), do: :returned
  defp kind_atom(_kind), do: :expiry

  defp kind_path(portal, :new, kind), do: CarePortal.disposals_new(portal, kind)
  defp kind_path(portal, _live_action, kind), do: CarePortal.disposals_index(portal, kind)

  defp new_path(portal, kind), do: CarePortal.disposals_new(portal, kind)

  defp empty_title("returned"), do: "No supplier returns yet"
  defp empty_title(_kind), do: "No expiry write-offs yet"

  defp empty_body("returned"), do: "Start one when stock is going back to the supplier."
  defp empty_body(_kind), do: "Start one when a batch has passed its date."

  def render(assigns) do
    ~H"""
    <Layouts.care_shell
      portal={@portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={CarePortal.disposals(@portal)}
    >
      <.td_list_page title="Disposals" subtitle="Stock leaving this site, sent for approval.">
        <:actions>
          <.td_button
            :if={@disposal_count > 0}
            id="new-disposal"
            variant="primary"
            label="New disposal"
            glyph="plus"
            patch={new_path(@portal, @list_kind)}
          />
        </:actions>
        <:tabs>
          <button
            id="disposal-tab-expiry"
            type="button"
            role="tab"
            class={["td-tab", @list_kind == "expiry" && "is-active"]}
            phx-click="switch_kind"
            phx-value-tab="expiry"
            aria-selected={to_string(@list_kind == "expiry")}
          >
            Expiry write-off
          </button>
          <button
            id="disposal-tab-returned"
            type="button"
            role="tab"
            class={["td-tab", @list_kind == "returned" && "is-active"]}
            phx-click="switch_kind"
            phx-value-tab="returned"
            aria-selected={to_string(@list_kind == "returned")}
          >
            Supplier return
          </button>
        </:tabs>

        <.modal
          :if={@live_action == :new}
          id="disposal-modal"
          show
          on_cancel={JS.patch(kind_path(@portal, :index, @list_kind))}
        >
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
            {if @list_kind == "returned",
              do: "Start a supplier return",
              else: "Start an expiry write-off"}
          </h2>
          <.form for={@form} id="disposal-form" phx-submit="save" phx-change="validate" class="mt-4">
            <input type="hidden" name="disposal[requested_by_id]" value={@current_scope.user.id} />
            <input type="hidden" name="disposal[kind]" value={@list_kind} />
            <%= if site = locked_site(@sites, @current_scope) do %>
              <.input field={@form[:site_id]} type="hidden" value={site.id} />
            <% else %>
              <.input
                field={@form[:site_id]}
                type="select"
                label="Site"
                options={Enum.map(@sites, &{&1.name, &1.id})}
                prompt="Choose a site"
                required
              />
            <% end %>
            <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />
            <div class="mt-4">
              <.button variant="primary" class="w-full">Start disposal</.button>
            </div>
          </.form>
        </.modal>

        <.table id="disposals" rows={@streams.disposals}>
          <:col :let={{_id, d}} :if={is_nil(locked_site(@sites, @current_scope))} label="Site">
            {site_name(@sites_by_id, d.site_id)}
          </:col>
          <:col :let={{_id, d}} label="Status">
            <.status_badge status={d.status} />
          </:col>
          <:col :let={{_id, d}} label="Started">
            {ThamaniDawaWeb.TimeFormat.date(d.inserted_at)}
          </:col>
          <:action :let={{_id, d}}>
            <.button
              variant="ghost"
              navigate={
                ThamaniDawaWeb.ReturnTo.with_query(
                  CarePortal.disposal(@portal, d.id),
                  kind_path(@portal, :index, @list_kind)
                )
              }
              class="gap-2"
            >
              <.icon
                name={if d.status == :draft, do: "hero-pencil-square", else: "hero-eye"}
                class="size-4"
              />
              {continue_label(d.status)}
            </.button>
          </:action>
          <:empty_state>
            <div class="td-empty-state">
              <.td_icon name="trash" class="td-empty-state-icon" />
              <p class="td-empty-state-title">{empty_title(@list_kind)}</p>
              <p class="td-empty-state-text">{empty_body(@list_kind)}</p>
              <div class="td-empty-state-actions">
                <.td_button
                  id="new-disposal"
                  variant="primary"
                  label={
                    if @list_kind == "returned",
                      do: "Start a supplier return",
                      else: "Start an expiry write-off"
                  }
                  patch={new_path(@portal, @list_kind)}
                />
              </div>
            </div>
          </:empty_state>
        </.table>
      </.td_list_page>
    </Layouts.care_shell>
    """
  end
end
