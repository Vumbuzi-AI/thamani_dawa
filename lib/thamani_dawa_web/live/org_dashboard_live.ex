defmodule ThamaniDawaWeb.OrgDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.{Dashboards, Organizations, Reports, Sites}

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:auto_start_tour?, params["tour"] == "1")
     |> assign_onboarding()
     |> assign_range("this_month")}
  end

  defp assign_onboarding(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)
    sites = Sites.list_sites(organization_id)
    primary_site = List.first(sites)
    checklist_items = Organizations.onboarding_checklist(organization, primary_site)

    socket
    |> assign(:organization, organization)
    |> assign(:primary_site, primary_site)
    |> assign(:checklist_items, checklist_items)
    |> assign(:setup_required?, not site_ready?(primary_site))
    |> assign(
      :show_checklist?,
      is_nil(organization.onboarding_checklist_dismissed_at) and
        Enum.any?(checklist_items, &(not &1.done?))
    )
    |> assign(:site_profitability, Reports.site_profitability(organization_id))
    |> assign(:multi_site?, Sites.multi_site?(organization_id))
  end

  defp primary_site_path(nil), do: ~p"/org/sites/new"
  defp primary_site_path(%{id: id}), do: ~p"/org/sites/#{id}/edit"

  defp site_ready?(nil), do: false

  defp site_ready?(site) do
    is_binary(site.address) and String.trim(site.address) != "" and site.activities != []
  end

  defp format_activities(activities), do: Enum.map_join(activities, ", ", &humanize_activity/1)

  defp humanize_activity(:pharmacy), do: "Pharmacy"
  defp humanize_activity(:laboratory), do: "Laboratory"
  defp humanize_activity(:distribution), do: "Distribution"

  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign_range(socket, range)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
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

  def handle_event("dismiss_onboarding_checklist", _params, socket) do
    {:ok, organization} = Organizations.dismiss_onboarding_checklist(socket.assigns.organization)

    {:noreply,
     socket
     |> assign(:organization, organization)
     |> assign(:show_checklist?, false)}
  end

  def handle_event("clear_search", _params, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
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
         {:ok, to_date} <- parse_date(to_str),
         {:ok, dates} <- Dashboards.validate_custom_range(from_date, to_date) do
      scope = socket.assigns.current_scope
      organization_id = scope.organization_id
      site_id = scope.current_site_id
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
      {:error, :reversed} ->
        {:noreply, put_flash(socket, :error, "Date From must be on or before Date To.")}

      {:error, :future} ->
        {:noreply, put_flash(socket, :error, "Date range cannot include future dates.")}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Invalid date selection. Please choose valid dates.")}
    end
  end

  def handle_event("apply_custom_range", _params, socket) do
    {:noreply, put_flash(socket, :error, "Please select valid dates.")}
  end

  defp assign_range(socket, range) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
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

  defp to_date_val(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date_val(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date_val(%Date{} = d), do: d

  defp money(amount), do: ThamaniDawaWeb.Money.ksh(amount)

  defp range_chip_label("custom", {from, to}) do
    "#{ThamaniDawaWeb.TimeFormat.date(from)} – #{ThamaniDawaWeb.TimeFormat.date(to)}"
  end

  defp range_chip_label(range, _dates) do
    Dashboards.ranges() |> Enum.into(%{}) |> Map.get(range, "This Month")
  end

  defp day_axis(date), do: Calendar.strftime(date, "%-d %b")
  defp month_axis(date), do: Calendar.strftime(date, "%b %Y")

  defp revenue_bars(series, label_fun) do
    amounts = Enum.map(series, &elem(&1, 1))
    max = Enum.max(amounts, fn -> 0 end)
    total = length(series)

    series
    |> Enum.with_index()
    |> Enum.map(fn {{date, amount}, index} ->
      height =
        cond do
          max <= 0 -> 8
          true -> max(8, round(amount / max * 100))
        end

      %{height: height, recent: index >= max(0, total - 7), label: label_fun.(date)}
    end)
  end

  defp axis_labels([]), do: []

  defp axis_labels(marks) do
    last = length(marks) - 1
    mid = div(last, 2)
    [Enum.at(marks, 0).label, Enum.at(marks, mid).label, Enum.at(marks, last).label]
  end

  defp site_tick_max(rows) do
    rows
    |> Enum.map(&tick_count(&1.revenue))
    |> Enum.max(fn -> 0 end)
  end

  defp tick_count(%Decimal{} = d), do: d |> Decimal.round(0) |> Decimal.to_integer() |> abs()
  defp tick_count(n) when is_number(n), do: n |> round() |> abs()
  defp tick_count(_), do: 0


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

    sites =
      Enum.map(Map.get(results, :sites, []), fn s ->
        %{
          type: :site,
          title: s.name,
          subtitle: "#{s.address || "No address"} • #{format_activities(s.activities)}",
          badge: "GLN: #{s.gln || "N/A"}",
          icon: "hero-building-office-2"
        }
      end)

    staff =
      Enum.map(Map.get(results, :staff, []), fn u ->
        %{
          type: :staff,
          title: u.name,
          subtitle: u.email,
          badge: ThamaniDawa.Accounts.User.humanize_roles(u),
          icon: "hero-users"
        }
      end)

    visits =
      Enum.map(Map.get(results, :visits, []), fn v ->
        %{
          type: :visit,
          title: v.patient_name,
          subtitle:
            "Site: #{v.site_name} • Date: #{Calendar.strftime(to_date_val(v.inserted_at), "%d %b %Y")}",
          badge: String.capitalize(to_string(v.visit_type)),
          icon: "hero-document-text"
        }
      end)

    patients ++ sites ++ staff ++ visits
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:daily_bars, revenue_bars(assigns[:daily_revenue] || [], &day_axis/1))
      |> assign(:monthly_bars, revenue_bars(assigns[:monthly_revenue] || [], &month_axis/1))
      |> assign(:range_label, range_chip_label(assigns[:range], assigns[:dates]))
      |> assign(:site_tick_max, site_tick_max(assigns[:site_profitability] || []))

    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/org/dashboard"
      crumb="Dashboard"
    >
      <:tools>
        <.td_button variant="primary" navigate={~p"/org/sites/new"} label="Add site">
          <:icon><.td_icon name="plus" /></:icon>
        </.td_button>
      </:tools>
      <%!-- Fixed backdrop blur overlay when search popover is active --%>
      <div
        :if={
          not @setup_required? and @search_query != "" and String.trim(@search_query) != "" and
            Map.get(assigns, :search_active, true)
        }
        class="fixed inset-0 z-30"
        style="background: var(--color-td-scrim);"
        phx-click="dismiss_search"
      />


      <section
        :if={@setup_required?}
        id="organization-onboarding-welcome"
        class="rounded-2xl border border-thamani-stone bg-td-surface px-6 py-7 shadow-sm sm:px-8"
      >
        <h1 class="text-3xl font-medium tracking-tight text-thamani-forest sm:text-4xl">
          Welcome to {@organization.name}
        </h1>
        <p class="mt-3 max-w-2xl text-base leading-7 text-thamani-pewter">
          A few quick steps before you're fully up and running.
        </p>
        <.link
          id="complete-primary-site"
          navigate={primary_site_path(@primary_site)}
          class="mt-5 inline-flex items-center rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-semibold text-td-on-accent shadow-sm transition-all hover:opacity-90 active:scale-[0.98]"
        >
          Complete your primary site
        </.link>
      </section>

      <section
        :if={@show_checklist?}
        id="organization-onboarding"
        class="rounded-2xl border border-transparent bg-td-accent-tint p-5 shadow-sm"
      >
        <div class="mb-4 flex items-center justify-between gap-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-forest">
            Getting started
          </h2>
          <div class="flex items-center gap-2">
            <span
              id="onboarding-checklist-progress"
              class="rounded-full bg-td-surface px-2.5 py-1 text-[11px] font-semibold text-thamani-forest"
            >
              {Enum.count(@checklist_items, & &1.done?)} of {length(@checklist_items)} complete
            </span>
            <button
              id="onboarding-checklist-dismiss"
              type="button"
              phx-click="dismiss_onboarding_checklist"
              title="Dismiss"
              aria-label="Dismiss getting started checklist"
              class="flex size-6 items-center justify-center rounded-full text-thamani-pewter transition-colors hover:bg-td-surface hover:text-thamani-forest"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </div>
        <ul class="flex flex-col gap-2">
          <li
            :for={item <- @checklist_items}
            id={"onboarding-item-#{item.key}"}
            class="flex items-start justify-between gap-3 rounded-xl bg-td-surface p-4 shadow-sm"
          >
            <div class="flex min-w-0 items-start gap-3">
              <div class={[
                "mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg",
                item.done? && "bg-td-accent-tint text-thamani-forest",
                !item.done? && "bg-thamani-forest text-thamani-on-accent"
              ]}>
                <.icon
                  name={if item.done?, do: "hero-check", else: "hero-rocket-launch"}
                  class="size-4"
                />
              </div>
              <div class="min-w-0">
                <h3 class={[
                  "text-sm font-semibold",
                  item.done? && "text-thamani-pewter line-through",
                  !item.done? && "text-thamani-forest"
                ]}>
                  {item.label}
                </h3>
                <p :if={!item.done?} class="mt-0.5 text-xs text-thamani-pewter">
                  {item.description}
                </p>
              </div>
            </div>
            <.link
              :if={!item.done?}
              id={"onboarding-item-#{item.key}-cta"}
              navigate={item.path}
              class="shrink-0 rounded-full bg-thamani-forest px-4 py-2 text-xs font-semibold text-td-on-accent shadow-sm transition-all hover:opacity-90 active:scale-[0.98]"
            >
              {item.cta}
            </.link>
          </li>
        </ul>
      </section>

      <.td_dashboard
        :if={not @setup_required?}
        id="org-admin-dashboard"
        title="Admin dashboard"
        subtitle="Revenue, patients, and staff across every site in your organization."
      >
        <:actions>
          <div class="td-org-dash-search">
            <input
              type="search"
              name="search"
              value={@search_query}
              placeholder="Search patients, visits, revenue or reports..."
              phx-keyup="search"
              phx-focus="activate_search"
              phx-click="activate_search"
              phx-debounce="250"
              autocomplete="off"
              class="td-input td-org-dash-search-input"
            />
            <button
              :if={@search_query != "" and String.trim(@search_query) != ""}
              type="button"
              phx-click="clear_search"
              class="td-icon-btn"
              aria-label="Clear search"
            >
              <.td_icon name="x" class="size-3.5" />
            </button>

            <div
              :if={
                @search_query != "" and String.trim(@search_query) != "" and
                  Map.get(assigns, :search_active, true)
              }
              phx-window-keydown="dismiss_search"
              phx-key="escape"
              class="td-popover td-org-dash-search-pop"
            >
              <% items = combined_search_items(@search_results) %>
              <div class="td-org-dash-search-hd">
                <p class="td-popover-label">Search hits for "{@search_query}"</p>
                <button type="button" phx-click="clear_search" class="td-text-btn">
                  Clear search
                </button>
              </div>
              <p class="td-org-dash-search-hint">
                Metrics on dashboard below filtered for "{@search_query}"
                <span>
                  {@stats.total_patients} patients • {@stats.patient_visits} visits • {money(
                    @stats.revenue_collected
                  )}
                </span>
              </p>
              <div :if={items == []} class="td-empty-inline">
                No matching patients, sites, staff, or records found for "{@search_query}"
              </div>
              <div :for={item <- items} class="td-org-dash-search-item">
                <div>
                  <p class="td-org-dash-search-title">{item.title}</p>
                  <p class="td-muted">{item.subtitle}</p>
                </div>
                <span class="td-chip is-quiet">{item.badge}</span>
              </div>
            </div>
          </div>

          <div id="org-dashboard-range-filter" class="td-view-menu">
            <button
              type="button"
              id="org-dashboard-range-filter-trigger"
              class="td-chip td-view-menu-trigger"
              aria-haspopup="menu"
              aria-expanded="false"
              phx-click={
                JS.toggle(to: "#org-dashboard-range-filter-menu")
                |> JS.toggle_attribute({"aria-expanded", "true", "false"},
                  to: "#org-dashboard-range-filter-trigger"
                )
              }
            >
              <.td_icon name="calendar-blank" class="size-3.5" />
              <span>Date range</span>
              <span class="td-chip-value">{@range_label}</span>
              <.td_icon name="caret-down" class="size-3.5" />
            </button>
            <div
              id="org-dashboard-range-filter-menu"
              class="td-popover td-view-menu-pop"
              role="menu"
              hidden
              phx-click-away={JS.hide(to: "#org-dashboard-range-filter-menu")}
            >
              <p class="td-popover-label">Date range</p>
              <button
                :for={{key, label} <- Dashboards.ranges()}
                type="button"
                role="menuitem"
                class={["td-menu-item", key == @range && "is-selected"]}
                phx-click={
                  JS.hide(to: "#org-dashboard-range-filter-menu")
                  |> JS.push("set_range", value: %{range: key})
                }
              >
                <span class="flex-1">{label}</span>
                <.td_icon :if={key == @range} name="check" class="size-3.5" />
              </button>
              <button
                type="button"
                role="menuitem"
                class={["td-menu-item", @range == "custom" && "is-selected"]}
                phx-click={
                  JS.hide(to: "#org-dashboard-range-filter-menu")
                  |> JS.push("toggle_filters")
                }
              >
                <span class="flex-1">Custom…</span>
                <.td_icon :if={@range == "custom"} name="check" class="size-3.5" />
              </button>
            </div>
          </div>

          <div class="relative">
            <button type="button" phx-click="toggle_filters" class="td-chip">
              <.td_icon name="funnel-simple" class="size-3.5" />
              Filters
              <span :if={@range == "custom"} class="td-chip-dot"></span>
            </button>
            <div
              :if={@show_filters}
              class="fixed inset-0 z-40"
              phx-click="toggle_filters"
            />
            <div :if={@show_filters} class="td-popover td-org-dash-filters absolute right-0 top-full z-50 mt-2">
              <form phx-submit="apply_custom_range">
                <div class="td-org-dash-filters-hd">
                  <h3>Filters</h3>
                  <button type="button" phx-click="reset_filters" class="td-text-btn">
                    Reset all
                  </button>
                  <button
                    type="button"
                    phx-click="toggle_filters"
                    class="td-icon-btn"
                    aria-label="Close filters"
                  >
                    <.td_icon name="x" class="size-3.5" />
                  </button>
                </div>
                <p class="td-popover-label">Date range</p>
                <.date_range_picker
                  id="filter-dates"
                  from_name="from"
                  from_value={elem(@dates, 0)}
                  to_name="to"
                  to_value={elem(@dates, 1)}
                  max="today"
                />
                <div class="td-org-dash-filters-ft">
                  <button type="button" phx-click="clear_filters" class="td-btn is-secondary">
                    Clear filters
                  </button>
                  <button type="submit" class="td-btn is-primary">Apply filters</button>
                </div>
              </form>
            </div>
          </div>
        </:actions>

        <:strip id="admin-dashboard-stats">
          <.td_glance_cell
            id="total-patients-stat"
            value={@stats.total_patients}
            caption="total patients"
            tone="success"
          >
            <:icon><.td_icon name="users" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="patient-visits-stat"
            value={@stats.patient_visits}
            caption="patient visits"
            tone="info"
          >
            <:icon><.td_icon name="calendar-check" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="revenue-collected-stat"
            value={money(@stats.revenue_collected)}
            caption="revenue collected"
            tone="warning"
          >
            <:icon><.td_icon name="wallet" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="active-staff-stat"
            value={@stats.active_staff}
            caption="active staff"
            tone="neutral"
          >
            <:icon><.td_icon name="identification-badge" /></:icon>
          </.td_glance_cell>
        </:strip>

        <div id="admin-dashboard-charts">
        <.td_dash_row>
          <.td_dash_card
            id="daily-revenue-chart"
            title="Daily revenue"
            subtitle="Wallet credits collected per day in the selected window"
          >
            <div class="td-bars" aria-label="Daily revenue in the selected window">
              <i
                :for={bar <- @daily_bars}
                class={bar.recent && "is-now"}
                style={"height: #{bar.height}%"}
              >
              </i>
            </div>
            <div :if={@daily_bars != []} class="td-axis">
              <span :for={label <- axis_labels(@daily_bars)}>{label}</span>
            </div>
          </.td_dash_card>
          <.td_dash_card
            id="monthly-revenue-chart"
            title="Monthly revenue"
            subtitle="Total wallet credits collected in the last 12 months"
            width={380}
          >
            <div class="td-bars" aria-label="Monthly revenue over the last 12 months">
              <i
                :for={bar <- @monthly_bars}
                class={bar.recent && "is-now"}
                style={"height: #{bar.height}%"}
              >
              </i>
            </div>
            <div :if={@monthly_bars != []} class="td-axis">
              <span :for={label <- axis_labels(@monthly_bars)}>{label}</span>
            </div>
          </.td_dash_card>
        </.td_dash_row>
        </div>

        <div id="org-analytics-charts">
        <.td_dash_row>
          <.td_dash_card
            id="org-site-performance-chart"
            title="Revenue and cost by site"
            subtitle="All-time site comparison. Profit is revenue less stock cost."
          >
            <table class="td-rows td-ticks">
              <thead>
                <tr>
                  <th>Site</th>
                  <th>Revenue</th>
                  <th>Stock cost</th>
                  <th>Profit</th>
                  <th class="td-ticks-col"></th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@site_profitability == []}>
                  <td colspan="5" class="td-muted">No site revenue yet.</td>
                </tr>
                <tr
                  :for={row <- @site_profitability}
                  id={"org-site-row-#{row.site.id}"}
                  class="is-link"
                  phx-click={JS.navigate("/org/sites/#{row.site.id}")}
                >
                  <td>{row.site.name}</td>
                  <td class="is-num">{money(row.revenue)}</td>
                  <td class="is-num">{money(row.cost_of_goods)}</td>
                  <td class="is-num">{money(row.profit)}</td>
                  <td>
                    <.td_ticks
                      count={tick_count(row.revenue)}
                      max={@site_tick_max}
                      tone="success"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
            <div id="org-site-profit-chart" class="hidden" aria-hidden="true"></div>
          </.td_dash_card>
        </.td_dash_row>
        </div>
      </.td_dashboard>


      <div
        :if={not @setup_required?}
        id="organization-product-tour"
        phx-hook=".ProductTour"
        phx-update="ignore"
        data-tour-key={"thamani-org-tour-v1-#{@current_scope.user.id}"}
        data-auto-start={to_string(@auto_start_tour?)}
        data-multi-site={to_string(@multi_site?)}
        class="hidden"
      >
        <button
          type="button"
          data-tour-dismiss
          aria-label="Close product tour"
          class="fixed inset-0 z-40 cursor-default bg-td-ink/45 backdrop-blur-[1px]"
        ></button>
        <section
          data-tour-card
          role="dialog"
          aria-modal="true"
          aria-labelledby="product-tour-title"
          class="fixed z-[100] w-[min(390px,calc(100vw-2rem))] rounded-2xl border border-white/20 bg-thamani-forest p-5 text-td-on-accent shadow-2xl transition-[top,left] duration-200"
        >
          <span
            data-tour-arrow
            class="absolute left-[-7px] top-1/2 hidden size-3.5 -translate-y-1/2 rotate-45 border-b border-l border-white/20 bg-thamani-forest"
          ></span>
          <div class="flex items-start justify-between gap-4">
            <div>
              <p
                data-tour-progress
                class="text-xs font-semibold uppercase tracking-[0.16em] text-td-on-accent"
              >
              </p>
              <h2 id="product-tour-title" data-tour-title class="mt-2 text-xl font-semibold"></h2>
            </div>
            <button
              type="button"
              data-tour-dismiss
              aria-label="Close product tour"
              class="rounded-lg p-1 text-white/70 transition-colors hover:bg-td-surface/10 hover:text-white"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <p
            data-tour-description
            class="mt-3 text-[15px] leading-6"
            style="color: rgba(255, 255, 255, 0.84);"
          >
          </p>
          <div class="mt-5 flex items-center justify-between gap-3">
            <button
              type="button"
              data-tour-back
              class="rounded-full px-4 py-2 text-sm font-medium text-white/80 transition-colors hover:bg-td-surface/10 disabled:invisible"
            >
              Back
            </button>
            <button
              type="button"
              data-tour-dismiss
              class="rounded-full px-3 py-2 text-sm font-medium text-white/70 transition-colors hover:bg-td-surface/10 hover:text-white"
            >
              Skip tour
            </button>
            <button
              type="button"
              data-tour-next
              class="rounded-full bg-td-accent-tint px-5 py-2 text-sm font-semibold text-thamani-forest transition-all hover:brightness-95 active:scale-[0.98]"
            >
              Next
            </button>
          </div>
        </section>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ProductTour">
        export default {
          mounted() {
            this.steps = [
              {
                selector: '[data-tour-target="/org/dashboard"]',
                title: "See what needs attention",
                description: "Start here for patient activity, revenue, and operational work across the organization."
              },
              {
                selector: '[data-tour-target="/org/sites"]',
                title: "Manage locations",
                description: "Add sites and keep their address, services, and operating details up to date."
              },
              {
                selector: '[data-tour-target="/org/products"]',
                title: "Build the shared catalog",
                description: "Create the medicines and supplies used across your organization before receiving stock."
              },
              {
                selector: '[data-tour-target="/org/team"]',
                title: "Give staff the right access",
                description: "Invite staff and assign site access so each person sees the work relevant to them."
              },
              {
                selector: '[data-tour-target="/org/suppliers"]',
                title: "Manage suppliers",
                description: "Store supplier contacts and GLNs for the businesses that provide your stock."
              },
              {
                selector: '[data-tour-target="/org/requisitions"]',
                title: "Coordinate stock requests",
                description: "Review site replenishment requests from submission through approval and fulfilment.",
                multiSiteOnly: true
              },
              {
                selector: '[data-tour-target="/org/earnings"]',
                title: "Review transactions",
                description: "Find completed payments and transaction history across the organization."
              },
              {
                selector: '[data-tour-target="/org/epcis"]',
                title: "Monitor TNT reporting",
                description: "Check whether reportable events reached PPB and resolve anything that needs resubmission."
              }
            ].filter(step => !step.multiSiteOnly || this.el.dataset.multiSite === "true")
            this.index = 0
            this.activeTarget = null
            this.dismiss = () => this.finish()
            this.next = () => this.index === this.steps.length - 1 ? this.finish() : this.show(this.index + 1)
            this.back = () => this.show(this.index - 1)
            this.start = () => this.show(0)
            this.reposition = () => this.positionCard()
            this.keydown = event => {
              if (event.key === "Escape") this.finish()
              if (event.key === "ArrowRight") this.next()
              if (event.key === "ArrowLeft" && this.index > 0) this.back()
            }

            this.el.querySelectorAll("[data-tour-dismiss]").forEach(button => button.addEventListener("click", this.dismiss))
            this.el.querySelector("[data-tour-next]").addEventListener("click", this.next)
            this.el.querySelector("[data-tour-back]").addEventListener("click", this.back)
            window.addEventListener("keydown", this.keydown)
            window.addEventListener("resize", this.reposition)

            if (this.el.dataset.autoStart === "true") {
              this.start()
              const url = new URL(window.location.href)
              url.searchParams.delete("tour")
              window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`)
            }
          },

          show(index) {
            this.clearTarget()
            this.index = Math.max(0, Math.min(index, this.steps.length - 1))
            const step = this.steps[this.index]
            const sidebar = document.getElementById("sidebar-shell")
            const aside = document.getElementById("sidebar-aside")
            sidebar?.classList.add("sidebar-mobile-open")
            aside?.classList.remove("sidebar-collapsed")

            this.activeTarget = document.querySelector(step.selector)
            if (this.activeTarget) {
              this.activeTarget.dataset.tourPreviousStyle = this.activeTarget.getAttribute("style") || ""
              this.activeTarget.style.position = "relative"
              this.activeTarget.style.zIndex = "55"
              this.activeTarget.style.boxShadow = "0 0 0 4px rgba(211, 239, 74, 0.9), 0 12px 30px rgba(0, 0, 0, 0.25)"
              this.activeTarget.scrollIntoView({block: "nearest"})
            }

            this.el.querySelector("[data-tour-progress]").textContent = `Quick tour · ${this.index + 1} of ${this.steps.length}`
            this.el.querySelector("[data-tour-title]").textContent = step.title
            this.el.querySelector("[data-tour-description]").textContent = step.description
            this.el.querySelector("[data-tour-back]").disabled = this.index === 0
            this.el.querySelector("[data-tour-next]").textContent = this.index === this.steps.length - 1 ? "Finish" : "Next"
            this.el.classList.remove("hidden")
            this.positionCard()
            window.clearTimeout(this.positionTimer)
            this.positionTimer = window.setTimeout(() => this.positionCard(), 220)
            this.el.querySelector("[data-tour-next]").focus()
          },

          positionCard() {
            const card = this.el.querySelector("[data-tour-card]")
            const arrow = this.el.querySelector("[data-tour-arrow]")
            if (!card || !this.activeTarget) return

            const target = this.activeTarget.getBoundingClientRect()
            const cardWidth = card.offsetWidth
            const cardHeight = card.offsetHeight
            const gap = 20
            const edge = 16
            const roomOnRight = window.innerWidth - target.right - gap

            if (window.innerWidth >= 640 && roomOnRight >= cardWidth + edge) {
              const top = Math.min(
                Math.max(target.top + target.height / 2 - cardHeight / 2, edge),
                window.innerHeight - cardHeight - edge
              )
              card.style.left = `${target.right + gap}px`
              card.style.top = `${top}px`
              arrow.classList.remove("hidden")
              arrow.style.top = `${Math.min(Math.max(target.top + target.height / 2 - top, 24), cardHeight - 24)}px`
            } else {
              card.style.left = `${Math.max((window.innerWidth - cardWidth) / 2, edge)}px`
              card.style.top = `${Math.max(window.innerHeight - cardHeight - edge, edge)}px`
              arrow.classList.add("hidden")
            }
          },

          clearTarget() {
            if (!this.activeTarget) return
            this.activeTarget.setAttribute("style", this.activeTarget.dataset.tourPreviousStyle || "")
            delete this.activeTarget.dataset.tourPreviousStyle
            this.activeTarget = null
          },

          finish() {
            this.clearTarget()
            this.el.classList.add("hidden")
            localStorage.setItem(this.el.dataset.tourKey, "complete")
            document.getElementById("sidebar-shell")?.classList.remove("sidebar-mobile-open")
          },

          destroyed() {
            this.clearTarget()
            window.clearTimeout(this.positionTimer)
            window.removeEventListener("keydown", this.keydown)
            window.removeEventListener("resize", this.reposition)
          }
        }
      </script>
    </Layouts.org_shell>
    """
  end
end
