defmodule ThamaniDawaWeb.DistributorDisposalLive.Index do
  @moduledoc """
  Expiry write-offs for a distributor warehouse. A request lists past-date
  lots and does not move stock until an admin approves it.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Batches
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  @inventory_type :medicine
  @kind :expiry

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
    socket =
      socket
      |> assign_expired_stock()
      |> apply_action(socket.assigns.live_action)
      |> reload_write_offs()

    socket =
      if socket.assigns.live_action == :new and not socket.assigns.expired_stock? do
        socket
        |> put_flash(:error, "No expired stock at this warehouse.")
        |> push_patch(to: ~p"/distributor/expiry-write-offs")
      else
        socket
      end

    {:noreply, socket}
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
    if not socket.assigns.expired_stock? do
      {:noreply, put_flash(socket, :error, "No expired stock at this warehouse.")}
    else
      save_write_off(socket, attrs)
    end
  end

  defp save_write_off(socket, attrs) do
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
           |> put_flash(:info, "Write-off started. Add the expired lots.")
           |> push_navigate(to: ~p"/distributor/expiry-write-offs/#{disposal.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: :disposal))}
      end
    else
      {:noreply,
       assign(socket, form: to_form(Map.put(changeset, :action, :validate), as: :disposal))}
    end
  end

  defp assign_expired_stock(socket) do
    assign(
      socket,
      :expired_stock?,
      Batches.any_expired_on_hand?(
        socket.assigns.current_scope.organization_id,
        write_off_site_ids(socket),
        @inventory_type
      )
    )
  end

  defp write_off_site_ids(socket) do
    case locked_site(socket.assigns.sites, socket.assigns.current_scope) do
      %Site{id: id} -> [id]
      nil -> Enum.map(socket.assigns.sites, & &1.id)
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

  defp reload_write_offs(socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    write_offs =
      case SiteScoping.default_site_id(scope) do
        nil ->
          org_id
          |> InventoryDisposals.list_disposals()
          |> Enum.filter(&(&1.inventory_type == @inventory_type and &1.kind == @kind))

        site_id ->
          InventoryDisposals.list_disposals_for_site(org_id, site_id, @kind, @inventory_type)
      end

    stream(socket, :write_offs, write_offs, reset: true)
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
      current_path="/distributor/expiry-write-offs"
    >
      <.header icon="hero-calendar-days">
        Expiry write-off
        <:subtitle>Past-date stock. Nothing leaves the warehouse until this is approved.</:subtitle>
        <:actions>
          <.button
            id="new-write-off"
            variant="primary"
            disabled={!@expired_stock?}
            patch={@expired_stock? && ~p"/distributor/expiry-write-offs/new"}
          >
            <.icon name="hero-plus" class="size-4" /> New write-off
          </.button>
        </:actions>
      </.header>

      <p
        :if={!@expired_stock?}
        id="no-expired-stock"
        role="status"
        class="mb-5 rounded-xl bg-amber-50 px-4 py-3 text-sm font-medium text-amber-950"
      >
        No expired stock at this warehouse. A write-off starts from a lot that has passed its date.
      </p>

      <.modal
        :if={@live_action == :new}
        id="write-off-modal"
        show
        on_cancel={JS.patch(~p"/distributor/expiry-write-offs")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
          Start an expiry write-off
        </h2>
        <p class="mt-1 text-sm text-thamani-pewter">
          Add the expired lots next. Each lot is written off in full, after approval.
        </p>
        <.form for={@form} id="write-off-form" phx-submit="save" phx-change="validate" class="mt-4">
          <input type="hidden" name="disposal[requested_by_id]" value={@current_scope.user.id} />
          <input type="hidden" name="disposal[kind]" value="expiry" />
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
            <.button variant="primary" class="w-full">Start write-off</.button>
          </div>
        </.form>
      </.modal>

      <.table id="write-offs" rows={@streams.write_offs}>
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
          <.button variant="ghost" navigate={~p"/distributor/expiry-write-offs/#{d.id}"} class="gap-2">
            <.icon
              name={if d.status == :draft, do: "hero-pencil-square", else: "hero-eye"}
              class="size-4"
            />
            {continue_label(d.status)}
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-calendar-days" title="No expiry write-offs yet">
            {if @expired_stock?,
              do: "Start one for a lot that has passed its date.",
              else: "Nothing to write off until a lot passes its date."}
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.distributor_shell>
    """
  end
end
