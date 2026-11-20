defmodule ThamaniDawaWeb.StockTakeQueueLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Sites
  alias ThamaniDawa.StockTakes

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites_by_id =
      organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:tabs, StockTakes.tabs())
     |> assign(:filters, %{"status" => "pending"})
     |> assign(:tab_counts, StockTakes.tab_counts([]))
     |> assign(:reject_stock_take, nil)
     |> assign(:reject_form, nil)
     |> stream(:stock_takes, [])}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, String.to_integer(id))}
  end

  def handle_params(params, _url, socket) do
    filters = %{"status" => params["status"] || "pending"}

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> apply_index()
     |> load_stock_takes()}
  end

  defp load_stock_takes(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    filters = socket.assigns.filters

    all = StockTakes.list_stock_takes(organization_id)
    stock_takes = StockTakes.filter_by_tab(all, filters["status"])

    socket
    |> assign(:tab_counts, StockTakes.tab_counts(all))
    |> stream(:stock_takes, stock_takes, reset: true)
  end

  defp filter_path(socket, changes) do
    socket.assigns.filters |> Map.merge(changes) |> build_path()
  end

  defp filter_path_for(filters, changes) do
    filters |> Map.merge(changes) |> build_path()
  end

  defp build_path(query) do
    query =
      query
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/org/stock-takes?#{query}"
  end

  defp apply_action(socket, :approve, _id), do: socket

  defp apply_action(socket, :reject, id) do
    organization_id = socket.assigns.current_scope.organization_id
    stock_take = StockTakes.get_stock_take!(organization_id, id)

    socket
    |> assign(:reject_stock_take, stock_take)
    |> assign(:reject_form, to_form(%{"rejection_reason" => ""}, as: :reject))
  end

  defp apply_action(socket, :index, _id), do: socket

  defp apply_index(socket) do
    socket
    |> assign(:reject_stock_take, nil)
    |> assign(:reject_form, nil)
  end

  def handle_event("clear_filter", %{"filter" => "status"}, socket) do
    {:noreply, push_patch(socket, to: filter_path(socket, %{"status" => "pending"}))}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    admin_id = socket.assigns.current_scope.user.id

    case StockTakes.approve_stock_take(organization_id, String.to_integer(id), admin_id) do
      {:ok, stock_take} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock take approved. Batch quantities updated.")
         |> stream_insert(:stock_takes, reloaded(organization_id, stock_take.id))
         |> push_patch(to: ~p"/org/stock-takes")}

      {:error, :not_approvable} ->
        {:noreply, put_flash(socket, :error, "That stock take can no longer be approved.")}
    end
  end

  def handle_event("reject", %{"reject" => %{"rejection_reason" => reason}}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    admin_id = socket.assigns.current_scope.user.id
    stock_take = socket.assigns.reject_stock_take

    case StockTakes.reject_stock_take(organization_id, stock_take.id, admin_id, reason) do
      {:ok, rejected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock take rejected.")
         |> stream_insert(:stock_takes, reloaded(organization_id, rejected.id))
         |> push_patch(to: ~p"/org/stock-takes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :reject_form, to_form(changeset, as: :reject))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't reject that stock take.")}
    end
  end

  defp reloaded(organization_id, stock_take_id),
    do: StockTakes.get_stock_take!(organization_id, stock_take_id)

  defp site_name(sites_by_id, site_id) do
    case Map.get(sites_by_id, site_id) do
      nil -> "—"
      site -> site.name
    end
  end

  defp person_name(nil), do: "—"
  defp person_name(user), do: user.name

  defp requester_label(%{admin_id: admin_id, admin: admin}) when not is_nil(admin_id),
    do: "#{person_name(admin)} (admin)"

  defp requester_label(%{requested_by: requested_by}), do: person_name(requested_by)

  defp counted_summary(items) do
    counted = Enum.count(items, &(not is_nil(&1.counted_quantity)))
    "#{counted}/#{length(items)} counted"
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/stock-takes">
      <.header icon="hero-clipboard-document-list">
        Stock takes
        <:subtitle>Physical inventory counts raised by your sites, awaiting review.</:subtitle>
      </.header>

      <nav class="mt-4 flex gap-2 border-b border-thamani-stone">
        <.link
          :for={{status, label} <- @tabs}
          patch={filter_path_for(@filters, %{"status" => status})}
          class={[
            "px-3 py-2 text-sm font-medium",
            if(@filters["status"] == status,
              do: "border-b-2 border-thamani-forest text-thamani-forest",
              else: "text-thamani-pewter hover:text-thamani-forest"
            )
          ]}
        >
          {label} ({@tab_counts[status]})
        </.link>
      </nav>

      <.modal
        :if={@live_action == :reject and not is_nil(@reject_stock_take)}
        id="reject-stock-take-modal"
        show
        on_cancel={JS.patch(~p"/org/stock-takes")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Reject stock take
        </h2>
        <.form for={@reject_form} id="reject-form" phx-submit="reject" class="flex flex-col gap-4">
          <.input field={@reject_form[:rejection_reason]} type="textarea" label="Reason" required />
          <.button variant="destructive" phx-disable-with="Rejecting…" class="w-full">
            Reject stock take
          </.button>
        </.form>
      </.modal>

      <.table
        id="stock-takes"
        rows={@streams.stock_takes}
        row_click={fn {_id, st} -> JS.navigate(~p"/org/stock-takes/#{st.id}") end}
      >
        <:col :let={{_id, st}} label="Site">{site_name(@sites_by_id, st.site_id)}</:col>
        <:col :let={{_id, st}} label="Type">{Phoenix.Naming.humanize(st.inventory_type)}</:col>
        <:col :let={{_id, st}} label="Requested by">{requester_label(st)}</:col>
        <:col :let={{_id, st}} label="Items">{counted_summary(st.items)}</:col>
        <:col :let={{_id, st}} label="Status">
          <.status_badge status={st.status} />
        </:col>
        <:action :let={{_id, st}}>
          <div :if={st.status in [:draft, :pending]} class="flex gap-2">
            <.button type="button" variant="primary" phx-click="approve" phx-value-id={st.id}>
              Approve
            </.button>
            <.button
              :if={st.status == :pending}
              variant="ghost"
              patch={~p"/org/stock-takes/#{st.id}/reject"}
            >
              Reject
            </.button>
          </div>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No stock takes yet">
            Stock takes raised by sites will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.org_shell>
    """
  end
end
