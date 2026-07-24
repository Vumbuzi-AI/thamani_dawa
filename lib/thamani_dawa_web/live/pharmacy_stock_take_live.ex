defmodule ThamaniDawaWeb.PharmacyStockTakeLive do
  @moduledoc """
  Pharmacy-portal stock take: start, resume, review, and finalize a physical count at an
  allowed (pharmacy-capable) site. See `ThamaniDawa.StockTakes` for the domain logic and
  `ThamaniDawaWeb.StockTakeComponents` for the counting table shared with the lab portal.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.StockTakes
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    sites = organization_id |> Sites.list_sites() |> Enum.filter(&Site.pharmacy?/1)
    site_ids = MapSet.new(sites, & &1.id)
    home_site_id = SiteScoping.default_site_id(scope)

    stock_takes =
      organization_id
      |> StockTakes.list_stock_takes()
      |> Enum.filter(&MapSet.member?(site_ids, &1.site_id))

    {:ok,
     socket
     |> assign(:sites, sites)
     |> assign(:site_options, Enum.map(sites, &{&1.name, &1.id}))
     |> assign(:home_site_id, home_site_id)
     |> assign(:show_start_modal, false)
     |> assign(:show_finalize_modal, false)
     |> assign(:stock_takes, stock_takes)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :stock_take, nil)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    scope = socket.assigns.current_scope
    stock_take = StockTakes.get_stock_take!(scope.organization_id, id)
    authorize_site!(socket, scope, stock_take)

    load_show_assigns(socket, stock_take)
  end

  defp authorize_site!(socket, scope, stock_take) do
    home_site_id = SiteScoping.default_site_id(scope)
    site_ids = MapSet.new(socket.assigns.sites, & &1.id)

    site_locked_out? = home_site_id != nil and home_site_id != stock_take.site_id
    outside_portal? = not MapSet.member?(site_ids, stock_take.site_id)

    if site_locked_out? or outside_portal? do
      raise Ecto.NoResultsError, queryable: ThamaniDawa.StockTakes.StockTake
    end
  end

  defp load_show_assigns(socket, stock_take) do
    organization_id = socket.assigns.current_scope.organization_id

    batches_by_id =
      stock_take.entries
      |> Enum.map(& &1.batch_id)
      |> Enum.uniq()
      |> Enum.map(&Batches.get_batch!(organization_id, &1))
      |> Map.new(&{&1.id, &1})

    products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    socket
    |> assign(:stock_take, stock_take)
    |> assign(:batches_by_id, batches_by_id)
    |> assign(:products_by_id, products_by_id)
  end

  def handle_event("open_start_modal", _params, socket) do
    {:noreply, assign(socket, :show_start_modal, true)}
  end

  def handle_event("cancel_start", _params, socket) do
    {:noreply, assign(socket, :show_start_modal, false)}
  end

  def handle_event("start", %{"stock_take" => attrs}, socket) do
    scope = socket.assigns.current_scope
    site_id = resolve_site_id(socket, attrs)

    case site_id &&
           StockTakes.start_stock_take(scope.organization_id, site_id, scope.user.id, attrs) do
      {:ok, stock_take} ->
        {:noreply, push_navigate(socket, to: ~p"/pharmacy/stock-take/#{stock_take.id}")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "That site already has a stock take in progress.")}

      nil ->
        {:noreply, put_flash(socket, :error, "Choose a site.")}
    end
  end

  def handle_event("record_count", %{"entry_id" => entry_id} = params, socket) do
    scope = socket.assigns.current_scope

    case StockTakes.record_count(scope.organization_id, entry_id, scope.user.id, params) do
      {:ok, _entry} ->
        stock_take =
          StockTakes.get_stock_take!(scope.organization_id, socket.assigns.stock_take.id)

        {:noreply, load_show_assigns(socket, stock_take)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Enter a valid quantity.")}

      {:error, :not_draft} ->
        {:noreply, put_flash(socket, :error, "This stock take has already been finalized.")}
    end
  end

  def handle_event("open_finalize_modal", _params, socket) do
    {:noreply, assign(socket, :show_finalize_modal, true)}
  end

  def handle_event("cancel_finalize", _params, socket) do
    {:noreply, assign(socket, :show_finalize_modal, false)}
  end

  def handle_event("finalize", _params, socket) do
    scope = socket.assigns.current_scope
    stock_take = socket.assigns.stock_take

    case StockTakes.finalize_stock_take(scope.organization_id, stock_take.id, scope.user.id) do
      {:ok, completed, %{applied: applied, conflicted: conflicted}} ->
        {:noreply,
         socket
         |> assign(:show_finalize_modal, false)
         |> load_show_assigns(StockTakes.get_stock_take!(scope.organization_id, completed.id))
         |> put_flash(:info, finalize_message(applied, conflicted))}

      {:error, :not_draft} ->
        {:noreply, put_flash(socket, :error, "This stock take has already been finalized.")}
    end
  end

  defp resolve_site_id(socket, attrs) do
    case socket.assigns.home_site_id do
      nil -> attrs |> Map.get("site_id", "") |> parse_site_id()
      home_site_id -> home_site_id
    end
  end

  defp parse_site_id(""), do: nil

  defp parse_site_id(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp finalize_message(applied, []) do
    "Stock take finalized — #{length(applied)} #{plural(applied, "batch", "batches")} updated."
  end

  defp finalize_message(applied, conflicted) do
    "Stock take finalized — #{length(applied)} #{plural(applied, "batch", "batches")} updated, " <>
      "#{length(conflicted)} left uncounted for a follow-up recount because " <>
      "#{plural(conflicted, "its", "their")} stock changed while you were counting."
  end

  defp plural(list, singular, plural), do: if(length(list) == 1, do: singular, else: plural)

  defp counted_count(entries), do: Enum.count(entries, &(&1.counted_quantity != nil))

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock-take"
    >
      <.header icon="hero-clipboard-document-check">
        Stock take
        <:subtitle>Count physical stock at your site and reconcile it against the system.</:subtitle>
        <:actions>
          <.button
            :if={@live_action == :index}
            variant="primary"
            phx-click="open_start_modal"
          >
            + Start a stock take
          </.button>
          <.button :if={@live_action == :show} navigate={~p"/pharmacy/stock-take"}>
            Back
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@show_start_modal}
        id="start-stock-take-modal"
        show
        on_cancel={JS.push("cancel_start")}
      >
        <h2 class="font-semibold mb-2">Start a stock take</h2>
        <form id="start-stock-take-form" phx-submit="start">
          <.input
            :if={is_nil(@home_site_id)}
            type="select"
            name="stock_take[site_id]"
            label="Site"
            options={@site_options}
            prompt="Choose a site"
            required
          />
          <.input
            :if={!is_nil(@home_site_id)}
            type="text"
            name="site_name_readonly"
            label="Site"
            value={site_name(@sites, @home_site_id)}
            disabled
          />
          <.input type="textarea" name="stock_take[notes]" label="Notes (optional)" />
          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Starting...">Start</.button>
            <.button type="button" phx-click="cancel_start">Cancel</.button>
          </div>
        </form>
      </.modal>

      <div :if={@live_action == :index}>
        <.table id="stock-takes" rows={@stock_takes}>
          <:col :let={st} label="Site">{site_name(@sites, st.site_id)}</:col>
          <:col :let={st} label="Status">
            <.status_badge status={st.status} />
          </:col>
          <:col :let={st} label="Started">{Calendar.strftime(st.started_at, "%Y-%m-%d %H:%M")}</:col>
          <:action :let={st}>
            <.link navigate={~p"/pharmacy/stock-take/#{st.id}"} class="link">
              {if st.status == :draft, do: "Continue", else: "View"}
            </.link>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-clipboard-document-check" title="No stock takes yet">
              Start one to count physical stock at your site.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={@live_action == :show}>
        <div class="mb-4 flex flex-wrap items-center gap-3">
          <.status_badge status={@stock_take.status} />
          <span class="text-sm" style="color: var(--thamani-pewter);">
            {site_name(@sites, @stock_take.site_id)} · started {Calendar.strftime(
              @stock_take.started_at,
              "%Y-%m-%d %H:%M"
            )}
          </span>
        </div>
        <p :if={@stock_take.notes} class="mb-4 text-sm" style="color: var(--thamani-pewter);">
          {@stock_take.notes}
        </p>

        <ThamaniDawaWeb.StockTakeComponents.counting_table
          entries={@stock_take.entries}
          products_by_id={@products_by_id}
          batches_by_id={@batches_by_id}
          editable?={@stock_take.status == :draft}
        />

        <div :if={@stock_take.status == :draft} class="mt-4">
          <.button
            variant="primary"
            phx-click="open_finalize_modal"
            disabled={counted_count(@stock_take.entries) == 0}
          >
            Finalize stock take
          </.button>
        </div>

        <ThamaniDawaWeb.StockTakeComponents.finalize_confirmation_modal
          id="finalize-stock-take-modal"
          show={@show_finalize_modal}
          counted_count={counted_count(@stock_take.entries)}
          on_cancel={JS.push("cancel_finalize")}
        />
      </div>
    </Layouts.pharmacy_shell>
    """
  end

  defp site_name(sites, site_id) do
    case Enum.find(sites, &(&1.id == site_id)) do
      nil -> "—"
      site -> site.name
    end
  end
end
