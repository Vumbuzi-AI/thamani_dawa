defmodule ThamaniDawaWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: ThamaniDawaWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  attr :variant, :string, values: ~w(primary ghost ghost-edit ghost-delete), default: "ghost"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base =
      case assigns[:variant] do
        "primary" -> "thamani-btn-primary"
        "ghost-edit" -> "thamani-btn-ghost-edit"
        "ghost-delete" -> "thamani-btn-ghost-delete"
        _ -> "thamani-btn-ghost"
      end

    # Merge any caller-supplied class onto the variant base rather than
    # replacing it, so utility classes (margins, alignment) don't strip the
    # button's styling.
    assigns = assign(assigns, :class, [base, assigns[:class]])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={assigns[:value]} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={@id} class="inline-flex items-center gap-2 cursor-pointer">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "checkbox checkbox-sm accent-thamani-forest"}
          {@rest}
        />
        <span class="thamani-label" style="margin-bottom: 0;">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: #C21F17; margin-left: 2px;"
          >*</span>
        </span>
        <select
          id={@id}
          name={@name}
          class={[@class || "thamani-select", @errors != [] && (@error_class || "border-red-600")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, assigns[:value])}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: #C21F17; margin-left: 2px;"
          >*</span>
        </span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "thamani-input",
            @errors != [] && (@error_class || "border-red-600")
          ]}
          style="min-height: 80px; resize: vertical;"
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", assigns[:value])}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: #C21F17; margin-left: 2px;"
          >*</span>
        </span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, assigns[:value])}
          class={[
            @class || "thamani-input",
            @errors != [] && (@error_class || "border-red-600")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  A Thamani-styled date picker: a pill-shaped trigger that opens a flat,
  shadowless calendar popover (Snow White surface, Forest Depths ink, Lime
  Pulse accents). Writes the selected date as an ISO-8601 string into a hidden
  input, so it works inside a `<.form>` exactly like `<.input type="date">`.

  ## Examples

  ```heex
  <.date_picker field={@patient_form[:date_of_birth]} label="Date of birth" max="today" />
  ```
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :placeholder, :string, default: "Choose a date"
  attr :required, :boolean, default: false

  attr :max, :string,
    default: nil,
    doc: ~S(pass "today" to disable future dates — useful for dates of birth)

  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct, e.g. @form[:date_of_birth]"

  def date_picker(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> date_picker()
  end

  def date_picker(assigns) do
    assigns = assign(assigns, :iso_value, date_iso(assigns[:value]))

    ~H"""
    <div id={"#{@id}-dp"} class="mb-3 relative" phx-hook=".DatePicker" data-max={@max}>
      <label :if={@label} for={@id} class="thamani-label">
        {@label}<span
          :if={@required}
          aria-hidden="true"
          style="color: #b91c1c; margin-left: 2px;"
        >*</span>
      </label>

      <input type="hidden" name={@name} id={@id} value={@iso_value} data-dp-input />

      <button
        type="button"
        data-dp-trigger
        class={[
          "thamani-input w-full flex items-center justify-between gap-2 text-left cursor-pointer",
          @errors != [] && "border-red-600"
        ]}
      >
        <span data-dp-display data-placeholder={@placeholder} style="color: var(--thamani-forest);">
          {display_date(@iso_value) || @placeholder}
        </span>
        <span style="color: var(--thamani-pewter);">
          <.icon name="hero-calendar-days" class="size-4 shrink-0" />
        </span>
      </button>

      <div
        data-dp-pop
        id={"#{@id}-dp-pop"}
        phx-update="ignore"
        hidden
        class="absolute z-50 mt-2 w-72 p-4"
        style="background: var(--thamani-snow); border: 1px solid var(--thamani-stone); border-radius: 16px;"
      >
      </div>

      <.error :for={msg <- @errors}>{msg}</.error>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".DatePicker">
      const MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"]
      const DOW = ["S","M","T","W","T","F","S"]

      export default {
        mounted() { this.setup() },
        updated() { this.syncFromInput() },
        destroyed() {
          document.removeEventListener("click", this.onDocClick)
          document.removeEventListener("keydown", this.onKey)
        },
        minYear() { return this.today.getFullYear() - 120 },
        maxYear() { return this.max ? this.max.getFullYear() : this.today.getFullYear() + 10 },
        setup() {
          this.input = this.el.querySelector("[data-dp-input]")
          this.trigger = this.el.querySelector("[data-dp-trigger]")
          this.display = this.el.querySelector("[data-dp-display]")
          this.pop = this.el.querySelector("[data-dp-pop]")
          this.today = new Date(); this.today.setHours(0,0,0,0)
          this.max = this.el.dataset.max === "today" ? this.today : null
          this.parseValue()
          this.onTrigger = (e) => { e.preventDefault(); e.stopPropagation(); this.toggle() }
          this.onDocClick = (e) => { if (!this.el.contains(e.target)) this.close() }
          this.onKey = (e) => { if (e.key === "Escape") this.close() }
          this.onPopClick = (e) => this.handlePopClick(e)
          this.trigger.addEventListener("click", this.onTrigger)
          this.pop.addEventListener("click", this.onPopClick)
          document.addEventListener("click", this.onDocClick)
          document.addEventListener("keydown", this.onKey)
        },
        syncFromInput() {
          this.input = this.el.querySelector("[data-dp-input]")
          this.display = this.el.querySelector("[data-dp-display]")
          this.parseValue()
          this.renderDisplay()
        },
        parseValue() {
          const v = this.input.value
          if (v && /^\d{4}-\d{2}-\d{2}$/.test(v)) {
            const [y,m,d] = v.split("-").map(Number)
            this.selected = new Date(y, m-1, d)
          } else {
            this.selected = null
          }
          this.renderDisplay()
        },
        iso(date) {
          const y = date.getFullYear()
          const m = String(date.getMonth()+1).padStart(2,"0")
          const d = String(date.getDate()).padStart(2,"0")
          return `${y}-${m}-${d}`
        },
        fmt(date) {
          return date.toLocaleDateString(undefined, {day:"numeric", month:"short", year:"numeric"})
        },
        renderDisplay() {
          if (!this.display) return
          if (this.selected) {
            this.display.textContent = this.fmt(this.selected)
            this.display.style.color = "var(--thamani-forest)"
          } else {
            this.display.textContent = this.display.dataset.placeholder || "Choose a date"
            this.display.style.color = "var(--thamani-pewter)"
          }
        },
        toggle() { this.pop.hasAttribute("hidden") ? this.open() : this.close() },
        open() {
          const base = this.selected || this.today
          this.viewYear = base.getFullYear()
          this.viewMonth = base.getMonth()
          this.mode = "days"
          const css = `
            [data-dp-body] button { transition: background 120ms ease; }
            [data-dp-body] button[data-dp-day]:not(:disabled):hover,
            [data-dp-body] button[data-dp-month]:not(:disabled):hover,
            [data-dp-body] button[data-dp-year]:hover,
            [data-dp-body] button[data-dp-nav]:hover,
            [data-dp-body] button[data-dp-open]:hover { background: var(--thamani-stone); }`
          this.pop.innerHTML = `<style>${css}</style><div data-dp-body></div>`
          this.body = this.pop.querySelector("[data-dp-body]")
          this.renderCalendar()
          this.pop.removeAttribute("hidden")
        },
        close() { this.pop.setAttribute("hidden", "") },
        handlePopClick(e) {
          // Rebuilding the popover detaches the clicked node, so stop the event
          // reaching the document "click-outside" handler (which would then see
          // a detached target and wrongly close the picker).
          e.stopPropagation()
          const nav = e.target.closest("[data-dp-nav]")
          if (nav) {
            e.preventDefault()
            this.viewMonth += parseInt(nav.dataset.dpNav, 10)
            if (this.viewMonth < 0) { this.viewMonth = 11; this.viewYear-- }
            if (this.viewMonth > 11) { this.viewMonth = 0; this.viewYear++ }
            this.renderCalendar()
            return
          }
          const open = e.target.closest("[data-dp-open]")
          if (open) {
            e.preventDefault()
            this.mode = open.dataset.dpOpen
            this.renderCalendar()
            return
          }
          const yr = e.target.closest("[data-dp-year]")
          if (yr && !yr.disabled) {
            e.preventDefault()
            this.viewYear = parseInt(yr.dataset.dpYear, 10)
            if (this.viewMonth > this.maxMonthFor(this.viewYear)) this.viewMonth = this.maxMonthFor(this.viewYear)
            this.mode = "days"
            this.renderCalendar()
            return
          }
          const mo = e.target.closest("[data-dp-month]")
          if (mo && !mo.disabled) {
            e.preventDefault()
            this.viewMonth = parseInt(mo.dataset.dpMonth, 10)
            this.mode = "days"
            this.renderCalendar()
            return
          }
          const day = e.target.closest("[data-dp-day]")
          if (day && !day.disabled) {
            e.preventDefault()
            this.selected = new Date(this.viewYear, this.viewMonth, parseInt(day.dataset.dpDay, 10))
            this.input.value = this.iso(this.selected)
            this.input.dispatchEvent(new Event("input", {bubbles: true}))
            this.renderDisplay()
            this.close()
          }
        },
        maxMonthFor(year) {
          return (this.max && year === this.max.getFullYear()) ? this.max.getMonth() : 11
        },
        renderCalendar() {
          if (this.mode === "years") return this.renderYears()
          if (this.mode === "months") return this.renderMonths()
          this.renderDays()
        },
        listHeader(label) {
          const back = "width:28px;height:28px;border-radius:1000px;display:flex;align-items:center;justify-content:center;cursor:pointer;color:var(--thamani-forest);flex-shrink:0;border:none;font-size:16px;"
          return `<div style="display:flex;align-items:center;gap:4px;margin-bottom:12px;">
              <button type="button" data-dp-open="days" aria-label="Back to days" style="${back}">&#8249;</button>
              <span style="flex:1;text-align:center;font-size:14px;font-weight:500;color:var(--thamani-forest);">${label}</span>
              <span style="width:28px;"></span>
            </div>`
        },
        renderDays() {
          const first = new Date(this.viewYear, this.viewMonth, 1)
          const startDow = first.getDay()
          const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate()
          const pillBtn = "width:28px;height:28px;border-radius:1000px;display:flex;align-items:center;justify-content:center;cursor:pointer;color:var(--thamani-forest);flex-shrink:0;border:none;font-size:16px;"
          const ctrl = "border:1px solid var(--thamani-stone);border-radius:8px;color:var(--thamani-forest);font-size:13px;font-weight:500;padding:6px 10px;cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:8px;"

          let head = `
            <div style="display:flex;align-items:center;gap:6px;margin-bottom:12px;">
              <button type="button" data-dp-nav="-1" aria-label="Previous month" style="${pillBtn}">&#8249;</button>
              <button type="button" data-dp-open="months" style="${ctrl}flex:1;">
                <span>${MONTHS[this.viewMonth]}</span><span style="color:var(--thamani-pewter);">&#9662;</span>
              </button>
              <button type="button" data-dp-open="years" style="${ctrl}">
                <span>${this.viewYear}</span><span style="color:var(--thamani-pewter);">&#9662;</span>
              </button>
              <button type="button" data-dp-nav="1" aria-label="Next month" style="${pillBtn}">&#8250;</button>
            </div>`

          let dow = `<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:2px;margin-bottom:4px;">`
          DOW.forEach(d => { dow += `<span style="text-align:center;font-size:11px;color:var(--thamani-pewter);">${d}</span>` })
          dow += `</div>`

          let grid = `<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:2px;">`
          for (let i = 0; i < startDow; i++) grid += `<span></span>`
          for (let d = 1; d <= daysInMonth; d++) {
            const cur = new Date(this.viewYear, this.viewMonth, d)
            const isSel = this.selected && cur.getTime() === this.selected.getTime()
            const isToday = cur.getTime() === this.today.getTime()
            const disabled = this.max && cur.getTime() > this.max.getTime()
            let style = "width:32px;height:32px;border-radius:1000px;display:flex;align-items:center;justify-content:center;font-size:13px;margin:0 auto;border:none;color:var(--thamani-forest);cursor:pointer;"
            if (disabled) style += "color:#b3b3b3;cursor:not-allowed;"
            else if (isSel) style += "background:var(--thamani-forest);color:var(--thamani-snow);"
            else if (isToday) style += "border:1.5px solid var(--thamani-lime);"
            grid += `<button type="button" data-dp-day="${d}" ${disabled ? "disabled" : ""} style="${style}">${d}</button>`
          }
          grid += `</div>`

          this.body.innerHTML = head + dow + grid
        },
        renderMonths() {
          let head = this.listHeader("Select month")
          let grid = `<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:6px;">`
          const maxMonth = this.maxMonthFor(this.viewYear)
          MONTHS.forEach((name, i) => {
            const isSel = i === this.viewMonth
            const disabled = i > maxMonth
            let style = "padding:10px 0;border:none;border-radius:1000px;font-size:13px;color:var(--thamani-forest);cursor:pointer;text-align:center;"
            if (disabled) style += "color:#b3b3b3;cursor:not-allowed;"
            else if (isSel) style += "background:var(--thamani-forest);color:var(--thamani-snow);font-weight:500;"
            grid += `<button type="button" data-dp-month="${i}" ${disabled ? "disabled" : ""} style="${style}">${name.slice(0,3)}</button>`
          })
          grid += `</div>`
          this.body.innerHTML = head + grid
        },
        renderYears() {
          let head = this.listHeader("Select year")
          let grid = `<div data-dp-years style="position:relative;max-height:196px;overflow-y:auto;display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:2px;">`
          for (let y = this.maxYear(); y >= this.minYear(); y--) {
            const isSel = y === this.viewYear
            let style = "padding:10px 0;border:none;border-radius:1000px;font-size:13px;color:var(--thamani-forest);cursor:pointer;text-align:center;"
            if (isSel) style += "background:var(--thamani-forest);color:var(--thamani-snow);font-weight:500;"
            grid += `<button type="button" data-dp-year="${y}" style="${style}">${y}</button>`
          }
          grid += `</div>`
          this.body.innerHTML = head + grid
          const container = this.pop.querySelector("[data-dp-years]")
          const sel = this.pop.querySelector(`[data-dp-year="${this.viewYear}"]`)
          if (container && sel) container.scrollTop = sel.offsetTop - container.clientHeight / 2 + sel.clientHeight / 2
        }
      }
    </script>
    """
  end

  defp date_iso(%Date{} = date), do: Date.to_iso8601(date)
  defp date_iso(value) when is_binary(value), do: value
  defp date_iso(_), do: ""

  defp display_date(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> Calendar.strftime(date, "%-d %b %Y")
      _ -> nil
    end
  end

  defp display_date(_), do: nil

  @doc """
  Renders a radio-card group for choosing a site capability.

  ## Examples

      <.capability_select
        field={@form[:site_type]}
        options={[{"Pharmacy", "Dispensing & stock", :pharmacy}]}
      />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :options, :list, required: true, doc: "list of {label, description, value} tuples"
  attr :id, :string, default: "site-capability"
  attr :required, :boolean, default: false

  def capability_select(assigns) do
    errors =
      if Phoenix.Component.used_input?(assigns.field),
        do: Enum.map(assigns.field.errors, &translate_error/1),
        else: []

    assigns = assign(assigns, :errors, errors)

    ~H"""
    <fieldset id={@id} class="fieldset mb-4">
      <legend class="label mb-2">
        Capability<span :if={@required} aria-hidden="true" class="text-error ml-0.5">*</span>
      </legend>
      <div class="grid grid-cols-2 gap-2">
        <label
          :for={{label, desc, value} <- @options}
          for={"#{@id}-#{value}"}
          class="card border cursor-pointer p-3"
        >
          <div class="flex items-center gap-2">
            <input
              type="radio"
              id={"#{@id}-#{value}"}
              name={@field.name}
              value={value}
              checked={to_string(@field.value || "") == to_string(value)}
              class="radio radio-sm"
            />
            <div>
              <p class="font-medium text-sm">{label}</p>
              <p class="text-xs opacity-60">{desc}</p>
            </div>
          </div>
        </label>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions
  attr :class, :any, default: nil

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a Thamani design-system pill button.

  Pattern-matched on `variant`:
  - `"primary"` — Forest-green fill, Snow text (main CTAs, form submits)
  - `"ghost"` — Transparent fill, Forest-green border (secondary CTAs on light bg)
  - `"ghost_inv"` — Transparent fill, Snow border (CTAs on dark/Forest bg)
  - `"lime"` — Lime fill, Forest-green text (accent CTAs)

  Renders as `<.link>` when `navigate` or `href` is set, `<button>` otherwise.

  ## Examples

      <.thamani_btn variant="primary" type="submit">Log in</.thamani_btn>
      <.thamani_btn variant="ghost" navigate={~p"/signup"}>Get started</.thamani_btn>
      <.thamani_btn variant="ghost_inv" href="#features">See how it works →</.thamani_btn>
      <.thamani_btn variant="lime" navigate={~p"/login"}>Log in</.thamani_btn>
  """
  attr :variant, :string,
    values: ~w(primary ghost ghost_inv lime),
    default: "primary",
    doc: "button style variant"

  attr :navigate, :string, default: nil, doc: "LiveView navigate href; renders as <.link>"
  attr :href, :string, default: nil, doc: "regular href; renders as <.link>"

  attr :type, :string,
    default: "button",
    doc: "HTML button type attribute (button | submit | reset)"

  attr :class, :any, default: nil, doc: "additional classes appended after variant classes"
  attr :rest, :global, include: ~w(disabled form id phx-click phx-disable-with)

  slot :inner_block, required: true

  def thamani_btn(%{navigate: nav, href: href} = assigns)
      when not is_nil(nav) or not is_nil(href) do
    ~H"""
    <.link
      navigate={@navigate}
      href={@href}
      class={[thamani_btn_classes(@variant), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def thamani_btn(assigns) do
    ~H"""
    <button type={@type} class={[thamani_btn_classes(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  # Each clause maps a variant name to its Tailwind token classes.
  # Colors resolve from the @theme block in app.css — change there, updates everywhere.
  defp thamani_btn_classes("primary"),
    do:
      "inline-flex items-center justify-center px-6 py-[11px] rounded-full bg-thamani-forest text-thamani-snow text-[15px] font-normal no-underline border-0 cursor-pointer transition-transform duration-[160ms] ease-out active:scale-[0.97] hover:opacity-90 w-full"

  defp thamani_btn_classes("ghost"),
    do:
      "inline-flex items-center justify-center px-6 py-[11px] rounded-full bg-transparent text-thamani-forest text-[15px] font-normal no-underline border-[1.5px] border-thamani-forest cursor-pointer transition-transform duration-[160ms] ease-out active:scale-[0.97]"

  defp thamani_btn_classes("ghost_inv"),
    do:
      "inline-flex items-center justify-center px-6 py-[11px] rounded-full bg-transparent text-thamani-snow text-[15px] font-normal no-underline border-[1.5px] border-thamani-snow cursor-pointer transition-transform duration-[160ms] ease-out active:scale-[0.97]"

  defp thamani_btn_classes("lime"),
    do:
      "inline-flex items-center justify-center px-6 py-[11px] rounded-full bg-thamani-lime text-thamani-forest text-[15px] font-medium no-underline border-0 cursor-pointer transition-transform duration-[160ms] ease-out active:scale-[0.97]"

  @doc """
  Renders a Thamani-styled auth-page form field with label and inline error.

  Pattern-matched on `type`:
  - `"email"` / `"text"` / `"url"` — standard text input
  - `"password"` — password input

  Accepts a `Phoenix.HTML.FormField` via `field=` so errors are wired automatically.

  ## Examples

      <.thamani_input field={@form[:email]} type="email" label="Email address"
        placeholder="you@yourpharmacy.com" autocomplete="email" />

      <.thamani_input field={@form[:password]} type="password" label="Password"
        placeholder="••••••••" autocomplete="current-password" />
  """
  attr :field, Phoenix.HTML.FormField,
    required: true,
    doc: "a form field struct, e.g. @form[:email]"

  attr :label, :string, required: true, doc: "visible label text"

  attr :type, :string,
    default: "text",
    values: ~w(text email url password textarea),
    doc: "HTML input type"

  attr :placeholder, :string, default: nil
  attr :autocomplete, :string, default: nil
  attr :class, :any, default: nil, doc: "extra classes on the wrapper div"
  attr :rest, :global, include: ~w(required disabled readonly rows)

  def thamani_input(%{type: "textarea", field: field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &translate_error(&1)))
      |> assign(:input_id, field.id)
      |> assign(:name, field.name)
      |> assign(:value, field.value)

    ~H"""
    <div class={["mb-5", @class]}>
      <div class={[
        "flex items-baseline justify-between mb-2",
        @errors != [] && "mb-1"
      ]}>
        <label
          for={@input_id}
          class="block text-[13px] font-medium text-thamani-forest tracking-[0.01em]"
        >
          {@label}
        </label>
      </div>
      <textarea
        id={@input_id}
        name={@name}
        placeholder={@placeholder}
        class={[
          "w-full box-border px-4 py-3 text-[15px] text-thamani-forest bg-thamani-snow",
          "border-[1.5px] rounded-lg outline-none",
          "transition-[border-color,box-shadow] duration-150 ease-in-out",
          "focus:border-thamani-forest focus:shadow-[0_0_0_3px_rgba(55, 56, 150,0.08)]",
          (@errors != [] && "border-thamani-error") || "border-thamani-stone"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", assigns[:value])}</textarea>
      <p :for={msg <- @errors} class="text-[13px] text-thamani-error mt-1.5">
        {msg}
      </p>
    </div>
    """
  end

  def thamani_input(%{field: field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &translate_error(&1)))
      |> assign(:input_id, field.id)
      |> assign(:name, field.name)
      |> assign(:value, field.value)

    ~H"""
    <div class={["mb-5", @class]}>
      <div class={[
        "flex items-baseline justify-between mb-2",
        @errors != [] && "mb-1"
      ]}>
        <label
          for={@input_id}
          class="block text-[13px] font-medium text-thamani-forest tracking-[0.01em]"
        >
          {@label}
        </label>
      </div>
      <input
        id={@input_id}
        type={@type}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, assigns[:value])}
        placeholder={@placeholder}
        autocomplete={@autocomplete}
        class={[
          "w-full box-border px-4 py-3 text-[15px] text-thamani-forest bg-thamani-snow",
          "border-[1.5px] rounded-lg outline-none",
          "transition-[border-color,box-shadow] duration-150 ease-in-out",
          "focus:border-thamani-forest focus:shadow-[0_0_0_3px_rgba(55, 56, 150,0.08)]",
          (@errors != [] && "border-thamani-error") || "border-thamani-stone"
        ]}
        {@rest}
      />
      <p :for={msg <- @errors} class="text-[13px] text-thamani-error mt-1.5">
        {msg}
      </p>
    </div>
    """
  end

  @doc """
  Renders a modal overlay.

  ## Examples

      <.modal id="site-modal" show on_cancel={JS.patch(~p"/org/sites")}>
        content
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-black/50 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class={["w-full max-w-2xl p-4 sm:p-6 lg:py-8", @class]}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="hidden relative rounded-2xl bg-base-100 shadow-lg ring-1 ring-black/5 p-6 transition"
            >
              <div class="absolute top-4 right-4">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-2 p-2 opacity-40 hover:opacity-70"
                  aria-label="close"
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  ## JS Commands

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}")
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ThamaniDawaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ThamaniDawaWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
