defmodule ThamaniDawaWeb.StockTakeLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Sites
  alias ThamaniDawa.StockTakes
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    {:ok,
     socket
     |> assign(:sites_by_id, org_id |> Sites.list_sites() |> Map.new(&{&1.id, &1}))
     |> reload_stock_takes()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope

    assign(socket,
      form:
        to_form(
          StockTakes.change_stock_take(%StockTake{}, %{
            started_by_id: scope.user.id,
            site_id: SiteScoping.default_site_id(scope)
          }),
          as: :stock_take
        )
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil)
  end

  def handle_event("validate", %{"stock_take" => attrs}, socket) do
    changeset =
      %StockTake{}
      |> StockTakes.change_stock_take(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :stock_take))}
  end

  def handle_event("save", %{"stock_take" => attrs}, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    attrs = Map.put_new(attrs, "started_by_id", to_string(scope.user.id))

    case StockTakes.create_stock_take(org_id, attrs) do
      {:ok, stock_take} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock take started.")
         |> push_navigate(to: ~p"/pharmacy/stock-takes/#{stock_take.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :stock_take))}
    end
  end

  defp reload_stock_takes(socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    stock_takes =
      case SiteScoping.default_site_id(scope) do
        nil -> StockTakes.list_stock_takes(org_id)
        site_id -> StockTakes.list_stock_takes_for_site(org_id, site_id)
      end

    stream(socket, :stock_takes, stock_takes, reset: true)
  end

  defp site_name(sites_by_id, site_id) do
    case sites_by_id[site_id] do
      nil -> "—"
      site -> site.name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock-takes"
    >
      <.header icon="hero-clipboard-document-list">
        Stock takes
        <:subtitle>Count physical inventory and reconcile it with recorded stock.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/pharmacy/stock-takes/new"}>
            + New stock take
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="stock-take-modal"
        show
        on_cancel={JS.patch(~p"/pharmacy/stock-takes")}
      >
        <h2 class="mb-4 font-semibold text-slate-900">Start a new stock take</h2>
        <.form for={@form} id="stock-take-form" phx-submit="save" phx-change="validate">
          <input type="hidden" name="stock_take[started_by_id]" value={@current_scope.user.id} />
          <.input
            field={@form[:site_id]}
            type="select"
            label="Site"
            options={Enum.map(@sites_by_id, fn {id, site} -> {site.name, id} end)}
            prompt="Choose a site"
            required
          />
          <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />
          <div class="mt-4 flex gap-2">
            <.button variant="primary">Start counting</.button>
            <.button patch={~p"/pharmacy/stock-takes"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.table id="stock-takes" rows={@streams.stock_takes}>
        <:col :let={{_id, take}} label="Site">{site_name(@sites_by_id, take.site_id)}</:col>
        <:col :let={{_id, take}} label="Status">
          <.status_badge status={take.status} />
        </:col>
        <:col :let={{_id, take}} label="Notes">{take.notes || "—"}</:col>
        <:col :let={{_id, take}} label="Started">
          {Calendar.strftime(take.inserted_at, "%d %b %Y")}
        </:col>
        <:col :let={{_id, take}} label="Finalized">
          {if take.finalized_at,
            do: Calendar.strftime(take.finalized_at, "%d %b %Y"),
            else: "—"}
        </:col>
        <:action :let={{_id, take}}>
          <.button
            variant="ghost"
            navigate={~p"/pharmacy/stock-takes/#{take.id}"}
            class="gap-2"
          >
            <.icon
              name={if take.status == :draft, do: "hero-pencil-square", else: "hero-eye"}
              class="size-4"
            />
            {if take.status == :draft, do: "Continue counting", else: "View"}
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No stock takes yet">
            Start a stock take to count and reconcile your physical inventory.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
