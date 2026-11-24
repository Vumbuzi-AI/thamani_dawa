defmodule ThamaniDawaWeb.DistributorShipmentLive.Index do
  @moduledoc """
  Two views over the distributor's shipments (Doop "Flagship · Distributor"):

    * Orders (`/distributor/orders`, `BtVvvYcI0u`): drafts, submitted and
      rejected shipments, with New order as a modal (`oOLJEW6Y9i`).
    * Shipments (`/distributor/shipments`, `3qslZ7MTx3`): approved shipments
      ("Ready to dispatch") by default; the All shipments tab drops the filter.

  Tabs, search, the Customer and Packed by menus and the shared date filter
  all filter in place. IDs carry TD Peek cards. Lists refresh live when the
  mobile app or another tab changes a shipment.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Customers
  alias ThamaniDawa.Distributor
  alias ThamaniDawaWeb.{DateRangeFilter, SiteScoping, TimeFormat}

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  @order_statuses ["draft", "submitted", "rejected"]
  @filter_keys ["status", "search", "customer", "mobile_user_id", "date", "date_from", "date_to"]

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    if connected?(socket), do: Distributor.subscribe(organization_id)

    {:ok,
     socket
     |> assign(:mobile_users, Distributor.list_mobile_users(organization_id))
     |> assign(:customers, Customers.list_customers(organization_id))
     |> assign(:summaries, %{})
     |> stream(:shipments, [])}
  end

  # Old links to /distributor/shipments?status=draft|submitted|rejected now
  # live on Orders.
  def handle_params(
        %{"status" => status} = params,
        _url,
        %{assigns: %{live_action: :index}} = socket
      )
      when status in @order_statuses do
    {:noreply, push_navigate(socket, to: ~p"/distributor/orders?#{params}", replace: true)}
  end

  def handle_params(params, _url, socket) do
    mode = if socket.assigns.live_action in [:orders, :new], do: :orders, else: :shipments

    filters = %{
      "status" => valid_status(mode, params["status"]),
      "search" => params["search"] || "",
      "customer" => params["customer"] || "",
      "mobile_user_id" => params["mobile_user_id"] || "",
      "date" => DateRangeFilter.valid_preset(params["date"]),
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || ""
    }

    {:noreply,
     socket
     |> assign(:mode, mode)
     |> assign(:page_title, if(mode == :orders, do: "Orders", else: "Shipments"))
     |> assign(
       :base_path,
       if(mode == :orders, do: "/distributor/orders", else: "/distributor/shipments")
     )
     |> assign(:filters, filters)
     |> assign(:page, page_number(params))
     |> safe_load_shipments()}
  end

  def handle_event("retry_load", _params, socket), do: {:noreply, safe_load_shipments(socket)}

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}

  def handle_event("set_filter", %{"field" => field, "value" => value}, socket)
      when field in ["customer", "mobile_user_id", "status"],
      do: {:noreply, push_patch(socket, to: filter_path(socket, %{field => value}))}

  def handle_event("set_date_preset", %{"value" => value}, socket) do
    changes = %{"date" => value, "date_from" => "", "date_to" => ""}
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_event("apply_date_range", params, socket) do
    from = params["date_from"] || ""
    to = params["date_to"] || ""
    preset = if from == "" and to == "", do: "", else: "custom"
    changes = %{"date" => preset, "date_from" => from, "date_to" => to}
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_event("clear_filters", _params, socket) do
    changes = Map.new(@filter_keys -- ["status"], &{&1, ""})
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_info({:distributor_shipment, _event, _shipment_id}, socket),
    do: {:noreply, load_shipments(socket)}

  # A dropped database connection shows the "didn't load" state with Try
  # again instead of crashing the LiveView into a reconnect loop.
  defp safe_load_shipments(socket) do
    socket |> load_shipments() |> assign(:load_error, false)
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      require Logger
      Logger.warning("Distributor list failed to load: " <> Exception.message(error))

      socket
      |> assign(:load_error, true)
      |> assign(:counts, Map.new(ThamaniDawa.Distributor.Shipment.statuses(), &{&1, 0}))
      |> assign(:summaries, %{})
      |> assign(:page_info, %{total_entries: 0, page_number: 1, page_size: 25, total_pages: 1})
      |> stream(:shipments, [], reset: true)
  end

  defp load_shipments(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    %{filters: filters, mode: mode} = socket.assigns

    {from, to} =
      DateRangeFilter.resolve(filters["date"], filters["date_from"], filters["date_to"])

    status =
      cond do
        filters["status"] not in ["", "all"] -> filters["status"]
        mode == :orders -> @order_statuses
        filters["status"] == "all" -> nil
        true -> "approved"
      end

    date_opts =
      if mode == :orders,
        do: %{date_from: from, date_to: to},
        else: %{approved_from: from, approved_to: to}

    result =
      Distributor.list_shipments(
        organization_id,
        Map.merge(date_opts, %{
          status: status,
          search: filters["search"],
          destination_gln: filters["customer"],
          mobile_user_id: parse_id(filters["mobile_user_id"]),
          origin_site_id: SiteScoping.default_site_id(socket.assigns.current_scope),
          page: socket.assigns.page
        })
      )

    counts = Distributor.status_counts(organization_id)

    summaries =
      if mode == :orders,
        do:
          Distributor.destination_summaries(
            organization_id,
            Enum.map(result.entries, & &1.destination_gln)
          ),
        else: %{}

    socket
    |> assign(:counts, counts)
    |> assign(:summaries, summaries)
    |> assign(:page_info, Map.delete(result, :entries))
    |> stream(:shipments, result.entries, reset: true)
  end

  defp filter_path(socket, changes) do
    query =
      socket.assigns.filters
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    "#{socket.assigns.base_path}?#{URI.encode_query(query)}" |> String.trim_trailing("?")
  end

  defp tab_path(base_path, filters, status) do
    query =
      filters
      |> Map.put("status", status)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    if query == %{}, do: base_path, else: "#{base_path}?#{URI.encode_query(query)}"
  end

  defp pagination_path(base_path, filters), do: tab_path(base_path, filters, filters["status"])

  defp valid_status(:orders, status) when status in @order_statuses, do: status
  defp valid_status(:shipments, "all"), do: "all"
  defp valid_status(_mode, _status), do: ""

  defp page_number(params) do
    case Integer.parse(params["page"] || "1") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_id(value) do
    case Integer.parse(value || "") do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp filtered?(filters),
    do:
      Enum.any?(["search", "customer", "mobile_user_id", "date"], &(filters[&1] not in [nil, ""]))

  defp unit_count(shipment), do: shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum()

  defp holder(%{status: "draft", assigned_to: nil}), do: nil
  defp holder(%{status: "draft", assigned_to: mobile_user}), do: mobile_user
  defp holder(%{submitted_by: nil, assigned_to: mobile_user}), do: mobile_user
  defp holder(%{submitted_by: mobile_user}), do: mobile_user

  defp products(shipment) do
    shipment.shippers
    |> Enum.flat_map(fn shipper ->
      [shipper.product_name | Enum.map(shipper.items, & &1.product_name)]
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&(&1 |> String.split(" ") |> List.first()))
    |> Enum.uniq()
    |> case do
      [] -> "None yet"
      names -> Enum.join(names, ", ")
    end
  end

  defp order_badge(assigns) do
    {tone, label} =
      case assigns.status do
        "draft" -> {"neutral", "Draft"}
        "submitted" -> {"warning", "Submitted"}
        "approved" -> {"success", "Approved"}
        "rejected" -> {"danger", "Rejected"}
        other -> {"neutral", Phoenix.Naming.humanize(other)}
      end

    assigns = assign(assigns, tone: tone, label: label)

    ~H"""
    <.td_badge tone={@tone} label={@label} />
    """
  end

  defp status_long("draft"), do: "Draft"
  defp status_long("submitted"), do: "Submitted for approval"
  defp status_long("rejected"), do: "Rejected"
  defp status_long("approved"), do: "Approved"
  defp status_long(other), do: other

  defp customer_for(customers, gln), do: Enum.find(customers, &(&1.gln == gln))

  defp detail_path(shipment, mode),
    do:
      ~p"/distributor/shipments/#{shipment.id}?#{%{return_to: if(mode == :orders, do: "/distributor/orders", else: "/distributor/shipments")}}"

  defp short_time(nil), do: "—"
  defp short_time(value), do: TimeFormat.short_datetime(value)

  defp count_for(counts, statuses),
    do: statuses |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@base_path}
      crumb={@page_title}
    >
      <:search>
        <form
          id="distributor-shipment-search"
          phx-change="search"
          phx-submit="search"
          onsubmit="return false"
        >
          <.td_search
            name="search"
            value={@filters["search"]}
            placeholder={
              if @mode == :orders,
                do: "Search order number, customer, GLN or batch",
                else: "Search shipment, order, customer, SSCC or batch"
            }
            shortcut="⌘K"
            phx-debounce="250"
          />
        </form>
      </:search>
      <:tools>
        <.td_button
          id="new-distributor-shipment"
          variant="primary"
          label="New order"
          glyph="plus"
          patch={~p"/distributor/orders/new"}
        />
      </:tools>

      <section class="td-recipe td-list-page" id={"distributor-#{@mode}-page"}>
        <.td_page_header
          title={@page_title}
          subtitle={
            if @mode == :orders,
              do:
                "Customer orders your mobile team is packing or has sent for approval. Approving an order issues its SSCCs and turns it into a shipment.",
              else:
                "Approved orders with SSCCs issued. Print the shipper labels and dispatch documents from here."
          }
        />

        <nav class="td-tabs" aria-label={"#{@page_title} status"}>
          <%= if @mode == :orders do %>
            <.td_tab
              id="tab-all"
              label="All"
              count={count_for(@counts, ["draft", "submitted", "rejected"])}
              active={@filters["status"] == ""}
              patch={tab_path(@base_path, @filters, "")}
            />
            <.td_tab
              :for={
                {status, label} <- [
                  {"draft", "Draft"},
                  {"submitted", "Submitted"},
                  {"rejected", "Rejected"}
                ]
              }
              id={"tab-#{status}"}
              label={label}
              count={Map.get(@counts, status, 0)}
              active={@filters["status"] == status}
              patch={tab_path(@base_path, @filters, status)}
            />
          <% else %>
            <.td_tab
              id="tab-ready"
              label="Ready to dispatch"
              count={Map.get(@counts, "approved", 0)}
              active={@filters["status"] != "all"}
              patch={tab_path(@base_path, @filters, "")}
            />
            <.td_tab
              id="tab-all-shipments"
              label="All shipments"
              count={count_for(@counts, ["draft", "submitted", "approved", "rejected"])}
              active={@filters["status"] == "all"}
              patch={tab_path(@base_path, @filters, "all")}
            />
          <% end %>
        </nav>

        <div class="td-toolbar">
          <.td_filter_menu
            id="shipments"
            field="customer"
            label="Customer"
            value={@filters["customer"]}
            options={[{"", "Any"} | Enum.map(Enum.filter(@customers, & &1.gln), &{&1.gln, &1.name})]}
          />
          <.td_filter_menu
            :if={@mode == :orders}
            id="shipments"
            field="mobile_user_id"
            label="Packed by"
            value={@filters["mobile_user_id"]}
            options={[{"", "Anyone"} | Enum.map(@mobile_users, &{Integer.to_string(&1.id), &1.name})]}
          />
          <.td_date_filter
            id="shipments-date"
            label={if @mode == :orders, do: "Created", else: "Approved"}
            preset={@filters["date"]}
            date_from={@filters["date_from"]}
            date_to={@filters["date_to"]}
          />
          <span class="flex-1"></span>
        </div>

        <div :if={@page_info.total_entries == 0} id={"#{@mode}-empty"} class="td-pad td-empty-wrap">
          <div class="td-card td-empty-card">
            <%= cond do %>
              <% @load_error -> %>
                <p class="td-empty-title" id="list-load-error">
                  {if @mode == :orders, do: "Orders didn't load", else: "Shipments didn't load"}
                </p>
                <p class="td-note">
                  Thamani couldn't reach the server. Check your connection, then try again.
                </p>
                <.td_button id="retry-load" phx-click="retry_load" label="Try again" />
              <% filtered?(@filters) -> %>
                <p class="td-empty-title">Nothing matches</p>
                <p class="td-note">Try a different search, or clear the filters.</p>
                <.td_button id="clear-filters" phx-click="clear_filters" label="Clear filters" />
              <% @mode == :orders -> %>
                <p class="td-empty-title">No orders yet</p>
                <p class="td-note">
                  Record a customer order and your mobile team can start packing it.
                </p>
                <.td_button
                  id="empty-new-order"
                  patch={~p"/distributor/orders/new"}
                  label="New order"
                />
              <% true -> %>
                <p class="td-empty-title">Nothing ready to dispatch</p>
                <p class="td-note">
                  Approved orders appear here with their SSCCs, labels and dispatch documents.
                </p>
                <.td_button
                  id="empty-open-orders"
                  navigate={~p"/distributor/orders"}
                  label="Open orders"
                />
            <% end %>
          </div>
        </div>

        <div class="td-list-table" hidden={@page_info.total_entries == 0}>
          <table class="td-rows" id="distributor-shipments-table">
            <thead>
              <tr :if={@mode == :orders}>
                <th>Order</th>
                <th>Customer</th>
                <th>Status</th>
                <th class="is-num">Shippers / units</th>
                <th>Packed by</th>
                <th>Updated (EAT)</th>
              </tr>
              <tr :if={@mode == :shipments}>
                <th>Shipment</th>
                <th>Order</th>
                <th>Customer</th>
                <th class="is-num">SSCCs</th>
                <th class="is-num">Units</th>
                <th>Approved (EAT)</th>
                <th>Approved by</th>
              </tr>
            </thead>
            <tbody id="distributor-shipments" phx-update="stream">
              <tr
                :for={{dom_id, shipment} <- @streams.shipments}
                id={dom_id}
                class="is-link"
                phx-click={JS.navigate(detail_path(shipment, @mode))}
              >
                <%= if @mode == :orders do %>
                  <td>
                    <.td_pid id={"#{dom_id}-order"} label={shipment.order_number}>
                      <:peek>
                        <.td_peek
                          kind="Order"
                          title={shipment.order_number}
                          subtitle={
                            Enum.join(
                              Enum.reject(
                                [shipment.destination_company, shipment.destination_address],
                                &is_nil/1
                              ),
                              " · "
                            )
                          }
                        >
                          <:badge><.order_badge status={shipment.status} /></:badge>
                          <:row label="Shipment">{shipment.reference}</:row>
                          <:row label="Status">{status_long(shipment.status)}</:row>
                          <:row label="Shippers / units">
                            {length(shipment.shippers)} / {unit_count(shipment)}
                          </:row>
                          <:row label="Products">{products(shipment)}</:row>
                          <:row label="Packed by">
                            {(holder(shipment) && holder(shipment).name) || "Not started"}
                          </:row>
                          <:row :if={shipment.submitted_at} label="Submitted">
                            {TimeFormat.datetime(shipment.submitted_at)} EAT
                          </:row>
                          <:action>
                            <.td_button
                              navigate={detail_path(shipment, @mode)}
                              label="Open order"
                              glyph="arrow-right"
                            />
                          </:action>
                        </.td_peek>
                      </:peek>
                    </.td_pid>
                    <span class="td-sub td-s12">{shipment.reference}</span>
                  </td>
                  <td>
                    <.td_pid id={"#{dom_id}-customer"} label={shipment.destination_company || "—"}>
                      <:peek>
                        <.customer_peek
                          shipment={shipment}
                          customer={customer_for(@customers, shipment.destination_gln)}
                          summary={Map.get(@summaries, shipment.destination_gln)}
                        />
                      </:peek>
                    </.td_pid>
                    <span class="td-sub td-s12">{shipment.destination_address}</span>
                  </td>
                  <td><.order_badge status={shipment.status} /></td>
                  <td class="is-num">{length(shipment.shippers)} / {unit_count(shipment)}</td>
                  <td>
                    <.td_person_cell
                      :if={holder(shipment)}
                      name={holder(shipment).name}
                      seed={holder(shipment).id}
                    />
                    <span :if={!holder(shipment)} class="td-muted">Not started</span>
                  </td>
                  <td>{short_time(shipment.updated_at)}</td>
                <% else %>
                  <td>
                    <.td_pid id={"#{dom_id}-shipment"} label={shipment.reference}>
                      <:peek>
                        <.td_peek
                          kind="Shipment"
                          icon="truck"
                          title={shipment.reference}
                          subtitle={
                            Enum.join(
                              Enum.reject(
                                [shipment.destination_company, shipment.destination_address],
                                &is_nil/1
                              ),
                              " · "
                            )
                          }
                        >
                          <:badge><.order_badge status={shipment.status} /></:badge>
                          <:row label="Order">{shipment.order_number}</:row>
                          <:row label="SSCCs / units">
                            {length(shipment.shippers)} / {unit_count(shipment)}
                          </:row>
                          <:row label="Approved">
                            {if shipment.approved_at,
                              do: "#{TimeFormat.datetime(shipment.approved_at)} EAT",
                              else: "Not yet"}
                          </:row>
                          <:action>
                            <.td_button
                              navigate={detail_path(shipment, @mode)}
                              label="Open shipment"
                              glyph="arrow-right"
                            />
                          </:action>
                        </.td_peek>
                      </:peek>
                    </.td_pid>
                    <span :if={shipment.status != "approved"} class="td-sub"><.order_badge status={
                      shipment.status
                    } /></span>
                  </td>
                  <td>{shipment.order_number}</td>
                  <td>
                    {shipment.destination_company}
                    <span class="td-sub td-mono">{shipment.destination_gln}</span>
                  </td>
                  <td class="is-num">{length(shipment.shippers)}</td>
                  <td class="is-num">{unit_count(shipment)}</td>
                  <td>{short_time(shipment.approved_at)}</td>
                  <td>
                    <.td_person_cell
                      :if={shipment.approved_by}
                      name={shipment.approved_by.name || shipment.approved_by.email}
                      seed={shipment.approved_by.id}
                    />
                    <span :if={!shipment.approved_by} class="td-muted">—</span>
                  </td>
                <% end %>
              </tr>
            </tbody>
          </table>
          <div class="td-tfoot">
            <span>
              <b>{(@page_info.page_number - 1) * @page_info.page_size + 1} to {min(
                @page_info.page_number * @page_info.page_size,
                @page_info.total_entries
              )}</b>
              of {@page_info.total_entries} {if @mode == :orders, do: "orders", else: "shipments"}
            </span>
            <span :if={@page_info.total_pages > 1} class="td-tfoot-pager">
              <.link
                :if={@page_info.page_number > 1}
                class="td-icon-btn"
                patch={
                  pagination_path(@base_path, Map.put(@filters, "page", @page_info.page_number - 1))
                }
                aria-label="Previous page"
              ><.td_icon name="caret-left" /></.link>
              <.link
                :if={@page_info.page_number < @page_info.total_pages}
                class="td-icon-btn"
                patch={
                  pagination_path(@base_path, Map.put(@filters, "page", @page_info.page_number + 1))
                }
                aria-label="Next page"
              ><.td_icon name="caret-right" /></.link>
            </span>
          </div>
        </div>
      </section>

      <.live_component
        :if={@live_action == :new}
        module={ThamaniDawaWeb.DistributorShipmentLive.OrderFormComponent}
        id="new-order"
        action={:new}
        current_scope={@current_scope}
        cancel={~p"/distributor/orders"}
      />
    </Layouts.distributor_shell>
    """
  end

  attr :shipment, :map, required: true
  attr :customer, :any, default: nil
  attr :summary, :any, default: nil

  defp customer_peek(assigns) do
    ~H"""
    <.td_peek
      kind="Customer"
      icon="address-book"
      title={@shipment.destination_company || @shipment.destination_gln}
      subtitle={@shipment.destination_address}
    >
      <:badge>
        <.td_badge :if={@customer} tone="success" label="Saved" />
        <.td_badge :if={!@customer} tone="neutral" label="Not saved" />
      </:badge>
      <:row label="GLN" mono>{@shipment.destination_gln}</:row>
      <:row label="Open orders">{(@summary && @summary.open_orders) || 0}</:row>
      <:row label="Last shipment">
        {if @summary && @summary.last_shipment,
          do:
            "#{@summary.last_shipment.reference}, #{TimeFormat.date(@summary.last_shipment.approved_at)}",
          else: "None yet"}
      </:row>
      <:row :if={@customer && @customer.contact_phone} label="Contact">
        {@customer.contact_phone}
      </:row>
      <:action>
        <.td_button
          :if={@customer}
          navigate={~p"/distributor/customers?#{%{selected: @customer.id}}"}
          label="Open customer"
          glyph="arrow-right"
        />
      </:action>
    </.td_peek>
    """
  end
end
