defmodule ThamaniDawaWeb.SiteLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 30

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site = Sites.get_site!(organization_id, id)

    socket =
      socket
      |> assign(:site, site)
      |> assign(:near_expiry_days, @near_expiry_days)
      |> assign(:staff, Accounts.list_users_for_site(organization_id, site.id))
      |> assign_range("today")
      |> load_pharmacy(organization_id, site)
      |> load_lab(organization_id, site)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply, assign(socket, :tab, tab_from_params(params, socket.assigns.site))}
  end

  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign_range(socket, range)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = socket.assigns.site.id
    dates = socket.assigns.dates

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_active, true)
     |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, query))
     |> assign(
       :search_results,
       Dashboards.search_admin_dashboard(organization_id, query, dates, site_id)
     )}
  end

  def handle_event("activate_search", _params, socket) do
    {:noreply, assign(socket, :search_active, true)}
  end

  def handle_event("dismiss_search", _params, socket) do
    {:noreply, assign(socket, :search_active, false)}
  end

  def handle_event("clear_search", _params, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = socket.assigns.site.id
    dates = socket.assigns.dates

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_active, false)
     |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, ""))
     |> assign(:search_results, %{patients: [], sites: [], staff: [], visits: []})}
  end

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :show_filters, &(!&1))}
  end

  def handle_event("reset_filters", _params, socket) do
    {:noreply, assign_range(socket, "this_month")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, assign_range(socket, "this_month")}
  end

  def handle_event("apply_custom_range", %{"from" => from_str, "to" => to_str}, socket) do
    with {:ok, from_date} <- parse_date(from_str),
         {:ok, to_date} <- parse_date(to_str) do
      dates = Dashboards.custom_range_dates(from_date, to_date)
      scope = socket.assigns.current_scope
      organization_id = scope.organization_id
      site_id = socket.assigns.site.id
      search_query = socket.assigns.search_query

      {:noreply,
       socket
       |> assign(:range, "custom")
       |> assign(:dates, dates)
       |> assign(:show_filters, false)
       |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, search_query))
       |> assign(
         :search_results,
         Dashboards.search_admin_dashboard(organization_id, search_query, dates, site_id)
       )
       |> assign(
         :daily_revenue,
         Dashboards.daily_revenue(organization_id, site_id, elem(dates, 0), elem(dates, 1))
       )
       |> assign(:monthly_revenue, Dashboards.monthly_revenue(organization_id, site_id))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Enter a valid from and to date")}
    end
  end

  def handle_event("apply_custom_range", _params, socket) do
    {:noreply, put_flash(socket, :error, "Enter a valid from and to date")}
  end

  defp tab_from_params(%{"tab" => "lab"}, site),
    do: if(Site.lab?(site), do: :lab, else: default_tab(site))

  defp tab_from_params(%{"tab" => "pharmacy"}, site),
    do: if(Site.pharmacy?(site), do: :pharmacy, else: default_tab(site))

  defp tab_from_params(_params, site), do: default_tab(site)

  defp default_tab(site) do
    cond do
      Site.pharmacy?(site) -> :pharmacy
      Site.lab?(site) -> :lab
      true -> nil
    end
  end

  defp assign_range(socket, range) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = socket.assigns.site.id
    dates = Dashboards.range_dates(range)
    search_query = Map.get(socket.assigns, :search_query, "")

    socket
    |> assign(:range, range)
    |> assign(:dates, dates)
    |> assign(:show_filters, false)
    |> assign(:search_query, search_query)
    |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, search_query))
    |> assign(
      :search_results,
      Dashboards.search_admin_dashboard(organization_id, search_query, dates, site_id)
    )
    |> assign(
      :daily_revenue,
      Dashboards.daily_revenue(organization_id, site_id, elem(dates, 0), elem(dates, 1))
    )
    |> assign(:monthly_revenue, Dashboards.monthly_revenue(organization_id, site_id))
  end

  defp parse_date(date_str) when is_binary(date_str) do
    cond do
      date_str == "" ->
        {:error, :empty}

      String.match?(date_str, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        Date.from_iso8601(date_str)

      String.match?(date_str, ~r/^\d{2}\/\d{2}\/\d{4}$/) ->
        case String.split(date_str, "/") do
          [m, d, y] -> Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d))
          _ -> {:error, :invalid}
        end

      true ->
        Date.from_iso8601(date_str)
    end
  end

  defp parse_date(%Date{} = d), do: {:ok, d}
  defp parse_date(_), do: {:error, :invalid}

  defp format_range_dates({from, to}) do
    "Granular view for #{Calendar.strftime(from, "%d %b %Y")} to #{Calendar.strftime(to, "%d %b %Y")}"
  end

  defp to_date_val(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date_val(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date_val(%Date{} = d), do: d

  defp money(amount) do
    grouped =
      amount
      |> round()
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "KSh " <> grouped
  end

  defp combined_search_items(results) do
    patients =
      Enum.map(Map.get(results, :patients, []), fn p ->
        %{
          type: :patient,
          title: p.full_name,
          subtitle: "Phone: #{p.phone} • DOB: #{p.date_of_birth}",
          badge: "GSRN: #{p.gsrn}",
          icon: "hero-user"
        }
      end)

    staff =
      Enum.map(Map.get(results, :staff, []), fn u ->
        %{
          type: :staff,
          title: u.name,
          subtitle: u.email,
          badge: String.capitalize(to_string(u.role)),
          icon: "hero-users"
        }
      end)

    visits =
      Enum.map(Map.get(results, :visits, []), fn v ->
        %{
          type: :visit,
          title: v.patient_name,
          subtitle: "Date: #{Calendar.strftime(to_date_val(v.inserted_at), "%d %b %Y")}",
          badge: String.capitalize(to_string(v.visit_type)),
          icon: "hero-document-text"
        }
      end)

    patients ++ staff ++ visits
  end

  defp daily_revenue_chart_data(daily_revenue) do
    %{
      labels: Enum.map(daily_revenue, fn {date, _amount} -> Calendar.strftime(date, "%d %b") end),
      datasets: [
        %{
          label: "KSh Collected",
          data: Enum.map(daily_revenue, fn {_date, amount} -> amount end),
          borderColor: "#1c3a13",
          backgroundColor: "rgba(28, 58, 19, 0.14)",
          fill: true,
          tension: 0.3,
          pointRadius: 3
        }
      ]
    }
  end

  defp monthly_revenue_chart_data(monthly_revenue) do
    %{
      labels: Enum.map(monthly_revenue, fn {date, _n} -> Calendar.strftime(date, "%b %Y") end),
      datasets: [
        %{
          label: "Revenue",
          data: Enum.map(monthly_revenue, fn {_date, n} -> n end),
          backgroundColor: "#757c5d",
          borderRadius: 4
        }
      ]
    }
  end

  defp chart_options do
    %{
      responsive: true,
      maintainAspectRatio: false,
      plugins: %{legend: %{display: false}},
      scales: %{y: %{beginAtZero: true}}
    }
  end

  defp load_pharmacy(socket, organization_id, site) do
    if Site.pharmacy?(site) do
      products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})
      batches = Batches.list_active_batches_for_site(organization_id, site.id)

      pending_prescriptions =
        organization_id
        |> Prescriptions.list_prescriptions()
        |> SiteScoping.for_site(site.id)
        |> Enum.filter(&(&1.status in [:pending, :partially_dispensed]))

      socket
      |> assign(:products_by_id, products_by_id)
      |> assign(:low_stock, low_stock(batches, products_by_id))
      |> assign(:near_expiry, near_expiry(batches))
      |> assign(:pending_prescriptions, pending_prescriptions)
    else
      socket
    end
  end

  defp load_lab(socket, organization_id, site) do
    if Site.lab?(site) do
      lab_orders =
        organization_id
        |> LabOrders.list_lab_orders_with_patient()
        |> SiteScoping.for_site(site.id)

      socket
      |> assign(:pending_orders, Enum.filter(lab_orders, &(&1.status == :pending)))
      |> assign(
        :incomplete_orders,
        Enum.filter(lab_orders, &(&1.status in [:pending, :in_progress]))
      )
    else
      socket
    end
  end

  defp low_stock(batches, products_by_id) do
    batches
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_batches} ->
      {products_by_id[product_id], Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
    end)
    |> Enum.filter(fn {product, total} ->
      product && product.reorder_level && total <= product.reorder_level
    end)
  end

  defp near_expiry(batches) do
    today = Date.utc_today()

    batches
    |> Enum.filter(&(Date.diff(&1.expiry_date, today) in 0..@near_expiry_days))
    |> Enum.sort_by(& &1.expiry_date, Date)
  end

  defp product_name(products_by_id, product_id) do
    product_display_name(products_by_id[product_id])
  end

  defp product_display_name(nil), do: "(unknown product)"

  defp product_display_name(product),
    do: product.generic_name || product.brand_name || "(unnamed)"

  defp patient_name(%{patient_visit: %{patient: patient}}) when not is_nil(patient),
    do: patient.full_name

  defp patient_name(_lab_order), do: "(unknown patient)"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/sites"}
      back={~p"/org/sites"}
    >
      <%!-- Granular Site Header Dashboard Card --%>
      <div class="relative ff-surface-card rounded-3xl p-6 sm:p-8 mb-6">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
              <h1 class="text-2xl sm:text-3xl font-medium text-slate-900 tracking-tight">
                {@site.name}
              </h1>
              <span class="px-3 py-1 text-xs font-medium bg-thamani-lime text-thamani-forest rounded-full border border-thamani-forest/10 capitalize">
                {Phoenix.Naming.humanize(@site.site_type)}
              </span>
            </div>
            <p class="text-xs sm:text-sm text-slate-500 font-normal mt-1.5">
              {@site.address || "No address specified"} · {format_range_dates(@dates)}
            </p>
          </div>

          <div class="flex flex-col items-end gap-3 shrink-0">
            <.button
              navigate={~p"/org/sites/#{@site.id}/edit"}
              class="!rounded-xl text-xs font-medium"
            >
              Edit site
            </.button>
            <.range_filter event="set_range" current={@range} ranges={Dashboards.ranges()} />
          </div>
        </div>

        <%!-- Fixed backdrop blur overlay when search popover is active --%>
        <div
          :if={
            @search_query != "" and String.trim(@search_query) != "" and
              Map.get(assigns, :search_active, true)
          }
          class="fixed inset-0 z-30 bg-black/15 backdrop-blur-sm transition-opacity"
          phx-click="dismiss_search"
        />

        <%!-- Search & Filters row --%>
        <div class="mt-6 flex flex-col sm:flex-row items-center gap-3 w-full">
          <div class="relative flex-1 w-full">
            <input
              type="text"
              name="search"
              value={@search_query}
              phx-keyup="search"
              phx-focus="activate_search"
              phx-click="activate_search"
              phx-debounce="250"
              placeholder={"Search patients, visits, revenue or reports at #{@site.name}..."}
              class="thamani-input relative z-40 w-full rounded-xl px-4 py-2.5 text-sm placeholder:text-thamani-pewter/60 focus:border-thamani-forest focus:outline-none focus:ring-0 transition-colors"
            />

            <%!-- Search Results Popover --%>
            <div
              :if={
                @search_query != "" and String.trim(@search_query) != "" and
                  Map.get(assigns, :search_active, true)
              }
              class="absolute left-0 right-0 top-full z-40 mt-2 rounded-2xl p-4 space-y-3 max-h-[460px] overflow-y-auto ff-surface-popover"
            >
              <div class="flex items-center justify-between border-b border-thamani-stone pb-2.5">
                <div class="flex items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-4 text-thamani-forest" />
                  <span class="text-xs font-medium text-thamani-forest uppercase tracking-wider">
                    Search hits at {@site.name} for "{@search_query}"
                  </span>
                </div>
                <div class="flex items-center gap-3">
                  <button
                    type="button"
                    phx-click="clear_search"
                    class="text-xs font-medium text-thamani-forest hover:underline cursor-pointer"
                  >
                    Clear search
                  </button>
                  <button
                    type="button"
                    phx-click="dismiss_search"
                    class="text-xs font-medium text-thamani-pewter hover:text-thamani-forest cursor-pointer"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>

              <div class="text-xs text-thamani-pewter bg-thamani-stone/50 p-2.5 rounded-lg border border-thamani-stone flex items-center justify-between">
                <span>Site metrics below filtered for "{@search_query}"</span>
                <span class="font-medium text-thamani-forest">
                  {@stats.total_patients} patients • {@stats.patient_visits} visits • {money(
                    @stats.revenue_collected
                  )}
                </span>
              </div>

              <%!-- Unified Flat Search Items List --%>
              <% items = combined_search_items(@search_results) %>
              <div
                :if={items != []}
                class="divide-y divide-thamani-stone/60 rounded-xl ff-surface-card"
              >
                <div
                  :for={item <- items}
                  class="p-3 hover:bg-thamani-stone/40 transition-colors flex items-center justify-between gap-3"
                >
                  <div class="flex items-center gap-3 min-w-0">
                    <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-thamani-stone text-thamani-forest">
                      <.icon name={item.icon} class="size-4" />
                    </div>
                    <div class="min-w-0">
                      <p class="text-sm font-medium text-thamani-forest truncate">{item.title}</p>
                      <p class="text-xs text-thamani-pewter truncate">{item.subtitle}</p>
                    </div>
                  </div>
                  <span class="px-2.5 py-1 text-xs font-medium bg-thamani-lime text-thamani-forest rounded-full shrink-0">
                    {item.badge}
                  </span>
                </div>
              </div>

              <%!-- Empty state --%>
              <div
                :if={items == []}
                class="py-8 text-center text-sm text-thamani-pewter"
              >
                No matching records found at {@site.name} for "{@search_query}"
              </div>
            </div>
          </div>

          <button
            type="button"
            phx-click="toggle_filters"
            class="inline-flex items-center justify-center gap-2 rounded-full bg-thamani-forest hover:opacity-90 text-thamani-snow px-5 py-2.5 text-sm font-normal transition-colors shrink-0 cursor-pointer w-full sm:w-auto"
          >
            <.icon name="hero-adjustments-horizontal" class="size-4" /> Filters
          </button>
        </div>

        <%!-- Date Range Filter Popover Modal --%>
        <div
          :if={@show_filters}
          class="absolute right-6 top-[80px] z-50 mt-2 w-full max-w-md rounded-2xl p-6 ff-surface-popover transition-all"
        >
          <form phx-submit="apply_custom_range">
            <div class="flex items-center justify-between border-b border-thamani-stone pb-3 mb-4">
              <h3 class="font-medium text-thamani-forest text-base">Filters</h3>
              <div class="flex items-center gap-3">
                <button
                  type="button"
                  phx-click="reset_filters"
                  class="text-xs font-medium text-thamani-forest hover:underline cursor-pointer"
                >
                  Reset all
                </button>
                <button
                  type="button"
                  phx-click="toggle_filters"
                  class="text-thamani-pewter hover:text-thamani-forest cursor-pointer"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </div>

            <p class="text-xs font-medium tracking-wider text-thamani-pewter uppercase mb-3">
              Date Range
            </p>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
              <div>
                <.date_picker
                  id="site-filter-date-from"
                  name="from"
                  value={elem(@dates, 0)}
                  label="Date From"
                  placeholder="MM/DD/YYYY"
                />
              </div>
              <div>
                <.date_picker
                  id="site-filter-date-to"
                  name="to"
                  value={elem(@dates, 1)}
                  label="Date To"
                  placeholder="MM/DD/YYYY"
                />
              </div>
            </div>

            <div class="flex items-center justify-end gap-3 border-t border-slate-100 pt-4">
              <button
                type="button"
                phx-click="clear_filters"
                class="px-4 py-2 text-xs sm:text-sm font-medium text-slate-600 hover:text-slate-900 border border-slate-200 rounded-xl hover:bg-slate-50 transition-colors cursor-pointer"
              >
                Clear filters
              </button>
              <button
                type="submit"
                class="px-5 py-2 text-xs sm:text-sm font-medium text-thamani-snow bg-thamani-forest hover:opacity-90 rounded-full transition-colors cursor-pointer"
              >
                Apply filters
              </button>
            </div>
          </form>
        </div>
      </div>

      <%!-- Site Stat Cards Grid --%>
      <div class="dashboard-stat-grid mt-6">
        <.stat_tile
          icon="hero-user-group"
          label="Total patients"
          value={@stats.total_patients}
          sublabel="Registered patients"
        />
        <.stat_tile
          icon="hero-building-office-2"
          label="Patient visits"
          value={@stats.patient_visits}
          sublabel="Visits in selected window"
        />
        <.stat_tile
          icon="hero-banknotes"
          label="Revenue collected"
          value={money(@stats.revenue_collected)}
          sublabel="Wallet credits at this site"
        />
        <.stat_tile
          icon="hero-users"
          label="Staff assigned"
          value={@stats.active_staff}
          sublabel="Assigned to this site"
        />
        <.stat_tile
          icon="hero-document-text"
          label="Prescriptions"
          value={@stats.prescriptions}
          sublabel="Prescriptions in selected window"
        />
        <.stat_tile
          icon="hero-beaker"
          label="Lab orders completed"
          value={@stats.lab_tests_done}
          sublabel="Completed lab orders at this site"
        />
        <.stat_tile
          icon="hero-clock"
          label="Pending prescriptions"
          value={@stats.pending_prescriptions}
          sublabel="Awaiting dispensing"
        />
        <.stat_tile
          icon="hero-clipboard-document-list"
          label="Pending lab orders"
          value={@stats.pending_lab_orders}
          sublabel="Awaiting results"
        />
      </div>

      <%!-- Revenue Charts Grid --%>
      <div class="dashboard-chart-grid mt-6">
        <.chart_card
          id="site-daily-revenue-chart"
          title="Daily revenue"
          subtitle={"Wallet credits collected per day at #{@site.name} in the selected window"}
          type="line"
          data={daily_revenue_chart_data(@daily_revenue)}
          options={chart_options()}
        />
        <.chart_card
          id="site-monthly-revenue-chart"
          title="Monthly revenue"
          subtitle={"Total wallet credits collected at #{@site.name} in the last 12 months"}
          type="bar"
          data={monthly_revenue_chart_data(@monthly_revenue)}
          options={chart_options()}
        />
      </div>

      <.header variant="plain" class="mt-8">Staff assigned</.header>
      <.table id="site-staff" rows={@staff}>
        <:col :let={user} label="Name">{user.name}</:col>
        <:col :let={user} label="Role">{Phoenix.Naming.humanize(user.role)}</:col>
        <:empty_state>
          <.blank_state icon="hero-users" title="No staff assigned">
            Staff assigned to this site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>

      <div
        :if={Site.pharmacy?(@site) and Site.lab?(@site)}
        class="tabs tabs-boxed w-fit mt-6 mb-2 p-1 bg-base-200"
      >
        <.link
          patch={~p"/org/sites/#{@site.id}?tab=pharmacy"}
          class={["tab px-6 font-medium", @tab == :pharmacy && "tab-active"]}
        >
          Pharmacy
        </.link>
        <.link
          patch={~p"/org/sites/#{@site.id}?tab=lab"}
          class={["tab px-6 font-medium", @tab == :lab && "tab-active"]}
        >
          Lab
        </.link>
      </div>

      <div :if={@tab == :pharmacy}>
        <.header variant="plain" class="mt-6">
          Low stock
          <:subtitle>Products at or below their reorder level</:subtitle>
        </.header>
        <.table id="site-low-stock" rows={@low_stock}>
          <:col :let={{product, _total}} label="Product">{product_display_name(product)}</:col>
          <:col :let={{product, _total}} label="Reorder level">
            {product && product.reorder_level}
          </:col>
          <:col :let={{_product, total}} label="Remaining">{total}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No products are low on stock">
              Products will show up here once they drop to their reorder level.
            </.blank_state>
          </:empty_state>
        </.table>

        <.header variant="plain" class="mt-6">
          Near-expiry batches
          <:subtitle>Expiring within {@near_expiry_days} days</:subtitle>
        </.header>
        <.table
          id="site-near-expiry"
          rows={@near_expiry}
          row_click={fn batch -> JS.navigate(~p"/org/batches/#{batch.id}") end}
        >
          <:col :let={batch} label="Product">{product_name(@products_by_id, batch.product_id)}</:col>
          <:col :let={batch} label="Batch no.">{batch.batch_no}</:col>
          <:col :let={batch} label="Expiry">{batch.expiry_date}</:col>
          <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
          <:empty_state>
            <.blank_state icon="hero-calendar-days" title="No batches expiring soon">
              Batches will appear here within {@near_expiry_days} days of their expiry date.
            </.blank_state>
          </:empty_state>
        </.table>

        <.header variant="plain" class="mt-6">Pending prescriptions</.header>
        <.table
          id="site-pending-prescriptions"
          rows={@pending_prescriptions}
          row_click={
            fn prescription -> JS.navigate(~p"/pharmacy/prescriptions/#{prescription.id}") end
          }
        >
          <:col :let={prescription} label="Status">
            <.status_badge status={prescription.status} />
          </:col>
          <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
          <:col :let={prescription} label="Paid">
            {if prescription.has_paid, do: "Yes", else: "No"}
          </:col>
          <:empty_state>
            <.blank_state icon="hero-clipboard-document-check" title="No pending prescriptions">
              Prescriptions awaiting dispensing at this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={@tab == :lab}>
        <.header variant="plain" class="mt-6">Pending orders</.header>
        <.table
          id="site-pending-orders"
          rows={@pending_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(lab_order)}
          </:col>
          <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No pending orders">
              New lab orders at this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>

        <.header variant="plain" class="mt-6">Incomplete reports</.header>
        <.table
          id="site-incomplete-orders"
          rows={@incomplete_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(lab_order)}
          </:col>
          <:col :let={lab_order} label="Status">
            <.status_badge status={lab_order.status} />
          </:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No incomplete reports">
              Orders still awaiting collection or results will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={is_nil(@tab)}>
        <.blank_state icon="hero-building-office-2" title="No operations configured" class="mt-6">
          This site has no pharmacy or lab operations to show.
        </.blank_state>
      </div>
    </Layouts.org_shell>
    """
  end
end
