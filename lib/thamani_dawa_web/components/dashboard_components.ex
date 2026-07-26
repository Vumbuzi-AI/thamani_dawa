defmodule ThamaniDawaWeb.DashboardComponents do
  @moduledoc """
  Stat tiles, Chart.js chart cards, and range-filter pills shared by the
  admin, pharmacy, and lab dashboards.
  """
  use Phoenix.Component

  import ThamaniDawaWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders a single KPI tile.

  ## Examples

      <.stat_tile icon="hero-users" label="Total patients" value="26" sublabel="Registered patients" />
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sublabel, :string, default: nil
  attr :class, :any, default: nil

  def stat_tile(assigns) do
    ~H"""
    <div class={["dashboard-stat-tile", @class]}>
      <span class="dashboard-stat-tile-icon">
        <.icon name={@icon} class="size-5" />
      </span>
      <span class="dashboard-stat-tile-label">{@label}</span>
      <span class="dashboard-stat-tile-value">{@value}</span>
      <span :if={@sublabel} class="dashboard-stat-tile-sublabel">{@sublabel}</span>
    </div>
    """
  end

  @doc """
  Renders a card wrapping a Chart.js canvas.

  `data` and `options` are plain maps/lists — they get JSON-encoded for the
  `Chart` JS hook (see `assets/js/hooks/chart_hook.js`), which (re)creates the
  chart whenever these attributes change.

  ## Examples

      <.chart_card id="daily-revenue" title="Daily Revenue" type="line" data={@daily_revenue_data} />
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :type, :string, required: true
  attr :data, :map, required: true
  attr :options, :map, default: %{}
  attr :class, :any, default: nil

  def chart_card(assigns) do
    ~H"""
    <div class={["dashboard-chart-card", @class]}>
      <p class="dashboard-chart-title">{@title}</p>
      <p :if={@subtitle} class="dashboard-chart-subtitle">{@subtitle}</p>
      <div class="dashboard-chart-canvas-wrap">
        <canvas
          id={@id}
          phx-hook="Chart"
          data-chart-type={@type}
          data-chart-data={Jason.encode!(@data)}
          data-chart-options={Jason.encode!(@options)}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a row of date-range pill buttons.

  Clicking a pill sends `phx-click={@event}` with `phx-value-range` set to
  that range's key; the parent LiveView's `handle_event/3` is responsible for
  recomputing assigns for the newly selected range.

  ## Examples

      <.range_filter event="set_range" current={@range} ranges={[{"this_month", "This Month"}, {"all_time", "All Time"}]} />
  """
  attr :event, :string, required: true
  attr :current, :string, required: true
  attr :ranges, :list, required: true

  def range_filter(assigns) do
    ~H"""
    <div class="dashboard-range-filter">
      <button
        :for={{key, label} <- @ranges}
        type="button"
        phx-click={JS.push(@event, value: %{range: key})}
        aria-pressed={to_string(key == @current)}
        class="dashboard-range-pill"
      >
        {label}
      </button>
    </div>
    """
  end
end
