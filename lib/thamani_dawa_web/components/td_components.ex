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
    ~H"""
    <Phosphor.icon name={@name} weight={@weight} class={@class} />
    """
  end

  attr :variant, :string,
    values: ~w(primary secondary danger danger-confirm),
    default: "secondary"

  attr :size, :string, values: ~w(md lg), default: "md"
  attr :label, :string, default: nil
  attr :glyph, :string, default: nil, doc: "Phosphor icon name shown before the label"

  attr :rest, :global,
    include:
      ~w(href navigate patch method download name value disabled type id form title onclick target rel phx-click phx-value-id phx-value-tier phx-value-from phx-value-to phx-value-mode phx-value-step phx-value-status phx-disable-with phx-submit phx-target phx-hook data-print-target data-print-container data-download-container data-role data-sscc data-gs1-text data-quantity data-gtin data-batch data-production data-expiry data-material-description data-order-number data-from-company data-from-address data-to-company data-to-address data-to-po-box)

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
  attr :rest, :global, include: ~w(id type phx-click)

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
  slot :actions

  def td_page_header(assigns) do
    ~H"""
    <header class="td-page-header">
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="td-header-actions">{render_slot(@actions)}</div>
    </header>
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
  attr :rest, :global, include: ~w(id type phx-click phx-value-mode)

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
  slot :notice, doc: "optional banner above the strips"

  slot :strip, doc: "one TD Stat strip; its children are td_glance_cell" do
    attr :id, :string
  end

  slot :inner_block

  def td_dashboard(assigns) do
    ~H"""
    <section id={@id} class="td-dashboard">
      <.td_page_header title={@title} subtitle={@subtitle}>
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

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  slot :action

  def td_empty(assigns) do
    ~H"""
    <div id={@id} class="td-empty">
      <p class="td-empty-title">{@title}</p>
      <p :if={@hint} class="td-note">{@hint}</p>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  def td_empty_state(assigns), do: td_empty(assigns)

  attr :selected, :boolean, default: false
  attr :title, :string, required: true
  attr :body, :string, default: nil
  attr :rest, :global, include: ~w(type phx-click id phx-target phx-value-mode phx-value-index phx-value-type)

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

  attr :tone, :string, values: ~w(info success warning danger), default: "info"
  attr :text, :string, required: true

  def td_toast(assigns) do
    ~H"""
    <p class={["td-toast", "is-#{@tone}"]} role="status">{@text}</p>
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
  attr :ranges, :list, default: nil
  attr :count, :integer, default: nil
  attr :noun, :string, default: "rows"

  def td_export_modal(assigns) do
    ~H"""
    <ThamaniDawaWeb.CoreComponents.modal
      id={@id}
      show
      size="confirm"
      class="td-export-modal"
      title="Export CSV"
      subtitle="Download the rows that match your current filters."
      on_cancel={@on_cancel}
    >
      <.form for={%{}} as={:export} id={"#{@id}-form"} phx-submit={@submit} class="td-modal-form">
        <ThamaniDawaWeb.CoreComponents.input
          :if={@ranges}
          type="select"
          id={"#{@id}-range"}
          name="range"
          label="Date range"
          value={@ranges |> List.first() |> elem(1)}
          options={@ranges}
        />
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
    </ThamaniDawaWeb.CoreComponents.modal>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
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
            <div id="td-notifications" class="td-notifications hidden" role="dialog" aria-labelledby="td-notifications-title">
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
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer"}><span class="td-cmd-ti"><.td_icon name="squares-four" /></span><span class="td-cmd-t"><b>Dashboard</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/products"}><span class="td-cmd-ti"><.td_icon name="package" /></span><span class="td-cmd-t"><b>Products</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/inventory"}><span class="td-cmd-ti"><.td_icon name="cube" /></span><span class="td-cmd-t"><b>Inventory</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/shipments"}><span class="td-cmd-ti"><.td_icon name="truck" /></span><span class="td-cmd-t"><b>Shipments</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/aggregations"}><span class="td-cmd-ti"><.td_icon name="squares-plus" /></span><span class="td-cmd-t"><b>Aggregation</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/mobile-users"}><span class="td-cmd-ti"><.td_icon name="device-mobile-camera" /></span><span class="td-cmd-t"><b>Mobile users</b></span></.link>
          <p class="td-cmd-gh">Actions</p>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/products"}><span class="td-cmd-ti"><.td_icon name="plus" /></span><span class="td-cmd-t"><b>Add product</b></span></.link>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/aggregations"}><span class="td-cmd-ti"><.td_icon name="package" /></span><span class="td-cmd-t"><b>Add SSCC</b></span></.link>
          <p class="td-cmd-gh">Account</p>
          <.link class="td-cmd-row" data-td-cmd-row navigate={"/manufacturer/api-keys"}><span class="td-cmd-ti"><.td_icon name="key" /></span><span class="td-cmd-t"><b>API keys</b></span></.link>
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
              else global()?.focus();
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
        phx-click={JS.toggle(to: "#sidebar-account-dropdown")}
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
        hidden
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
  slot :actions
  slot :filters
  slot :inner_block, required: true

  def td_list_page(assigns) do
    ~H"""
    <section class="td-recipe">
      <.td_page_header title={@title} subtitle={@subtitle}>
        <:actions>{render_slot(@actions)}</:actions>
      </.td_page_header>
      <div :if={@filters != []} class="td-filter-row">{render_slot(@filters)}</div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def td_detail_page(assigns) do
    ~H"""
    <section class="td-recipe">
      <.td_page_header title={@title} subtitle={@subtitle}>
        <:actions>{render_slot(@actions)}</:actions>
      </.td_page_header>
      <div class="td-kv-grid">{render_slot(@inner_block)}</div>
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
  attr :body, :string, required: true
  attr :confirm, :string, default: "Confirm"
  attr :on_cancel, JS, default: %JS{}
  attr :confirm_click, :string, required: true

  def td_confirm(assigns) do
    ~H"""
    <.td_modal id={@id} show={@show} title={@title} on_cancel={@on_cancel}>
      <:body>
        <p class="td-note">{@body}</p>
      </:body>
      <:footer>
        <.td_button type="button" variant="secondary" label="Cancel" phx-click={@on_cancel} />
        <.td_button
          type="button"
          variant="danger-confirm"
          label={@confirm}
          phx-click={@confirm_click}
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

  attr :title, :string, required: true
  slot :inner_block, required: true

  def td_mode_picker(assigns) do
    ~H"""
    <div class="td-mode">
      <h2>{@title}</h2>
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
end
