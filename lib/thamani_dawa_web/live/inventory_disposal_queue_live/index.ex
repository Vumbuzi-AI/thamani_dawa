defmodule ThamaniDawaWeb.InventoryDisposalQueueLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites_by_id =
      organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:tabs, InventoryDisposals.tabs())
     |> assign(:filters, %{"status" => "pending"})
     |> assign(:tab_counts, InventoryDisposals.tab_counts([]))
     |> assign(:reject_disposal, nil)
     |> assign(:reject_form, nil)
     |> stream(:disposals, [])}
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
     |> load_disposals()}
  end

  defp load_disposals(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    filters = socket.assigns.filters

    all = InventoryDisposals.list_disposals(organization_id)
    disposals = InventoryDisposals.filter_by_tab(all, filters["status"])

    socket
    |> assign(:tab_counts, InventoryDisposals.tab_counts(all))
    |> stream(:disposals, disposals, reset: true)
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

    ~p"/org/disposals?#{query}"
  end

  defp apply_action(socket, :approve, _id), do: socket

  defp apply_action(socket, :reject, id) do
    organization_id = socket.assigns.current_scope.organization_id
    disposal = InventoryDisposals.get_disposal!(organization_id, id)

    socket
    |> assign(:reject_disposal, disposal)
    |> assign(:reject_form, to_form(%{"rejection_reason" => ""}, as: :reject))
  end

  defp apply_action(socket, :index, _id), do: socket

  defp apply_index(socket) do
    socket
    |> assign(:reject_disposal, nil)
    |> assign(:reject_form, nil)
  end

  def handle_event("clear_filter", %{"filter" => "status"}, socket) do
    {:noreply, push_patch(socket, to: filter_path(socket, %{"status" => "pending"}))}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    admin_id = socket.assigns.current_scope.user.id

    case InventoryDisposals.approve_disposal(organization_id, String.to_integer(id), admin_id) do
      {:ok, disposal} ->
        {:noreply,
         socket
         |> put_flash(:info, "Disposal approved. Batch quantities updated.")
         |> stream_insert(:disposals, reloaded(organization_id, disposal.id))
         |> push_patch(to: ~p"/org/disposals")}

      {:error, :not_approvable} ->
        {:noreply, put_flash(socket, :error, "That disposal can no longer be approved.")}
    end
  end

  def handle_event("reject", %{"reject" => %{"rejection_reason" => reason}}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    admin_id = socket.assigns.current_scope.user.id
    disposal = socket.assigns.reject_disposal

    case InventoryDisposals.reject_disposal(organization_id, disposal.id, admin_id, reason) do
      {:ok, rejected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Disposal rejected.")
         |> stream_insert(:disposals, reloaded(organization_id, rejected.id))
         |> push_patch(to: ~p"/org/disposals")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :reject_form, to_form(changeset, as: :reject))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't reject that disposal.")}
    end
  end

  defp reloaded(organization_id, disposal_id),
    do: InventoryDisposals.get_disposal!(organization_id, disposal_id)

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

  defp kind_label(:expiry), do: "Expiry"
  defp kind_label(:returned), do: "Returned"

  defp total_quantity_summary(items) do
    "#{length(items)} batch#{if length(items) == 1, do: "", else: "es"} · #{Enum.sum(Enum.map(items, & &1.quantity))} units"
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/disposals">
      <.td_list_page
        title="Disposals"
        subtitle="Expiry write-offs and supplier returns raised by your sites, awaiting review."
      >
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
          :if={@live_action == :reject and not is_nil(@reject_disposal)}
          id="reject-disposal-modal"
          show
          on_cancel={JS.patch(~p"/org/disposals")}
        >
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
            Reject disposal
          </h2>
          <.form for={@reject_form} id="reject-form" phx-submit="reject" class="flex flex-col gap-4">
            <.input field={@reject_form[:rejection_reason]} type="textarea" label="Reason" required />
            <.button variant="danger-confirm" phx-disable-with="Rejecting…" class="w-full">
              Reject disposal
            </.button>
          </.form>
        </.modal>

        <.table
          id="disposals"
          rows={@streams.disposals}
          row_click={fn {_id, d} -> JS.navigate(~p"/org/disposals/#{d.id}") end}
        >
          <:col :let={{_id, d}} label="Site">{site_name(@sites_by_id, d.site_id)}</:col>
          <:col :let={{_id, d}} label="Kind">{kind_label(d.kind)}</:col>
          <:col :let={{_id, d}} label="Type">{Phoenix.Naming.humanize(d.inventory_type)}</:col>
          <:col :let={{_id, d}} label="Requested by">{requester_label(d)}</:col>
          <:col :let={{_id, d}} label="Items">{total_quantity_summary(d.items)}</:col>
          <:col :let={{_id, d}} label="Status">
            <.status_badge status={d.status} />
          </:col>
          <:action :let={{_id, d}}>
            <div :if={d.status in [:draft, :pending]} class="flex gap-2">
              <.button type="button" variant="primary" phx-click="approve" phx-value-id={d.id}>
                Approve
              </.button>
              <.button
                :if={d.status == :pending}
                variant="ghost"
                patch={~p"/org/disposals/#{d.id}/reject"}
              >
                Reject
              </.button>
            </div>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-trash" title="No disposals yet">
              Expiry write-offs and supplier returns raised by sites will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </.td_list_page>
    </Layouts.org_shell>
    """
  end
end
