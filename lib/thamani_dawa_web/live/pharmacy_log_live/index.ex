defmodule ThamaniDawaWeb.PharmacyLogLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.PharmacyLogs
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  import ThamaniDawaWeb.MonthlyLogComponents

  @log_types ~w(fridge_temperature humidity other)

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    {:ok,
     socket
     |> assign(:sites, Sites.list_sites(organization_id))
     |> assign(:site_id, SiteScoping.default_site_id(scope))
     |> assign(:log_types, @log_types)}
  end

  def handle_params(params, _url, socket) do
    today = Date.utc_today()
    month = param_to_integer(params["month"], today.month)
    year = param_to_integer(params["year"], today.year)
    log_type = params["log_type"] || "fridge_temperature"
    site_id = param_to_integer(params["site_id"], socket.assigns.site_id)

    log = find_log(socket, log_type, month, year)

    {:noreply,
     socket
     |> assign(:month, month)
     |> assign(:year, year)
     |> assign(:log_type, log_type)
     |> assign(:site_id, site_id)
     |> assign(:log, log)}
  end

  defp find_log(socket, log_type, month, year) do
    organization_id = socket.assigns.current_scope.organization_id

    organization_id
    |> PharmacyLogs.list_pharmacy_logs()
    |> Enum.find(&(&1.log_type == log_type and &1.month == month and &1.year == year))
  end

  defp param_to_integer(nil, default), do: default
  defp param_to_integer("", default), do: default
  defp param_to_integer(value, _default), do: String.to_integer(value)

  def handle_event("filter_change", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/pharmacy/pharmacy-logs?#{%{month: params["month"], year: params["year"], log_type: params["log_type"], site_id: params["site_id"]}}"
     )}
  end

  def handle_event("add_entry", %{"day" => day, "reading" => reading, "notes" => notes}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    entry = %{"reading" => reading, "notes" => notes}

    case PharmacyLogs.record_daily_entry(
           organization_id,
           socket.assigns.site_id,
           socket.assigns.log_type,
           socket.assigns.month,
           socket.assigns.year,
           String.to_integer(day),
           entry
         ) do
      {:ok, log} ->
        {:noreply, assign(socket, :log, log)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't add that entry.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>Pharmacy logs</.header>

      <.month_year_picker month={@month} year={@year} on_change="filter_change">
        <div>
          <label class="label">Log type</label>
          <select name="log_type" class="select">
            <option :for={t <- @log_types} value={t} selected={t == @log_type}>
              {Phoenix.Naming.humanize(t)}
            </option>
          </select>
        </div>
        <div :if={is_nil(SiteScoping.default_site_id(@current_scope))}>
          <label class="label">Site</label>
          <select name="site_id" class="select">
            <option value="">Choose a site</option>
            <option :for={s <- @sites} value={s.id} selected={s.id == @site_id}>{s.name}</option>
          </select>
        </div>
      </.month_year_picker>

      <div :if={@site_id} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">Add entry</h2>
          <form phx-submit="add_entry" class="flex flex-wrap gap-2 items-end">
            <input type="number" name="day" placeholder="Day (1-31)" min="1" max="31" class="input" required />
            <input type="text" name="reading" placeholder="Reading" class="input" required />
            <input type="text" name="notes" placeholder="Notes" class="input" />
            <.button variant="primary">Add entry</.button>
          </form>
        </div>
      </div>

      <p :if={is_nil(@site_id)} class="text-sm text-error">Choose a site before adding entries.</p>

      <.entries_table entries={(@log && @log.daily_entries) || %{}} key_label="Day">
        <:col :let={entry} label="Reading">{entry["reading"]}</:col>
        <:col :let={entry} label="Notes">{entry["notes"]}</:col>
      </.entries_table>
    </Layouts.app_shell>
    """
  end
end
