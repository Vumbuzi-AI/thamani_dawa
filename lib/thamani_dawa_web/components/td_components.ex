defmodule ThamaniDawaWeb.TDComponents do
  @moduledoc """
  Thamani Dawa kit. Prop names match Doop: variant, tone, label, crumb, tools, side, content.
  Screens compose these. They do not grow a skin on CoreComponents.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :name, :string, required: true
  attr :weight, :string, default: "regular"
  attr :class, :any, default: "size-4"

  # Doop icons the bundled Phosphor release predates.
  @extra_icons %{
    "tray-arrow-down" =>
      "M208 32H48a16 16 0 0 0-16 16v160a16 16 0 0 0 16 16h160a16 16 0 0 0 16-16V48a16 16 0 0 0-16-16m0 16v104h-28.7a15.86 15.86 0 0 0-11.3 4.69L148.69 176h-41.38L88 156.69A15.86 15.86 0 0 0 76.69 152H48V48Zm0 160H48v-40h28.69L96 187.31a15.86 15.86 0 0 0 11.31 4.69h41.38a15.86 15.86 0 0 0 11.31-4.69L179.31 168H208zM90.34 125.66a8 8 0 0 1 11.32-11.32L120 132.69V72a8 8 0 0 1 16 0v60.69l18.34-18.35a8 8 0 0 1 11.32 11.32l-32 32a8 8 0 0 1-11.32 0Z"
  }

  def td_icon(%{name: name} = assigns) when is_map_key(@extra_icons, name) do
    assigns = assign(assigns, :d, Map.fetch!(@extra_icons, name))

    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" class={@class} aria-hidden="true">
      <path fill="currentColor" d={@d} />
    </svg>
    """
  end

  def td_icon(assigns) do
    assigns = update(assigns, :name, &known_icon/1)

    ~H"""
    <Phosphor.icon name={@name} weight={@weight} class={@class} />
    """
  end

  # The bundled Phosphor set has no squares-plus. Stack is the aggregation mark.
  defp known_icon("squares-plus"), do: "stack"
  defp known_icon(name), do: name

  attr :variant, :string,
    values: ~w(primary secondary danger danger-confirm),
    default: "secondary"

  attr :size, :string, values: ~w(md lg), default: "md"
  attr :label, :string, default: nil
  attr :glyph, :string, default: nil, doc: "Phosphor icon name shown before the label"

  attr :rest, :global,
    include:
      ~w(href navigate patch method download name value disabled type id form title onclick target rel phx-click phx-value-id phx-value-tier phx-value-from phx-value-to phx-value-mode phx-value-step phx-value-status phx-disable-with phx-submit phx-target phx-hook data-print-target data-print-container data-label-size data-download-container data-role data-sscc data-gs1-text data-quantity data-gtin data-batch data-production data-expiry data-material-description data-order-number data-from-company data-from-address data-to-company data-to-address data-to-po-box)

  slot :icon
  slot :inner_block

  def td_button(%{rest: rest} = assigns) do
    assigns = assign(assigns, :class, ["td-btn", "is-#{assigns.variant}", "is-#{assigns.size}"])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        <.td_icon :if={@glyph} name={@glyph} />
        {render_slot(@icon)}
        <span :if={@label}>{@label}</span>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        <.td_icon :if={@glyph} name={@glyph} />
        {render_slot(@icon)}
        <span :if={@label}>{@label}</span>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  attr :label, :string, required: true
  attr :rest, :global, include: ~w(id type disabled phx-click)
  slot :icon, required: true

  def td_icon_button(assigns) do
    ~H"""
    <button type="button" class="td-icon-btn" aria-label={@label} {@rest}>
      {render_slot(@icon)}
    </button>
    """
  end

  attr :tone, :string,
    values: ~w(success warning expiry danger info neutral),
    default: "neutral"

  attr :label, :string, required: true

  def td_badge(assigns) do
    ~H"""
    <span class={["td-badge", "is-#{@tone}"]}>{@label}</span>
    """
  end

  attr :value, :any, required: true

  def td_count(assigns) do
    ~H"""
    <span class="td-count">{@value}</span>
    """
  end

  attr :label, :string, default: nil
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :any, default: nil
  attr :hint, :string, default: nil
  attr :state, :string, values: ~w(default error), default: "default"
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []

  attr :rest, :global,
    include:
      ~w(autocomplete required placeholder disabled autocapitalize phx-debounce min max inputmode readonly maxlength)

  def td_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      if Phoenix.Component.used_input?(field), do: Enum.map(field.errors, &error_text/1), else: []

    assigns
    |> assign(:field, nil)
    |> assign(:id, assigns.id || field.id)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, Phoenix.HTML.Form.normalize_value(assigns.type, field.value))
    |> assign(:errors, errors)
    |> assign(:state, if(errors == [], do: assigns.state, else: "error"))
    |> td_input()
  end

  # Dates always use the TD date picker, never the browser's native calendar.
  def td_input(%{type: "date"} = assigns) do
    rest = assigns.rest

    assigns =
      assigns
      |> assign(:dp_required, !!rest[:required])
      |> assign(:dp_disabled, !!rest[:disabled])
      |> assign(:dp_max, rest[:max] && to_string(rest[:max]))
      |> assign(:dp_min, rest[:min] && to_string(rest[:min]))
      |> assign(:dp_placeholder, rest[:placeholder] || "Choose a date")

    ~H"""
    <div class="td-field">
      <ThamaniDawaWeb.CoreComponents.date_picker
        id={@id}
        name={@name}
        label={@label}
        value={@value}
        errors={@errors}
        required={@dp_required}
        disabled={@dp_disabled}
        max={@dp_max}
        min={@dp_min}
        placeholder={@dp_placeholder}
      />
      <span :if={@hint} class="td-field-hint">{@hint}</span>
    </div>
    """
  end

  def td_input(assigns) do
    ~H"""
    <label class="td-field" for={@id}>
      <span :if={@label} class="td-field-label">{@label}</span>
      <input
        id={@id}
        name={@name}
        type={@type}
        value={@value}
        class={["td-field-control", @state == "error" && "is-error"]}
        {@rest}
      />
      <span :if={@hint} class="td-field-hint">{@hint}</span>
      <span :for={error <- @errors} class="td-field-error">{error}</span>
    </label>
    """
  end

  attr :label, :string, default: nil
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :any, default: nil
  attr :prompt, :string, default: nil
  attr :options, :list, default: []
  attr :hint, :string, default: nil
  attr :state, :string, values: ~w(default error), default: "default"
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(required disabled)

  def td_select(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors =
      if Phoenix.Component.used_input?(field), do: Enum.map(field.errors, &error_text/1), else: []

    assigns
    |> assign(:field, nil)
    |> assign(:id, assigns.id || field.id)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, field.value)
    |> assign(:errors, errors)
    |> assign(:state, if(errors == [], do: assigns.state, else: "error"))
    |> td_select()
  end

  def td_select(assigns) do
    ~H"""
    <label class="td-field" for={@id}>
      <span :if={@label} class="td-field-label">{@label}</span>
      <select
        id={@id}
        name={@name}
        class={["td-field-control", @state == "error" && "is-error"]}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        <option
          :for={{label, value} <- @options}
          value={value}
          selected={to_string(value) == to_string(@value)}
        >
          {label}
        </option>
      </select>
      <span :if={@hint} class="td-field-hint">{@hint}</span>
      <span :for={error <- @errors} class="td-field-error">{error}</span>
    </label>
    """
  end

  attr :label, :string, default: nil
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :value, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :rest, :global, include: ~w(required placeholder rows)

  def td_textarea(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(:field, nil)
    |> assign(:id, assigns.id || field.id)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, field.value || "")
    |> td_textarea()
  end

  def td_textarea(assigns) do
    ~H"""
    <label class="td-field" for={@id}>
      <span :if={@label} class="td-field-label">{@label}</span>
      <textarea id={@id} name={@name} class="td-field-control td-textarea" {@rest}>{@value}</textarea>
    </label>
    """
  end

  attr :on, :boolean, default: false
  attr :label, :string, required: true
  attr :name, :string, default: nil
  attr :id, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil

  def td_checkbox(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(:field, nil)
    |> assign(:id, assigns.id || field.id)
    |> assign(:name, assigns.name || field.name)
    |> assign(:on, Phoenix.HTML.Form.normalize_value("checkbox", field.value))
    |> td_checkbox()
  end

  def td_checkbox(assigns) do
    ~H"""
    <label class="td-check" for={@id}>
      <input id={@id} type="checkbox" name={@name} value="true" checked={@on} />
      <span>{@label}</span>
    </label>
    """
  end

  attr :on, :boolean, default: false
  attr :label, :string, default: nil
  attr :rest, :global, include: ~w(id type phx-click phx-target)

  def td_switch(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked={to_string(@on)}
      aria-label={@label}
      class={["td-switch-ui", @on && "is-on"]}
      {@rest}
    >
      <span></span>
    </button>
    """
  end

  attr :active, :boolean, default: false
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :label_id, :string, default: nil
  attr :icon, :string, required: true
  attr :rest, :global, include: ~w(href navigate patch id data-tour-target data-tooltip)

  def td_nav_item(assigns) do
    ~H"""
    <.link
      class={["td-nav-item", @active && "is-active"]}
      aria-current={@active && "page"}
      aria-label={@label}
      {@rest}
    >
      <.td_icon
        name={ThamaniDawaWeb.CoreComponents.phosphor_name(@icon)}
        weight={if(@active, do: "fill", else: "regular")}
      />
      <span id={@label_id} class="nav-label">{@label}</span>
      <.td_count :if={(@count || 0) > 0} value={@count} />
    </.link>
    """
  end

  attr :tone, :string, values: ~w(default danger), default: "default"
  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :rest, :global, include: ~w(id type href navigate patch method phx-click phx-value-id)

  def td_menu_item(%{rest: rest} = assigns) do
    class = ["td-menu-item", assigns.tone == "danger" && "is-danger"]
    assigns = assign(assigns, :class, class)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        <.td_icon :if={@icon} name={@icon} />
        <span>{@label}</span>
      </.link>
      """
    else
      ~H"""
      <button type="button" class={@class} {@rest}>
        <.td_icon :if={@icon} name={@icon} />
        <span>{@label}</span>
      </button>
      """
    end
  end

  attr :seed, :string, default: "td"
  attr :size, :integer, default: 28

  def td_orb(assigns) do
    assigns = assign(assigns, :orb, :erlang.phash2(assigns.seed, 6) + 1)

    ~H"""
    <span
      class="td-orb"
      data-seed={@seed}
      data-orb={@orb}
      style={"width: #{@size}px; height: #{@size}px;"}
      aria-hidden="true"
    />
    """
  end

  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :mono, :boolean, default: false

  def td_key_value(assigns) do
    ~H"""
    <div class="td-kv">
      <span class="td-kv-label">{@label}</span>
      <span class={["td-kv-value", @mono && "is-mono"]}>{@value}</span>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def td_card_header(assigns) do
    ~H"""
    <header class="td-card-header">
      <div>
        <h2>{@title}</h2>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="td-header-actions">{render_slot(@actions)}</div>
    </header>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :back, :any, default: nil
  slot :status, doc: "badge or meta beside the title"
  slot :actions

  def td_page_header(assigns) do
    ~H"""
    <header class="td-page-header">
      <div class="td-page-title-wrap">
        <.link :if={is_binary(@back)} navigate={@back} aria-label="Go back" class="td-icon-btn">
          <.td_icon name="arrow-left" />
        </.link>
        <button
          :if={@back == true}
          type="button"
          aria-label="Go back"
          onclick="window.history.back()"
          class="td-icon-btn"
        >
          <.td_icon name="arrow-left" />
        </button>
        <div class="td-page-title">
          <div class="td-page-title-row">
            <h1>{@title}</h1>
            {render_slot(@status)}
          </div>
          <p :if={@subtitle}>{@subtitle}</p>
        </div>
      </div>
      <div :if={@actions != []} class="td-header-actions">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Doop filter-menu chip (Category `RBA4UYrkXr`, Status `TTXzDZPEWP`,
  Expiry `v0UH0bx6L9` and the other Filter menu · * frames): a labelled
  chip that opens a single-select popover. The empty value is shown as
  Any. Options are `{value, label}` pairs supplied by the page.
  """
  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :options, :list, required: true
  attr :event, :string, default: "set_filter"

  def td_filter_menu(assigns) do
    current =
      Enum.find_value(assigns.options, assigns.value, fn {v, label} ->
        if v == assigns.value, do: label
      end)

    assigns = assign(assigns, :current_label, current)

    ~H"""
    <div class="td-chip-wrap" phx-click-away={JS.hide(to: "##{@id}-menu-#{@field}")}>
      <button
        type="button"
        id={"#{@id}-chip-#{@field}"}
        class="td-chip"
        phx-click={JS.toggle(to: "##{@id}-menu-#{@field}")}
        aria-haspopup="menu"
        aria-expanded="false"
      >
        <span class="td-chip-label">{@label}</span>
        <span class="td-chip-value">{@current_label}</span>
        <.td_icon name="caret-down" />
      </button>
      <div id={"#{@id}-menu-#{@field}"} class="td-popover td-filter-menu hidden" role="menu">
        <p class="td-popover-label">{@label}</p>
        <button
          :for={{value, label} <- @options}
          type="button"
          id={"#{@id}-#{@field}-#{if value == "", do: "any", else: value}"}
          class={["td-menu-item", value == @value && "is-selected"]}
          phx-click={
            JS.push(@event, value: %{field: @field, value: value})
            |> JS.hide(to: "##{@id}-menu-#{@field}")
          }
          role="menuitemradio"
          aria-checked={to_string(value == @value)}
        >
          <span class="flex-1">{label}</span>
          <.td_icon :if={value == @value} name="check" class="size-3.5" />
        </button>
      </div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :shown, :integer, required: true
  attr :total, :integer, required: true
  attr :noun, :string, required: true

  def td_toolbar_count(assigns) do
    ~H"""
    <span id={@id} class="td-toolbar-count"><b>{@shown}</b> of {@total} {@noun}</span>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil

  def td_filter_chip(assigns) do
    ~H"""
    <span class="td-chip">
      <span class="td-chip-label">{@label}</span>
      <span :if={@value} class="td-chip-value">{@value}</span>
    </span>
    """
  end

  attr :label, :string, required: true
  attr :active, :boolean, default: false

  attr :rest, :global,
    include: ~w(id type phx-click phx-value-mode phx-value-tab phx-value-source aria-pressed)

  def td_segment(assigns) do
    ~H"""
    <button type="button" class={["td-segment", @active && "is-active"]} {@rest}>{@label}</button>
    """
  end

  slot :inner_block, required: true

  def td_segmented(assigns) do
    ~H"""
    <div class="td-segmented" role="group">{render_slot(@inner_block)}</div>
    """
  end

  attr :active, :boolean, default: false
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :rest, :global, include: ~w(href navigate patch type phx-click)

  def td_tab(assigns) do
    ~H"""
    <.link class={["td-tab", @active && "is-active"]} {@rest}>
      {@label}
      <.td_count :if={(@count || 0) > 0} value={@count} />
    </.link>
    """
  end

  attr :tone, :string, values: ~w(neutral success warning danger info), default: "neutral"
  attr :value, :any, required: true
  attr :caption, :string, required: true
  attr :icon, :string, default: nil
  attr :id, :string, default: nil

  def td_stat(assigns) do
    ~H"""
    <div id={@id} class={["td-stat", "is-#{@tone}"]}>
      <span class="td-stat-label">{@caption}</span>
      <span class="td-stat-value">{@value}</span>
    </div>
    """
  end

  slot :inner_block, required: true

  def td_glance_strip(assigns) do
    ~H"""
    <div class="td-glance">{render_slot(@inner_block)}</div>
    """
  end

  attr :tone, :string,
    values: ~w(success warning expiry danger info neutral),
    default: "neutral"

  attr :value, :string, required: true
  attr :caption, :string, required: true
  attr :rest, :global, include: ~w(id href navigate patch)
  slot :icon

  def td_glance_cell(assigns) do
    ~H"""
    <.link :if={@rest[:href] || @rest[:navigate] || @rest[:patch]} class="td-glance-cell" {@rest}>
      <span class={["td-glance-stat", "is-#{@tone}"]}>
        <span class="td-glance-tile">{render_slot(@icon)}</span>
        <span class="td-glance-copy">
          <span class="td-glance-value">{@value}</span>
          <span class="td-glance-caption">{@caption}</span>
        </span>
      </span>
    </.link>
    <div :if={!(@rest[:href] || @rest[:navigate] || @rest[:patch])} class="td-glance-cell">
      <span class={["td-glance-stat", "is-#{@tone}"]}>
        <span class="td-glance-tile">{render_slot(@icon)}</span>
        <span class="td-glance-copy">
          <span class="td-glance-value">{@value}</span>
          <span class="td-glance-caption">{@caption}</span>
        </span>
      </span>
    </div>
    """
  end

  @doc """
  Doop dashboard recipe (frames 8OjVBGuJw2 / ssU7S65tZF, element y1dna0): a
  68px page header on the surface, then a 16px pad on the canvas holding one
  or more TD Stat strips and rows of cards. The last row grows to fill the
  viewport. Shared by the manufacturer, distributor, lab and pharmacy
  dashboards.

      <.td_dashboard id="x" title="…" subtitle="…">
        <:actions>secondary buttons</:actions>
        <:strip><.td_glance_cell … /> × 4</:strip>
        <.td_dash_row>
          <.td_dash_card title="…" subtitle="…">…</.td_dash_card>
          <.td_dash_card title="…" width={320}>…</.td_dash_card>
        </.td_dash_row>
      </.td_dashboard>
  """
  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions
  slot :status, doc: "badge or meta beside the title"
  slot :notice, doc: "optional banner above the strips"

  slot :strip, doc: "one TD Stat strip; its children are td_glance_cell" do
    attr :id, :string
  end

  slot :inner_block

  def td_dashboard(assigns) do
    ~H"""
    <section id={@id} class="td-dashboard">
      <.td_page_header title={@title} subtitle={@subtitle}>
        <:status :if={@status != []}>{render_slot(@status)}</:status>
        <:actions :if={@actions != []}>{render_slot(@actions)}</:actions>
      </.td_page_header>
      <div class="td-dashboard-pad">
        {render_slot(@notice)}
        <div :for={strip <- @strip} id={strip[:id]} class="td-glance">{render_slot(strip)}</div>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def td_dash_row(assigns) do
    ~H"""
    <div class={["td-dash-row", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :width, :integer, default: nil, doc: "fixed width in px; nil fills the row"
  slot :actions
  slot :inner_block

  def td_dash_card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["td-dash-card", @width && "is-fixed"]}
      style={@width && "width: #{@width}px"}
    >
      <.td_card_header title={@title} subtitle={@subtitle}>
        <:actions :if={@actions != []}>{render_slot(@actions)}</:actions>
      </.td_card_header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :count, :integer, required: true
  attr :max, :integer, required: true
  attr :tone, :string, values: ~w(neutral info success warning danger expiry), default: "neutral"

  def td_ticks(assigns) do
    assigns = assign(assigns, :filled, ticks_filled(assigns.count, assigns.max))

    ~H"""
    <span class="td-ticks" aria-hidden="true">
      <i :for={index <- 0..11} class={[index < @filled && "is-on", "is-#{@tone}"]}></i>
    </span>
    """
  end

  @doc false
  def ticks_filled(count, max)
      when is_integer(count) and is_integer(max) and count > 0 and max > 0,
      do: count |> Kernel./(max) |> Kernel.*(12) |> Float.ceil() |> trunc() |> min(12)

  def ticks_filled(_count, _max), do: 0

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :caption, :string, default: nil
  attr :count, :integer, required: true
  attr :max, :integer, required: true
  attr :tone, :string, default: "neutral"
  attr :rest, :global, include: ~w(navigate patch href)

  def td_tick_row(assigns) do
    assigns =
      assign(
        assigns,
        :link?,
        !!(assigns.rest[:navigate] || assigns.rest[:patch] || assigns.rest[:href])
      )

    ~H"""
    <.link :if={@link?} id={@id} class="td-status-row is-link" {@rest}>
      <span class="td-status-copy">
        <b>{@label}</b>
        <span :if={@caption}>{@caption}</span>
      </span>
      <.td_ticks count={@count} max={@max} tone={@tone} />
      <span class="td-status-n">{@count}</span>
    </.link>
    <div :if={!@link?} id={@id} class="td-status-row">
      <span class="td-status-copy">
        <b>{@label}</b>
        <span :if={@caption}>{@caption}</span>
      </span>
      <.td_ticks count={@count} max={@max} tone={@tone} />
      <span class="td-status-n">{@count}</span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :current, :string, default: "week"
  attr :event, :string, default: "set_calendar_view"

  def td_view_menu(assigns) do
    views = [{"day", "Day"}, {"week", "Week"}, {"month", "Month"}]
    current_label = views |> Enum.into(%{}) |> Map.get(assigns.current, "Week")

    assigns =
      assigns
      |> assign(:views, views)
      |> assign(:current_label, current_label)

    ~H"""
    <div id={@id} class="td-view-menu">
      <button
        type="button"
        id={"#{@id}-trigger"}
        class="td-chip td-view-menu-trigger"
        aria-haspopup="menu"
        aria-expanded="false"
        phx-click={
          JS.toggle(to: "##{@id}-menu")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{@id}-trigger")
        }
      >
        <.td_icon name="calendar-blank" class="size-3.5" />
        <span>View</span>
        <span class="td-chip-value">{@current_label}</span>
        <.td_icon name="caret-down" class="size-3.5" />
      </button>
      <div
        id={"#{@id}-menu"}
        class="td-popover td-view-menu-pop"
        role="menu"
        hidden
        phx-click-away={JS.hide(to: "##{@id}-menu")}
      >
        <p class="td-popover-label">View</p>
        <button
          :for={{key, label} <- @views}
          type="button"
          role="menuitem"
          class={["td-menu-item", key == @current && "is-selected"]}
          phx-click={JS.hide(to: "##{@id}-menu") |> JS.push(@event, value: %{view: key})}
        >
          <span class="flex-1">{label}</span>
          <.td_icon :if={key == @current} name="check" class="size-3.5" />
        </button>
      </div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, default: "tray"
  slot :action

  def td_empty(assigns) do
    ~H"""
    <div id={@id} class="td-empty">
      <span class="td-empty-tile" aria-hidden="true"><.td_icon name={@icon} /></span>
      <p class="td-empty-title">{@title}</p>
      <p :if={@hint} class="td-note">{@hint}</p>
      <div :if={@action != []} class="td-empty-action">{render_slot(@action)}</div>
    </div>
    """
  end

  def td_empty_state(assigns), do: td_empty(assigns)

  attr :selected, :boolean, default: false
  attr :title, :string, required: true
  attr :body, :string, default: nil

  attr :rest, :global,
    include: ~w(type phx-click id phx-target phx-value-mode phx-value-index phx-value-type)

  def td_option_card(assigns) do
    ~H"""
    <button type="button" class={["td-option", @selected && "is-selected"]} {@rest}>
      <span class="td-option-title">{@title}</span>
      <span :if={@body} class="td-note">{@body}</span>
    </button>
    """
  end

  attr :placeholder, :string, required: true
  attr :shortcut, :string, default: nil
  attr :name, :string, default: "search"
  attr :value, :string, default: ""
  attr :rest, :global, include: ~w(id phx-change phx-debounce)

  def td_search(assigns) do
    ~H"""
    <label class="td-search">
      <.td_icon name="magnifying-glass" />
      <input type="search" name={@name} value={@value} placeholder={@placeholder} {@rest} />
      <kbd :if={@shortcut}>{@shortcut}</kbd>
    </label>
    """
  end

  attr :tone, :string, values: ~w(success danger info warning), default: "success"
  attr :text, :string, required: true

  def td_toast(assigns) do
    ~H"""
    <p class={["td-toast", "is-#{@tone}"]} data-tone={@tone} role="status">
      <span class="td-toast-icon" aria-hidden="true">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 256 256">
          <path
            fill="currentColor"
            d="M128 24a104 104 0 1 0 104 104A104.11 104.11 0 0 0 128 24m45.66 85.66l-56 56a8 8 0 0 1-11.32 0l-24-24a8 8 0 0 1 11.32-11.32L112 148.69l50.34-50.35a8 8 0 0 1 11.32 11.32"
          />
        </svg>
      </span>
      <span class="td-toast-text">{@text}</span>
    </p>
    """
  end

  attr :state, :string, values: ~w(done current upcoming), default: "upcoming"
  attr :number, :integer, required: true
  attr :label, :string, required: true

  def td_step(assigns) do
    ~H"""
    <span class={["td-step", "is-#{@state}"]}>
      <span class="td-step-n">{@number}</span>
      <span>{@label}</span>
    </span>
    """
  end

  @doc """
  Hidden hook target that turns a `push_event(socket, "td:csv", %{filename:,
  content:})` into a browser download, so a LiveView can export the rows it
  already holds without a separate controller route.
  """
  attr :id, :string, required: true

  def td_csv_download(assigns) do
    ~H"""
    <span id={@id} phx-hook=".CsvDownload" hidden></span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CsvDownload">
      export default {
        mounted() {
          this.handleEvent("td:csv", ({filename, content}) => {
            const blob = new Blob([content], {type: "text/csv;charset=utf-8"})
            const url = URL.createObjectURL(blob)
            const link = document.createElement("a")
            link.href = url
            link.download = filename
            document.body.appendChild(link)
            link.click()
            link.remove()
            setTimeout(() => URL.revokeObjectURL(url), 1000)
          })
        }
      }
    </script>
    """
  end

  @doc """
  Doop "Export CSV" dialog (2E9yucAGjQ): an optional date range, a column
  choice and a note, then Cancel / Download CSV. Submits `submit` with
  `%{"columns" => value}` (and `"range"` when `ranges` is given).
  """
  attr :id, :string, required: true
  attr :submit, :string, default: "export_csv"
  attr :on_cancel, JS, required: true
  attr :columns, :list, default: [{"All visible columns", "visible"}]
  attr :from, :any, default: nil
  attr :to, :any, default: nil
  attr :count, :integer, default: nil
  attr :noun, :string, default: "rows"

  def td_export_modal(assigns) do
    ~H"""
    <.td_modal
      id={@id}
      show
      width={520}
      title="Export CSV"
      subtitle="Download the rows that match your current filters."
      on_cancel={@on_cancel}
    >
      <:body>
        <.form for={%{}} as={:export} id={"#{@id}-form"} phx-submit={@submit} class="td-modal-form">
          <div :if={@from && @to}>
            <p class="td-field-label">Date range</p>
            <ThamaniDawaWeb.CoreComponents.date_range_picker
              id={"#{@id}-dates"}
              from_name="from"
              from_value={@from}
              to_name="to"
              to_value={@to}
              max="today"
            />
          </div>
          <ThamaniDawaWeb.CoreComponents.input
            type="select"
            id={"#{@id}-columns"}
            name="columns"
            label="Columns"
            value={@columns |> List.first() |> elem(1)}
            options={@columns}
          />
          <p class="td-note">
            The file downloads as CSV and opens in Excel or Google Sheets.<span :if={@count}>{@count} {@noun} match.</span>
          </p>
        </.form>
      </:body>
      <:footer>
        <.td_button type="button" variant="secondary" label="Cancel" phx-click={@on_cancel} />
        <.td_button
          id={"#{@id}-submit"}
          type="submit"
          variant="primary"
          label="Download CSV"
          glyph="download-simple"
          form={"#{@id}-form"}
        />
      </:footer>
    </.td_modal>
    """
  end

  @doc """
  Doop "Download ready" dialog (zkycQlzsjO): shown after a CSV has been
  sent to the browser. Filename, size, and a Done button.
  """
  attr :id, :string, required: true
  attr :filename, :string, required: true
  attr :bytes, :integer, required: true
  attr :on_cancel, JS, required: true

  def td_download_ready(assigns) do
    ~H"""
    <.td_modal
      id={@id}
      show
      width={480}
      title="Your file is ready"
      subtitle="It is saved to your downloads folder."
      on_cancel={@on_cancel}
    >
      <:body>
        <div class="td-download-ready">
          <.td_icon name="check-circle" class="td-download-ready-icon" />
          <div class="td-download-ready-copy">
            <b>{@filename}</b>
            <span class="td-muted">{format_download_bytes(@bytes)} · ready</span>
          </div>
        </div>
      </:body>
      <:footer>
        <.td_button type="button" variant="primary" label="Done" phx-click={@on_cancel} />
      </:footer>
    </.td_modal>
    """
  end

  defp format_download_bytes(bytes) when is_integer(bytes) and bytes < 1_000, do: "#{bytes} B"

  defp format_download_bytes(bytes) when is_integer(bytes) and bytes < 1_000_000 do
    kb = bytes / 1_000
    if kb < 10, do: "#{Float.round(kb, 1)} KB", else: "#{round(kb)} KB"
  end

  defp format_download_bytes(bytes) when is_integer(bytes) do
    "#{Float.round(bytes / 1_000_000, 1)} MB"
  end

  defp format_download_bytes(_), do: "—"

  @doc """
  Hidden hook that prints the current page (or a document URL in a hidden
  iframe) and starts a same-origin file download. Keep this mounted while
  the Print or Download-ready overlays can fire, so the events are not lost
  when those dialogs close.
  """
  attr :id, :string, required: true

  def td_browser_file(assigns) do
    ~H"""
    <span id={@id} phx-hook=".TdBrowserFile" hidden></span>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".TdBrowserFile">
      export default {
        mounted() {
          this.handleEvent("td:print", ({url}) => {
            if (url) {
              const frame = document.createElement("iframe")
              frame.setAttribute("hidden", "")
              frame.src = url
              frame.onload = () => {
                try {
                  frame.contentWindow.focus()
                  frame.contentWindow.print()
                } finally {
                  setTimeout(() => frame.remove(), 5000)
                }
              }
              document.body.appendChild(frame)
            } else {
              window.print()
            }
          })
          this.handleEvent("td:file", ({url, filename}) => {
            if (!url) return
            const link = document.createElement("a")
            link.href = url
            if (filename) link.download = filename
            document.body.appendChild(link)
            link.click()
            link.remove()
          })
        }
      }
    </script>
    """
  end

  @doc """
  Doop "Print" dialog (d687xWcrBC): printer, copies, and paper, then
  Cancel / Print. There is no site-printer registry in the product, so the
  only printer option is this computer — Print opens the browser dialog
  (which is also where the user can change the copy count).
  """
  attr :id, :string, required: true
  attr :on_cancel, JS, required: true
  attr :submit, :string, default: "confirm_print"
  attr :printer, :string, default: "browser"
  attr :copies, :integer, default: 1
  attr :paper, :string, default: "a4"
  attr :printer_options, :list, default: [{"This computer", "browser"}]
  attr :paper_options, :list, default: [{"A4", "a4"}, {"80 mm receipt", "80mm"}]

  def td_print(assigns) do
    ~H"""
    <.td_modal
      id={@id}
      show
      width={480}
      title="Print"
      subtitle="Send this document to a printer at your site."
      on_cancel={@on_cancel}
    >
      <:body>
        <.form for={%{}} as={:print} id={"#{@id}-form"} phx-submit={@submit} class="td-modal-form">
          <.td_select
            id={"#{@id}-printer"}
            name="printer"
            label="Printer"
            value={@printer}
            options={@printer_options}
          />
          <div class="td-fgrid is-2">
            <.td_select
              id={"#{@id}-copies"}
              name="copies"
              label="Copies"
              value={@copies}
              options={Enum.map(1..5, &{to_string(&1), &1})}
            />
            <.td_select
              id={"#{@id}-paper"}
              name="paper"
              label="Paper"
              value={@paper}
              options={@paper_options}
            />
          </div>
        </.form>
      </:body>
      <:footer>
        <.td_button type="button" variant="secondary" label="Cancel" phx-click={@on_cancel} />
        <.td_button
          id={"#{@id}-submit"}
          type="submit"
          variant="primary"
          label="Print"
          glyph="printer"
          form={"#{@id}-form"}
        />
      </:footer>
    </.td_modal>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :width, :integer, default: nil
  attr :on_cancel, JS, default: %JS{}
  slot :body, required: true
  slot :footer

  def td_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="td-modal-root"
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
    >
      <div id={"#{@id}-bg"} class="td-modal-scrim" aria-hidden="true"></div>
      <div class="td-modal-stage" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-title"}>
        <.focus_wrap
          id={"#{@id}-container"}
          class="td-modal"
          style={@width && "width: min(#{@width}px, 100%)"}
          phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
          phx-key="escape"
          phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
        >
          <div class="td-modal-hd">
            <div class="td-modal-tt">
              <h2 :if={@title} id={"#{@id}-title"}>{@title}</h2>
              <p :if={@subtitle}>{@subtitle}</p>
            </div>
            <button
              type="button"
              class="td-icon-btn"
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
              aria-label="Close"
            >
              <.td_icon name="x" />
            </button>
          </div>
          <div class="td-modal-bd">{render_slot(@body)}</div>
          <div :if={@footer != []} class="td-modal-ft">{render_slot(@footer)}</div>
        </.focus_wrap>
      </div>
    </div>
    """
  end

  attr :id, :string, default: "sidebar-shell"
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil
  attr :crumb_root, :string, default: nil
  attr :help_path, :string, default: nil
  attr :nav_label, :string, default: "Navigation"
  attr :base_path, :string, default: "/"

  attr :current_scope, :any,
    default: nil,
    doc: "gates the command palette rows by the user's role, like the sidebar links"

  slot :search
  slot :tools
  slot :side
  slot :content

  def td_app_shell(assigns) do
    ~H"""
    <div id={@id} class="td-shl internal-app" phx-hook=".Sidebar">
      <button id="sidebar-backdrop" type="button" class="td-backdrop" aria-label="Close navigation" />
      <div class="td-br">
        <a id="sidebar-brand-link" href="/" aria-label="Thamani Dawa home">
          <img
            id="sidebar-brand-logo"
            class="td-br-word"
            src="/images/logo-transparent.png"
            alt="Thamani Dawa"
          />
          <img class="td-br-mark" src="/images/logo-mark.png" alt="" aria-hidden="true" />
        </a>
        <button
          type="button"
          id="sidebar-toggle"
          class="td-tg"
          aria-label="Collapse sidebar"
          aria-controls="sidebar-aside"
          aria-expanded="true"
        >
          <.td_icon name="sidebar-simple" />
        </button>
      </div>
      <div class="td-tb">
        <div class="td-cr">
          <span :if={@crumb_root} class="td-cr-root">{@crumb_root}</span>
          <i :if={@crumb_root && @crumb}>/</i>
          <span :if={@crumb_parent} class="td-cr-root">{@crumb_parent}</span>
          <i :if={@crumb_parent && @crumb}>/</i>
          <b :if={@crumb}>{@crumb}</b>
        </div>
        <div class="td-tl">
          <.td_icon_button
            id="mobile-sidebar-toggle"
            label="Open navigation"
            aria-controls="sidebar-aside"
            aria-expanded="false"
          >
            <:icon><.td_icon name="list" /></:icon>
          </.td_icon_button>
          <%!-- Title bar (brief 4.6): global search with the K shortcut, help,
               notifications, a divider, then the page's primary action. --%>
          <%= if @search != [] do %>
            {render_slot(@search)}
          <% else %>
            <label class="td-search td-global-search" for="td-global-search">
              <.td_icon name="magnifying-glass" />
              <input
                id="td-global-search"
                type="search"
                placeholder="Search products, GTINs, patients"
                aria-label="Search"
                autocomplete="off"
              />
              <kbd>⌘K</kbd>
            </label>
          <% end %>
          <.link
            :if={@help_path}
            navigate={@help_path}
            class="td-icon-btn"
            aria-label="Help and product tour"
          >
            <.td_icon name="question" />
          </.link>
          <div class="td-bell-wrap">
            <button
              type="button"
              id="td-notifications-toggle"
              class="td-icon-btn"
              aria-label="Notifications"
              aria-haspopup="dialog"
              aria-expanded="false"
              aria-controls="td-notifications"
            >
              <.td_icon name="bell" />
            </button>
            <div
              id="td-notifications"
              class="td-notifications hidden"
              role="dialog"
              aria-labelledby="td-notifications-title"
            >
              <div class="td-notifications-hd">
                <p id="td-notifications-title">Notifications</p>
                <button type="button" class="td-text-btn" id="td-notifications-mark-read" disabled>
                  Mark all read
                </button>
              </div>
              <div class="td-notifications-empty">
                <p class="td-empty-title">No notifications yet</p>
                <p class="td-note">Stock alerts, requisitions and approvals will appear here.</p>
              </div>
            </div>
          </div>
          <span :if={@tools != []} class="td-vdiv" aria-hidden="true"></span>
          {render_slot(@tools)}
        </div>
      </div>
      <aside id="sidebar-aside" class="td-sd" aria-label={@nav_label}>
        {render_slot(@side)}
      </aside>
      <main class="td-ct">
        <div class="td-page">{render_slot(@content)}</div>
      </main>
    </div>
    <div
      id="td-chrome"
      phx-hook=".ShellChrome"
      data-base-path={@base_path}
      hidden
    >
    </div>
    <div
      :if={@base_path == "/manufacturer"}
      id="td-command-palette"
      class="td-cmd hidden"
      role="dialog"
      aria-modal="true"
      aria-label="Command menu"
    >
      <div class="td-cmd-scrim" data-td-cmd-dismiss></div>
      <div class="td-cmd-panel">
        <div class="td-cmd-pin">
          <.td_icon name="magnifying-glass" />
          <input
            id="td-command-search"
            type="search"
            placeholder="Type a command or search"
            aria-label="Type a command or search"
            autocomplete="off"
          />
          <kbd>Esc</kbd>
        </div>
        <div class="td-cmd-body">
          <p class="td-cmd-gh">Go to</p>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer"><span class="td-cmd-ti"><.td_icon name="squares-four" /></span><span class="td-cmd-t"><b>Dashboard</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer/products"><span class="td-cmd-ti"><.td_icon name="package" /></span><span class="td-cmd-t"><b>Products</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer/inventory"><span class="td-cmd-ti"><.td_icon name="cube" /></span><span class="td-cmd-t"><b>Inventory</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer/shipments"><span class="td-cmd-ti"><.td_icon name="truck" /></span><span class="td-cmd-t"><b>Shipments</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer/aggregations"><span class="td-cmd-ti"><.td_icon name="squares-plus" /></span><span class="td-cmd-t"><b>Aggregation</b></span></.link>
          <.link
            :if={
              ThamaniDawaWeb.Portals.path_accessible?(@current_scope, "/manufacturer/mobile-users")
            }
            class="td-cmd-row"
            data-td-cmd-row
            navigate="/manufacturer/mobile-users"
          ><span class="td-cmd-ti"><.td_icon name="device-mobile-camera" /></span><span class="td-cmd-t"><b>Mobile users</b></span></.link>
          <p class="td-cmd-gh">Actions</p>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer/products"><span class="td-cmd-ti"><.td_icon name="plus" /></span><span class="td-cmd-t"><b>Add product</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate="/manufacturer/aggregations"><span class="td-cmd-ti"><.td_icon name="package" /></span><span class="td-cmd-t"><b>Add SSCC</b></span></.link>
          <p class="td-cmd-gh">Account</p>
          <.link
            :if={ThamaniDawaWeb.Portals.path_accessible?(@current_scope, "/manufacturer/api-keys")}
            class="td-cmd-row"
            data-td-cmd-row
            navigate="/manufacturer/api-keys"
          ><span class="td-cmd-ti"><.td_icon name="key" /></span><span class="td-cmd-t"><b>API keys</b></span></.link>
          <button
            type="button"
            class="td-cmd-row td-cmd-danger"
            data-td-cmd-row
            phx-click={ThamaniDawaWeb.CoreComponents.show_modal("sidebar-logout-confirm")}
          >
            <span class="td-cmd-ti"><.td_icon name="sign-out" /></span>
            <span class="td-cmd-t"><b>Log out</b></span>
          </button>
        </div>
        <div class="td-cmd-ft">
          <span class="td-cmd-hint">↑↓ to move</span>
          <span class="td-cmd-hint">↵ to run</span>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ShellChrome">
      export default {
        mounted() {
          const base = this.el.dataset.basePath || "";
          const manufacturer = base === "/manufacturer";
          const palette = () => document.getElementById("td-command-palette");
          const search = () => document.getElementById("td-command-search");
          const global = () => document.getElementById("td-global-search");
          const bell = () => document.getElementById("td-notifications-toggle");
          const panel = () => document.getElementById("td-notifications");

          const visibleRows = () =>
            [...(palette()?.querySelectorAll("[data-td-cmd-row]") || [])].filter((row) => !row.hidden);

          const setActive = (idx) => {
            const rows = visibleRows();
            rows.forEach((row, i) => row.classList.toggle("on", i === idx));
            rows[idx]?.scrollIntoView({ block: "nearest" });
            this.active = idx;
          };

          const filterRows = () => {
            const q = (search()?.value || "").trim().toLowerCase();
            palette()?.querySelectorAll("[data-td-cmd-row]").forEach((row) => {
              const text = row.textContent.toLowerCase();
              row.hidden = q !== "" && !text.includes(q);
            });
            setActive(0);
          };

          const openPalette = () => {
            const el = palette();
            if (!el) {
              global()?.focus();
              return;
            }
            el.classList.remove("hidden");
            if (search()) {
              search().value = "";
              filterRows();
              search().focus();
            }
          };

          const closePalette = () => {
            palette()?.classList.add("hidden");
          };

          const runActive = () => {
            visibleRows()[this.active || 0]?.click();
          };

          this.active = 0;

          this.onKey = (e) => {
            const metaK = (e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k";
            if (metaK) {
              e.preventDefault();
              if (manufacturer) openPalette();
              else (global() || document.querySelector(".td-tl input[type='search']"))?.focus();
              return;
            }
            if (e.key === "Escape") {
              if (palette() && !palette().classList.contains("hidden")) {
                e.preventDefault();
                closePalette();
              }
              panel()?.classList.add("hidden");
              return;
            }
            if (palette() && !palette().classList.contains("hidden")) {
              if (e.key === "ArrowDown") {
                e.preventDefault();
                setActive(Math.min((this.active || 0) + 1, visibleRows().length - 1));
              } else if (e.key === "ArrowUp") {
                e.preventDefault();
                setActive(Math.max((this.active || 0) - 1, 0));
              } else if (e.key === "Enter") {
                e.preventDefault();
                runActive();
              }
            }
          };

          this.onOpen = () => openPalette();
          this.onSearch = () => filterRows();
          this.onDismiss = (e) => {
            if (e.target.closest("[data-td-cmd-dismiss]")) closePalette();
          };
          this.onBell = (e) => {
            e.stopPropagation();
            const p = panel();
            if (!p) return;
            const open = p.classList.contains("hidden");
            p.classList.toggle("hidden", !open);
            bell()?.setAttribute("aria-expanded", open ? "true" : "false");
          };
          this.onDocClick = (e) => {
            if (!e.target.closest(".td-bell-wrap")) panel()?.classList.add("hidden");
          };

          window.addEventListener("keydown", this.onKey);
          window.addEventListener("td:open-command-palette", this.onOpen);
          search()?.addEventListener("input", this.onSearch);
          palette()?.addEventListener("click", this.onDismiss);
          bell()?.addEventListener("click", this.onBell);
          document.addEventListener("click", this.onDocClick);
        },
        destroyed() {
          window.removeEventListener("keydown", this.onKey);
          window.removeEventListener("td:open-command-palette", this.onOpen);
          document.removeEventListener("click", this.onDocClick);
        }
      }
    </script>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
      export default {
        mounted() {
          const sidebar = () => document.getElementById("sidebar-aside");
          const toggle = () => document.getElementById("sidebar-toggle");
          const mobile = () => document.getElementById("mobile-sidebar-toggle");
          const tip = () => {
            let el = document.getElementById("sidebar-floating-tooltip");
            if (!el) {
              el = document.createElement("div");
              el.id = "sidebar-floating-tooltip";
              el.setAttribute("role", "tooltip");
              el.hidden = true;
              document.body.appendChild(el);
            }
            return el;
          };
          const hideTip = () => {
            const el = document.getElementById("sidebar-floating-tooltip");
            if (el) el.hidden = true;
          };
          const showTip = (target) => {
            if (!this.el.classList.contains("is-collapsed")) return;
            const label = target.getAttribute("data-tooltip");
            if (!label) return;
            const el = tip();
            const rect = target.getBoundingClientRect();
            el.textContent = label;
            el.style.top = `${rect.top + rect.height / 2}px`;
            el.style.left = `${rect.left + 48}px`;
            el.hidden = false;
          };
          const apply = () => {
            const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
            this.el.classList.toggle("is-collapsed", collapsed);
            sidebar()?.classList.toggle("sidebar-collapsed", collapsed);
            toggle()?.setAttribute("aria-expanded", String(!collapsed));
            toggle()?.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
            if (collapsed) {
              document.getElementById("distributor-nav-items")?.classList.remove("hidden");
            } else {
              hideTip();
            }
          };
          apply();
          this.onClick = (event) => {
            const distributorToggle = event.target.closest("#distributor-nav-toggle");
            if (distributorToggle) {
              if (this.el.classList.contains("is-collapsed")) return;
              const items = document.getElementById("distributor-nav-items");
              const expanded = items?.classList.toggle("hidden") === false;
              distributorToggle.setAttribute("aria-expanded", String(expanded));
              document.getElementById("distributor-nav-group")?.classList.toggle("is-expanded", expanded);
              return;
            }
            if (event.target.closest("#sidebar-toggle")) {
              event.preventDefault();
              const next = localStorage.getItem("sidebar-collapsed") !== "true";
              localStorage.setItem("sidebar-collapsed", String(next));
              apply();
              return;
            }
            if (event.target.closest("#sidebar-backdrop")) {
              this.el.classList.remove("sidebar-mobile-open");
              mobile()?.setAttribute("aria-expanded", "false");
              return;
            }
            if (event.target.closest("#mobile-sidebar-toggle")) {
              const open = !this.el.classList.contains("sidebar-mobile-open");
              this.el.classList.toggle("sidebar-mobile-open", open);
              mobile()?.setAttribute("aria-expanded", String(open));
              return;
            }
            if (event.target.closest("#sidebar-aside a")) {
              this.el.classList.remove("sidebar-mobile-open");
              mobile()?.setAttribute("aria-expanded", "false");
            }
          };
          this.onOver = (event) => {
            const el = event.target.closest("#sidebar-aside [data-tooltip]");
            if (el) showTip(el);
          };
          this.onOut = (event) => {
            const el = event.target.closest("#sidebar-aside [data-tooltip]");
            if (!el) return;
            if (event.relatedTarget && el.contains(event.relatedTarget)) return;
            hideTip();
          };
          this.onFocusIn = (event) => {
            const el = event.target.closest("#sidebar-aside [data-tooltip]");
            if (el) showTip(el);
          };
          this.onFocusOut = () => hideTip();
          this.hideTip = hideTip;
          document.addEventListener("click", this.onClick);
          this.el.addEventListener("mouseover", this.onOver);
          this.el.addEventListener("mouseout", this.onOut);
          this.el.addEventListener("focusin", this.onFocusIn);
          this.el.addEventListener("focusout", this.onFocusOut);
        },
        updated() {
          const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
          this.el.classList.toggle("is-collapsed", collapsed);
          if (!collapsed) this.hideTip?.();
        },
        destroyed() {
          document.removeEventListener("click", this.onClick);
          this.el.removeEventListener("mouseover", this.onOver);
          this.el.removeEventListener("mouseout", this.onOut);
          this.el.removeEventListener("focusin", this.onFocusIn);
          this.el.removeEventListener("focusout", this.onFocusOut);
          this.hideTip?.();
        }
      }
    </script>
    """
  end

  attr :name, :string, required: true
  attr :role, :string, default: nil
  attr :seed, :string, default: "account"
  slot :menu

  def td_account_chip(assigns) do
    ~H"""
    <div id="sidebar-account" class="td-account" phx-hook=".AccountMenu">
      <button
        id="sidebar-account-card"
        type="button"
        class="td-account-chip"
        aria-label="Open account menu"
        aria-haspopup="menu"
        aria-controls="sidebar-account-dropdown"
        phx-click={JS.toggle(to: "#sidebar-account-dropdown", display: "flex")}
        phx-click-away={JS.hide(to: "#sidebar-account-dropdown")}
      >
        <.td_orb seed={@seed} size={28} />
        <span class="nav-label">
          <span id="sidebar-profile" class="td-account-name">{@name}</span>
          <span :if={@role} class="td-account-role">{@role}</span>
        </span>
        <span class="td-account-more nav-label"><.td_icon name="dots-three" /></span>
      </button>
      <div
        id="sidebar-account-dropdown"
        class="td-account-menu"
        role="menu"
        aria-label="Account"
      >
        {render_slot(@menu)}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AccountMenu">
      // Keyboard for the account menu (SHELL-ACCOUNT): Enter/Space on the
      // chip opens it on the first row, arrows move and wrap, Home/End jump,
      // Escape closes and returns focus to the chip, Tab closes.
      export default {
        mounted() {
          const chip = this.el.querySelector("#sidebar-account-card")
          const menu = this.el.querySelector("#sidebar-account-dropdown")
          const items = () =>
            Array.from(menu.querySelectorAll("[role^=menuitem]")).filter((el) => el.offsetParent !== null)
          const isOpen = () => getComputedStyle(menu).display !== "none"
          const close = (refocus) => {
            menu.hidden = false
            menu.style.display = "none"
            chip.setAttribute("aria-expanded", "false")
            if (refocus) chip.focus()
          }
          chip.setAttribute("aria-expanded", "false")
          chip.addEventListener("click", () =>
            requestAnimationFrame(() => chip.setAttribute("aria-expanded", String(isOpen())))
          )
          chip.addEventListener("keydown", (e) => {
            if (e.key === "Enter" || e.key === " " || e.key === "ArrowUp" || e.key === "ArrowDown") {
              if (e.key.startsWith("Arrow")) { e.preventDefault(); chip.click() }
              requestAnimationFrame(() => isOpen() && items()[0]?.focus())
            }
          })
          menu.addEventListener("keydown", (e) => {
            const list = items()
            const i = list.indexOf(document.activeElement)
            if (e.key === "ArrowDown") { e.preventDefault(); list[(i + 1) % list.length]?.focus() }
            else if (e.key === "ArrowUp") { e.preventDefault(); list[(i - 1 + list.length) % list.length]?.focus() }
            else if (e.key === "Home") { e.preventDefault(); list[0]?.focus() }
            else if (e.key === "End") { e.preventDefault(); list[list.length - 1]?.focus() }
            else if (e.key === "Escape") { e.preventDefault(); close(true) }
            else if (e.key === "Tab") { close(false) }
          })
        }
      }
    </script>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :back, :any, default: nil
  slot :actions
  slot :tabs
  slot :filters
  slot :inner_block, required: true

  def td_list_page(assigns) do
    ~H"""
    <section class="td-recipe td-list-page">
      <.td_page_header title={@title} subtitle={@subtitle} back={@back}>
        <:actions>{render_slot(@actions)}</:actions>
      </.td_page_header>
      <nav :if={@tabs != []} class="td-tabs">{render_slot(@tabs)}</nav>
      <div :if={@filters != []} class="td-toolbar">
        {render_slot(@filters)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :back, :any, default: nil
  slot :actions
  slot :body
  slot :inner_block

  def td_detail_page(assigns) do
    ~H"""
    <section class="td-recipe">
      <.td_page_header title={@title} subtitle={@subtitle} back={@back}>
        <:actions>{render_slot(@actions)}</:actions>
      </.td_page_header>
      <div :if={@inner_block != []} class="td-kv-grid">{render_slot(@inner_block)}</div>
      {render_slot(@body)}
    </section>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :on_cancel, JS, default: %JS{}
  attr :submit, :string, default: "Save"
  slot :inner_block, required: true

  def td_overlay_form(assigns) do
    ~H"""
    <.td_modal id={@id} show={@show} title={@title} subtitle={@subtitle} on_cancel={@on_cancel}>
      <:body>{render_slot(@inner_block)}</:body>
      <:footer>
        <.td_button
          type="button"
          variant="secondary"
          label="Cancel"
          phx-click={JS.exec("data-cancel", to: "##{@id}")}
        />
        <.td_button type="submit" variant="primary" label={@submit} form={"#{@id}-form"} />
      </:footer>
    </.td_modal>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :body, :string, required: true
  attr :confirm, :string, default: "Confirm"
  attr :confirm_id, :string, default: nil
  attr :confirm_value_id, :any, default: nil
  attr :on_cancel, JS, default: %JS{}
  attr :confirm_click, :string, required: true

  def td_confirm(assigns) do
    ~H"""
    <.td_modal id={@id} show={@show} title={@title} subtitle={@subtitle} on_cancel={@on_cancel}>
      <:body>
        <p class="td-note">{@body}</p>
      </:body>
      <:footer>
        <.td_button type="button" variant="secondary" label="Cancel" phx-click={@on_cancel} />
        <.td_button
          id={@confirm_id}
          type="button"
          variant="danger-confirm"
          label={@confirm}
          phx-click={@confirm_click}
          phx-value-id={@confirm_value_id}
        />
      </:footer>
    </.td_modal>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil

  slot :col, required: true do
    attr :label, :string
  end

  slot :action
  slot :empty

  def td_data_table(assigns) do
    ~H"""
    <div class="td-data">
      <table>
        <thead>
          <tr>
            <th :for={col <- @col}>{col[:label]}</th>
            <th :if={@action != []}></th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr :if={@empty != []} id={"#{@id}-empty"} class="td-data-empty">
            <td colspan={length(@col) + if(@action != [], do: 1, else: 0)}>{render_slot(@empty)}</td>
          </tr>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td :for={col <- @col}>{render_slot(col, row)}</td>
            <td :if={@action != []}>{render_slot(@action, row)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :title, :string, default: nil
  slot :inner_block, required: true

  def td_mode_picker(assigns) do
    ~H"""
    <div class="td-mode">
      <h2 :if={@title}>{@title}</h2>
      <div class="td-mode-grid">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :steps
  slot :inner_block, required: true
  slot :footer

  def td_auth_card(assigns) do
    ~H"""
    <section class="td-auth-card">
      <div :if={@steps != []} class="td-steps">{render_slot(@steps)}</div>
      <h1>{@title}</h1>
      <p :if={@subtitle} class="td-note">{@subtitle}</p>
      {render_slot(@inner_block)}
      <div :if={@footer != []} class="td-auth-card-foot">{render_slot(@footer)}</div>
    </section>
    """
  end

  defp error_text({msg, opts}) when is_binary(msg) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp error_text(other), do: to_string(other)

  # Doop TD Orb: a seeded radial gradient. The hue comes from a hash of the
  # seed, so the same person always gets the same orb.
  defp show_modal(id) when is_binary(id) do
    JS.show(to: "##{id}")
    |> JS.show(to: "##{id}-bg")
    |> JS.show(to: "##{id}-container")
    |> JS.focus_first(to: "##{id}-container")
  end

  defp hide_modal(id) do
    JS.hide(to: "##{id}-bg")
    |> JS.hide(to: "##{id}-container")
    |> JS.hide(to: "##{id}")
  end

  @doc """
  TD Peek (Doop `cuo1ccz0cc`, spec `lUbiG4NO-X`): the hover card for a
  record ID (order, shipment, SSCC, customer, GLN, batch). Shows the facts a
  person would otherwise click through for, plus one Open action. Wrap the ID
  with `td_pid/1`, which places this card under it and opens it 300ms after
  hover or on focus; Esc closes it. Fill `:row` with label/value facts.
  """
  attr :id, :string, default: nil
  attr :kind, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :hint, :string, default: "Click the ID to open it"
  attr :icon, :string, default: "clipboard-text"
  attr :mono, :boolean, default: false

  slot :badge
  slot :action

  slot :row do
    attr :label, :string, required: true
    attr :mono, :boolean
  end

  def td_peek(assigns) do
    ~H"""
    <div id={@id} class="td-peek" data-mono={to_string(@mono)} role="tooltip">
      <div class="td-peek-hd">
        <span class="td-peek-tile"><.td_icon name={@icon} /></span>
        <div class="td-peek-tt">
          <span class="td-peek-k">{@kind}</span>
          <b>{@title}</b>
        </div>
        <span :if={@badge != []} class="td-peek-bd">{render_slot(@badge)}</span>
      </div>
      <span :if={@subtitle} class="td-peek-sub">{@subtitle}</span>
      <div :if={@row != []} class="td-peek-rows">
        <div :for={row <- @row} class="td-peek-row" data-mono={to_string(Map.get(row, :mono, false))}>
          <span class="td-peek-l">{row.label}</span>
          <span class="td-peek-v">{render_slot(row)}</span>
        </div>
      </div>
      <div class="td-peek-ft">
        <span class="td-peek-hint">{@hint}</span>
        <span :if={@action != []} class="td-peek-act">{render_slot(@action)}</span>
      </div>
    </div>
    """
  end

  @doc """
  A dashed-underline record ID that opens a `td_peek/1` card on hover or
  focus. `:peek` holds the card. Clicking the ID follows `navigate` when
  given; inside a clickable table row the click stops at the ID.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :mono, :boolean, default: false
  attr :navigate, :string, default: nil
  attr :align, :string, values: ~w(left right), default: "left"
  slot :peek, required: true

  def td_pid(assigns) do
    ~H"""
    <span id={@id} class={["td-pid-wrap", @align == "right" && "is-right"]} phx-hook="TdPeek">
      <.link
        :if={@navigate}
        navigate={@navigate}
        class={["td-pid", @mono && "td-mono"]}
        aria-describedby={"#{@id}-peek"}
      >{@label}</.link>
      <span
        :if={!@navigate}
        tabindex="0"
        class={["td-pid", @mono && "td-mono"]}
        aria-describedby={"#{@id}-peek"}
      >{@label}</span>
      <span id={"#{@id}-peek"} class="td-peek-pop">{render_slot(@peek)}</span>
    </span>
    """
  end

  @doc """
  The back link at the top of every detail page ("Back to …"). `to` is the
  page's `return_to` when it is a safe in-app path, else the parent list.
  """
  attr :id, :string, default: nil
  attr :to, :string, required: true
  attr :label, :string, required: true

  def td_back_link(assigns) do
    ~H"""
    <div class="td-back">
      <.link id={@id} navigate={@to} class="td-back-link">
        <.td_icon name="arrow-left" class="size-3.5" /> {@label}
      </.link>
    </div>
    """
  end

  @doc """
  The one shared date-range filter chip (Doop `TD DateFilter`, open state in
  "Orders · Created date filter" `QtYrmaQO7u`): presets plus a custom range on
  the TD date picker, in EAT. Use it for every list date filter; never a bare
  `date_range_picker` in a filter row.
  Pushes `set_date_preset` with `%{"field" => field, "value" => preset}` and
  submits `apply_date_range` with `date_from` / `date_to`.
  """
  attr :id, :string, required: true
  attr :field, :string, default: "date"
  attr :label, :string, required: true
  attr :preset, :string, default: ""
  attr :date_from, :string, default: ""
  attr :date_to, :string, default: ""

  def td_date_filter(assigns) do
    assigns =
      assign(
        assigns,
        :shown,
        ThamaniDawaWeb.DateRangeFilter.label(assigns.preset, assigns.date_from, assigns.date_to)
      )

    ~H"""
    <div class="td-chip-wrap" phx-click-away={JS.hide(to: "##{@id}-pop")}>
      <button
        type="button"
        id={"#{@id}-chip"}
        class="td-chip"
        phx-click={JS.toggle(to: "##{@id}-pop")}
        aria-haspopup="dialog"
      >
        <span class="td-chip-label">{@label}</span>
        <span class="td-chip-value">{@shown}</span>
        <.td_icon name="caret-down" />
      </button>
      <div id={"#{@id}-pop"} class="td-popover td-date-filter hidden" role="dialog">
        <div class="td-date-filter-presets">
          <button
            :for={{value, text} <- ThamaniDawaWeb.DateRangeFilter.presets()}
            type="button"
            id={"#{@id}-preset-#{if value == "", do: "any", else: value}"}
            class={["td-menu-item", value == @preset && "is-selected"]}
            phx-click={
              JS.push("set_date_preset", value: %{field: @field, value: value})
              |> JS.hide(to: "##{@id}-pop")
            }
          >
            <span class="flex-1">{text}</span>
            <.td_icon :if={value == @preset} name="check" class="size-3.5" />
          </button>
        </div>
        <form id={"#{@id}-form"} class="td-date-filter-custom" phx-submit="apply_date_range">
          <input type="hidden" name="field" value={@field} />
          <.date_range_picker_proxy id={"#{@id}-range"} date_from={@date_from} date_to={@date_to} />
          <div class="td-date-filter-ft">
            <span class="td-s12">{ThamaniDawaWeb.DateRangeFilter.range_caption(@date_from, @date_to)}</span>
            <span class="flex gap-2">
              <button
                type="button"
                class="td-btn is-secondary"
                phx-click={
                  JS.push("set_date_preset", value: %{field: @field, value: ""})
                  |> JS.hide(to: "##{@id}-pop")
                }
              >
                Clear
              </button>
              <button type="submit" class="td-btn is-primary" phx-click={JS.hide(to: "##{@id}-pop")}>
                Apply
              </button>
            </span>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :date_from, :string, default: ""
  attr :date_to, :string, default: ""

  defp date_range_picker_proxy(assigns) do
    ~H"""
    <ThamaniDawaWeb.CoreComponents.date_range_picker
      id={@id}
      from_name="date_from"
      from_value={@date_from}
      to_name="date_to"
      to_value={@date_to}
      placeholder="Custom range"
    />
    """
  end

  @doc "A seeded orb and a name, for people in tables and activity lists."
  attr :name, :string, required: true
  attr :seed, :any, default: nil

  def td_person_cell(assigns) do
    ~H"""
    <span class="td-person"><.td_orb seed={to_string(@seed || @name)} size={20} /><span>{@name}</span></span>
    """
  end
end
