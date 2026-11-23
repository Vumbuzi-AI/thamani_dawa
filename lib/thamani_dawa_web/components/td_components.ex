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
      ~w(href navigate patch method download name value disabled type id form title onclick phx-click phx-value-id phx-value-from phx-value-to phx-value-mode phx-value-step phx-value-status phx-disable-with phx-submit phx-target phx-hook data-print-target data-print-container data-download-container data-role data-sscc data-gs1-text data-quantity data-gtin data-batch data-production data-expiry data-material-description data-order-number data-from-company data-from-address data-to-company data-to-address data-to-po-box)

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
    <.link class={["td-nav-item", @active && "is-active"]} aria-current={@active && "page"} {@rest}>
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
  attr :rest, :global, include: ~w(id type href navigate patch method phx-click)

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
  attr :rest, :global, include: ~w(type phx-click)

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
  attr :rest, :global, include: ~w(href navigate patch)
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

  attr :title, :string, required: true
  attr :hint, :string, default: nil
  slot :action

  def td_empty(assigns) do
    ~H"""
    <div class="td-empty">
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
  attr :rest, :global, include: ~w(type phx-click id phx-target phx-value-mode phx-value-index)

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
  slot :tools
  slot :side
  slot :content

  def td_app_shell(assigns) do
    ~H"""
    <div id={@id} class="td-shl internal-app" phx-hook=".Sidebar">
      <button id="sidebar-backdrop" type="button" class="td-backdrop" aria-label="Close navigation" />
      <div class="td-br">
        <a id="sidebar-brand-link" href="/" aria-label="Thamani Dawa home">
          <img id="sidebar-brand-logo" src="/images/logo-transparent.png" alt="Thamani Dawa" />
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
          <button type="button" class="td-icon-btn" aria-label="Notifications">
            <.td_icon name="bell" />
          </button>
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
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
      export default {
        mounted() {
          const sidebar = () => document.getElementById("sidebar-aside");
          const toggle = () => document.getElementById("sidebar-toggle");
          const mobile = () => document.getElementById("mobile-sidebar-toggle");
          const apply = () => {
            const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
            this.el.classList.toggle("is-collapsed", collapsed);
            sidebar()?.classList.toggle("sidebar-collapsed", collapsed);
            toggle()?.setAttribute("aria-expanded", String(!collapsed));
            toggle()?.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
          };
          apply();
          this.onClick = (event) => {
            const distributorToggle = event.target.closest("#distributor-nav-toggle");
            if (distributorToggle) {
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
          document.addEventListener("click", this.onClick);
        },
        updated() {
          const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
          this.el.classList.toggle("is-collapsed", collapsed);
        },
        destroyed() {
          document.removeEventListener("click", this.onClick);
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
    <div class="td-account">
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
      <div id="sidebar-account-dropdown" class="td-account-menu" hidden>
        {render_slot(@menu)}
      </div>
    </div>
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
