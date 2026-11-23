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
     |> assign(:sites_by_id, scope.organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1}))
     |> assign(:return_count, 0)}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:status, if(params["status"] in ~w(draft pending approved rejected), do: params["status"], else: ""))
     |> assign(:search, params["search"] || "")
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

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, push_patch(socket, to: list_path(socket.assigns.status, search))}

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
           |> push_navigate(to: ThamaniDawaWeb.ReturnTo.with_query(~p"/distributor/returns/#{disposal.id}", ~p"/distributor/returns"))}

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

    counts = Enum.frequencies_by(returns, &Atom.to_string(&1.status))
    query = socket.assigns.search |> String.trim() |> String.downcase()

    shown =
      returns
      |> Enum.filter(&(socket.assigns.status == "" or Atom.to_string(&1.status) == socket.assigns.status))
      |> Enum.filter(&(query == "" or return_matches?(&1, query)))

    socket
    |> assign(:return_count, length(returns))
    |> assign(:status_counts, counts)
    |> assign(:shown_count, length(shown))
    |> stream(:supplier_returns, shown, reset: true)
  end

  defp return_matches?(disposal, query) do
    ["#{disposal.id}", "return ##{disposal.id}", return_supplier(disposal), disposal.reason, disposal.notes]
    |> Enum.concat(Enum.map(disposal.items, &(&1.batch && &1.batch.batch_no)))
    |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), query)))
  end

  defp return_supplier(%{items: items}) do
    items
    |> Enum.map(&(&1.batch && &1.batch.supplier && &1.batch.supplier.name))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> "—"
      [name] -> name
      names -> "#{length(names)} suppliers"
    end
  end

  defp return_units(%{items: items}), do: items |> Enum.map(&(&1.quantity || 0)) |> Enum.sum()

  defp list_path(status, search) do
    query = Enum.reject([{"status", status}, {"search", search}], fn {_k, v} -> v in [nil, ""] end)
    "/distributor/returns" <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  defp detail_path(d), do: ThamaniDawaWeb.ReturnTo.with_query(~p"/distributor/returns/#{d.id}", ~p"/distributor/returns")

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


  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/distributor/returns"
    >
      <div class="td-recipe td-list-page">
        <.td_page_header
          title="Supplier returns"
          subtitle="Stock going back to a supplier. Your organisation admin approves each return before the stock leaves."
        >
          <:actions :if={@return_count > 0}>
            <.td_button id="new-supplier-return" variant="primary" glyph="plus" patch={~p"/distributor/returns/new"} label="New supplier return" />
          </:actions>
        </.td_page_header>
      </div>
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

      <div class="td-list-page" id="supplier-returns-page">
        <nav class="td-tabs" aria-label="Supplier return status">
          <.td_tab id="sr-tab-all" label="All" count={@return_count} active={@status == ""} patch={list_path("", @search)} />
          <.td_tab
            :for={{status, label} <- [{"draft", "Draft"}, {"pending", "Awaiting approval"}, {"approved", "Approved"}, {"rejected", "Rejected"}]}
            id={"sr-tab-#{status}"}
            label={label}
            count={Map.get(@status_counts, status, 0)}
            active={@status == status}
            patch={list_path(status, @search)}
          />
        </nav>
        <div class="td-toolbar">
          <form id="supplier-return-search" phx-change="search" phx-submit="search" onsubmit="return false">
            <label class="td-search">
              <.td_icon name="magnifying-glass" />
              <input type="search" name="search" value={@search} placeholder="Search return, supplier or batch" phx-debounce="250" autocomplete="off" />
              <kbd>/</kbd>
            </label>
          </form>
          <span class="flex-1"></span>
        </div>

        <div :if={@shown_count == 0} id="supplier-returns-empty" class="td-pad td-empty-wrap">
          <div class="td-card td-empty-card">
            <%= if @return_count == 0 do %>
              <p class="td-empty-title">No supplier returns yet</p>
              <p class="td-note">Start one when stock is going back to a supplier, for example after a recall or a damaged delivery.</p>
              <.td_button id="new-supplier-return" variant="primary" label="New supplier return" patch={~p"/distributor/returns/new"} />
            <% else %>
              <p class="td-empty-title">Nothing matches</p>
              <p class="td-note">Try a different search, or another tab.</p>
              <.td_button id="supplier-returns-clear" patch={~p"/distributor/returns"} label="Clear filters" />
            <% end %>
          </div>
        </div>

        <div class="td-list-table" hidden={@shown_count == 0}>
          <table class="td-rows">
            <thead>
              <tr>
                <th>Return</th>
                <th>Supplier</th>
                <th :if={is_nil(locked_site(@sites, @current_scope))}>Warehouse</th>
                <th>Status</th>
                <th class="is-num">Batches</th>
                <th class="is-num">Units</th>
                <th>Created (EAT)</th>
                <th>Created by</th>
              </tr>
            </thead>
            <tbody id="supplier-returns" phx-update="stream">
              <tr :for={{dom_id, d} <- @streams.supplier_returns} id={dom_id} class="is-link" phx-click={JS.navigate(detail_path(d))}>
                <td>
                  <.link navigate={detail_path(d)} id={"#{dom_id}-open"}><b>Return #{d.id}</b></.link>
                  <span :if={d.reason} class="td-sub td-s12">{d.reason}</span>
                </td>
                <td>{return_supplier(d)}</td>
                <td :if={is_nil(locked_site(@sites, @current_scope))}>{site_name(@sites_by_id, d.site_id)}</td>
                <td><.status_badge status={d.status} /></td>
                <td class="is-num">{length(d.items)}</td>
                <td class="is-num">{return_units(d)}</td>
                <td>{ThamaniDawaWeb.TimeFormat.datetime(d.inserted_at)}</td>
                <td>
                  <.td_person_cell :if={d.requested_by} name={d.requested_by.name || d.requested_by.email} seed={d.requested_by.id} />
                  <span :if={!d.requested_by} class="td-sub">—</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.distributor_shell>
    """
  end
end
