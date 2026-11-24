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
  use ThamaniDawaWeb, :verified_routes

  alias Phoenix.LiveView.JS
  alias ThamaniDawaWeb.Layouts

  @doc """
  Renders a flash as the canon TD toast: an ink pill with a check, sitting in
  the toast region. Info flashes are completed actions, so they use the
  success tone. Error flashes use danger. Click the pill to dismiss it.

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
    assigns = assign(assigns, :timeout_ms, flash_timeout(assigns))
    assigns = assign(assigns, :tone, toast_tone(assigns.kind))

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook="FlashAutoDismiss"
      data-timeout={@timeout_ms}
      data-kind={@kind}
      role={if @tone == "danger", do: "alert", else: "status"}
      class="td-toast-hit"
      {@rest}
    >
      <p class={["td-toast", "is-#{@tone}"]} data-tone={@tone}>
        <span class="td-toast-icon" aria-hidden="true">
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 256 256">
            <path
              fill="currentColor"
              d="M128 24a104 104 0 1 0 104 104A104.11 104.11 0 0 0 128 24m45.66 85.66l-56 56a8 8 0 0 1-11.32 0l-24-24a8 8 0 0 1 11.32-11.32L112 148.69l50.34-50.35a8 8 0 0 1 11.32 11.32"
            />
          </svg>
        </span>
        <span class="td-toast-text"><span :if={@title}>{@title}. </span>{msg}</span>
      </p>
    </div>
    """
  end

  # Completed actions are stored as :info. The toast for those is the green check.
  defp toast_tone(:error), do: "danger"
  defp toast_tone(_kind), do: "success"

  defp flash_timeout(%{id: id}) when id in ["client-error", "server-error"], do: 0
  defp flash_timeout(%{kind: :error}), do: 8_000
  defp flash_timeout(_assigns), do: 5_000

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil

  attr :variant, :string,
    values: ~w(primary ghost ghost-edit ghost-delete destructive danger-confirm),
    default: "ghost"

  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    # One button implementation: map the legacy variants onto the TD kit
    # (Doop TD Button nvEn_C--z3): ghost/ghost-edit -> secondary,
    # ghost-delete/destructive -> danger.
    base =
      case assigns[:variant] do
        "primary" -> "td-btn is-primary is-md"
        v when v in ["ghost-delete", "destructive"] -> "td-btn is-danger is-md"
        "danger-confirm" -> "td-btn is-danger-confirm is-md"
        _ -> "td-btn is-secondary is-md"
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
  Renders a standardized form step/section block card.

  ## Examples

      <.form_block title="1. Test Details">
        ...
      </.form_block>
  """
  attr :title, :string, required: true
  attr :class, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def form_block(assigns) do
    ~H"""
    <section class={["rounded-xl ff-surface-card", @class]}>
      <div class="flex items-center justify-between gap-3 rounded-t-xl border-b border-thamani-stone bg-thamani-canvas px-4 py-3">
        <h3 class="text-base font-semibold text-thamani-forest">{@title}</h3>
        <div>{render_slot(@actions)}</div>
      </div>
      <div class="space-y-4 p-4 sm:p-5">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
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
    values: ~w(checkbox color combobox date datetime-local email file number password
               search select tel text textarea url hidden)

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
    |> assign(field: nil, id: assigns[:id] || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns[:multiple], do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # Every date field in the app is the TD date picker; the browser's native
  # calendar is never rendered.
  def input(%{type: type} = assigns) when type in ~w(date datetime-local) do
    rest = assigns.rest

    assigns =
      assigns
      |> assign(:dp_required, !!rest[:required])
      |> assign(:dp_disabled, !!rest[:disabled])
      |> assign(:dp_max, rest[:max] && to_string(rest[:max]))
      |> assign(:dp_min, rest[:min] && to_string(rest[:min]))
      |> assign(:dp_placeholder, rest[:placeholder] || "Choose a date")

    ~H"""
    <.date_picker
      id={@id}
      name={@name}
      label={@label}
      value={assigns[:value]}
      errors={@errors}
      required={@dp_required}
      disabled={@dp_disabled}
      max={@dp_max}
      min={@dp_min}
      placeholder={@dp_placeholder}
      time={@type == "datetime-local"}
      class={@class}
    />
    """
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={assigns[:id]} name={@name} value={assigns[:value]} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={assigns[:id]} class="inline-flex items-center gap-2 cursor-pointer">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={assigns[:id]}
          name={@name}
          value="true"
          checked={@checked}
          class={
            @class ||
              "size-5 rounded accent-thamani-forest cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
          }
          {@rest}
        />
        <span class="thamani-label" style="margin-bottom: 0;">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    assigns = ensure_id(assigns, "select")

    opts =
      Enum.map(assigns[:options] || [], fn
        {label, value} -> [to_string(label), to_string(value)]
        label -> [to_string(label), to_string(label)]
      end)

    assigns =
      assigns
      |> assign(:opts, opts)
      |> assign(:opts_json, Jason.encode!(opts))

    ~H"""
    <div class="mb-3">
      <label :if={@label} for={"#{@id}-trigger"}>
        <span class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: var(--color-td-danger); margin-left: 2px;"
          >*</span>
        </span>
      </label>
      <div
        id={@id}
        phx-hook=".CustomSelect"
        data-options={@opts_json}
        data-prompt={@prompt || ""}
        class="relative"
      >
        <select
          id={"#{@id}-input"}
          name={@name}
          data-cs-input
          class="hidden"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          <option
            :for={[label, val] <- @opts}
            value={val}
            selected={to_string(val) == to_string(assigns[:value] || "")}
          >
            {label}
          </option>
        </select>
        <button
          type="button"
          id={"#{@id}-trigger"}
          data-cs-trigger
          aria-haspopup="listbox"
          aria-expanded="false"
          disabled={@rest[:disabled]}
          class={[
            "td-select-trigger",
            @errors != [] && (@error_class || "is-error"),
            @rest[:disabled] && "cursor-not-allowed opacity-60",
            @class
          ]}
        >
          <span data-cs-display class="truncate">{@prompt || "Select..."}</span>
          <svg
            data-cs-chevron
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 256 256"
            class="size-4 shrink-0 transition-transform duration-150"
            aria-hidden="true"
          ><path
            fill="currentColor"
            d="m213.66 101.66l-80 80a8 8 0 0 1-11.32 0l-80-80a8 8 0 0 1 11.32-11.32L128 164.69l74.34-74.35a8 8 0 0 1 11.32 11.32"
          /></svg>
        </button>
        <div
          data-cs-dropdown
          role="listbox"
          class="td-select-pop hidden"
        >
          <div class="td-select-pop-search">
            <input
              data-cs-search
              type="text"
              placeholder="Search…"
              autocomplete="off"
            />
          </div>
          <div data-cs-list class="td-select-pop-list"></div>
        </div>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CustomSelect">
        export default {
          mounted() { this.init() },
          updated() { this.syncDisplay() },
          destroyed() {
            document.removeEventListener("click", this.onDocClick)
            document.removeEventListener("keydown", this.onKey)
          },
          init() {
            this.input    = this.el.querySelector("[data-cs-input]")
            this.trigger  = this.el.querySelector("[data-cs-trigger]")
            this.display  = this.el.querySelector("[data-cs-display]")
            this.dropdown = this.el.querySelector("[data-cs-dropdown]")
            this.list     = this.el.querySelector("[data-cs-list]")
            this.search   = this.el.querySelector("[data-cs-search]")
            this.chevron  = this.el.querySelector("[data-cs-chevron]")
            this.renderList("")
            this.syncDisplay()
            this.onTrigger  = (e) => {
              if (this.trigger.disabled) return
              e.preventDefault()
              e.stopPropagation()
              this.toggle()
            }
            this.onDocClick = (e) => { if (!this.el.contains(e.target)) this.close() }
            this.onKey      = (e) => { if (e.key === "Escape") this.close() }
            this.trigger.addEventListener("click", this.onTrigger)
            if (this.search) {
              this.search.addEventListener("input", () => this.renderList(this.search.value))
              this.search.addEventListener("click", (e) => e.stopPropagation())
              this.search.addEventListener("keydown", (e) => {
                if (e.key === "Escape") { e.stopPropagation(); this.close() }
                if (e.key === "ArrowDown") {
                  e.preventDefault()
                  const first = this.list.querySelector("[data-cs-val]")
                  if (first) first.focus()
                }
              })
            }
            document.addEventListener("click", this.onDocClick)
            document.addEventListener("keydown", this.onKey)
          },
          opts()   { return JSON.parse(this.el.dataset.options || "[]") },
          prompt() { return this.el.dataset.prompt || "" },
          renderList(query) {
            this.list.innerHTML = ""
            const q = (query || "").toLowerCase().trim()
            const cur = this.input ? String(this.input.value) : ""
            const allOpts = this.opts()
            const filtered = q === "" ? allOpts : allOpts.filter(([label]) => label.toLowerCase().includes(q))
            const p = this.prompt()
            if (p && q === "") this.list.appendChild(this.makeBtn("", p, false, true))
            if (filtered.length === 0) {
              const empty = document.createElement("div")
              empty.textContent = "No matches"
              empty.style.cssText = "padding:8px 12px;font-size:13px;color:var(--color-td-ink-3);text-align:center;"
              this.list.appendChild(empty)
              return
            }
            filtered.forEach(([label, val]) => {
              this.list.appendChild(this.makeBtn(String(val), label, String(val) === cur, false))
            })
          },
          makeBtn(val, label, active, isPrompt) {
            const b = document.createElement("button")
            b.type = "button"
            b.dataset.csVal = val
            b.textContent = label
            b.tabIndex = 0
            b.className = "td-select-opt"
            b.style.cssText = "background:transparent;"
            if (active) {
              b.style.background = "var(--color-td-hover)"
              b.style.color = "var(--color-td-ink)"
              b.style.fontWeight = "500"
            } else {
              b.style.color = isPrompt ? "var(--color-td-ink-2)" : "var(--color-td-ink)"
              b.onmouseenter = () => { b.style.background = "var(--color-td-hover)" }
              b.onmouseleave = () => { b.style.background = "transparent" }
            }
            b.addEventListener("mousedown", (e) => { e.preventDefault() })
            b.addEventListener("click", (e) => { e.stopPropagation(); this.select(b.dataset.csVal) })
            b.addEventListener("keydown", (e) => {
              if (e.key === "Enter" || e.key === " ") { e.preventDefault(); this.select(b.dataset.csVal) }
              if (e.key === "ArrowDown") { e.preventDefault(); const n = b.nextElementSibling; if (n) n.focus() }
              if (e.key === "ArrowUp")   {
                e.preventDefault()
                const p = b.previousElementSibling
                if (p && p.dataset.csVal !== undefined) p.focus()
                else if (this.search) this.search.focus()
              }
            })
            return b
          },
          select(val) {
            this.input.value = val
            this.input.dispatchEvent(new Event("input",  { bubbles: true }))
            this.input.dispatchEvent(new Event("change", { bubbles: true }))
            this.renderList("")
            this.syncDisplay()
            this.close()
          },
          syncDisplay() {
            if (!this.input || !this.display) return
            const val   = String(this.input.value)
            const match = this.opts().find(([, v]) => String(v) === val)
            if (match) {
              this.display.textContent = match[0]
              this.display.style.color = "var(--color-td-ink)"
            } else {
              this.display.textContent = this.prompt() || "Select..."
              this.display.style.color = "var(--color-td-ink-3)"
            }
          },
          toggle() { this.dropdown.classList.contains("hidden") ? this.open() : this.close() },
          open() {
            if (this.search) this.search.value = ""
            this.renderList("")
            this.dropdown.classList.remove("hidden")
            // Flip above the trigger when the viewport has no room below
            // (selects near a modal footer or the bottom of the screen).
            this.dropdown.classList.remove("is-up")
            const r = this.trigger.getBoundingClientRect()
            const h = this.dropdown.offsetHeight
            if (window.innerHeight - r.bottom < h + 12 && r.top > h + 12) this.dropdown.classList.add("is-up")
            this.trigger.setAttribute("aria-expanded", "true")
            if (this.chevron) this.chevron.style.transform = "rotate(180deg)"
            setTimeout(() => { if (this.search) this.search.focus() }, 10)
          },
          close() {
            this.dropdown.classList.add("hidden")
            this.trigger.setAttribute("aria-expanded", "false")
            if (this.chevron) this.chevron.style.transform = ""
            if (this.search) this.search.value = ""
          }
        }
      </script>
    </div>
    """
  end

  def input(%{type: "combobox"} = assigns) do
    assigns = ensure_id(assigns, "cb")

    opts =
      Enum.map(assigns[:options] || [], fn
        {label, value} -> [to_string(label), to_string(value)]
        label -> [to_string(label), to_string(label)]
      end)

    assigns = assign(assigns, :opts_json, Jason.encode!(opts))

    ~H"""
    <div class="mb-3">
      <label :if={@label} for={@id}>
        <span class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: var(--color-td-danger); margin-left: 2px;"
          >*</span>
        </span>
      </label>
      <div
        id={"#{@id}-cb"}
        phx-hook=".CustomCombobox"
        data-options={@opts_json}
        class="relative"
      >
        <input
          type="text"
          id={@id}
          name={@name}
          value={to_string(assigns[:value] || "")}
          autocomplete="off"
          data-cb-input
          class={[
            "thamani-input",
            @class,
            @errors != [] && (@error_class || "border-red-600")
          ]}
          {@rest}
        />
        <div
          data-cb-dropdown
          role="listbox"
          class="td-select-pop hidden"
        >
          <div data-cb-list class="td-select-pop-list"></div>
        </div>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CustomCombobox">
        export default {
          mounted() { this.init() },
          updated() {},
          destroyed() {
            document.removeEventListener("click", this.onDocClick)
            document.removeEventListener("keydown", this.onKey)
          },
          init() {
            this.input    = this.el.querySelector("[data-cb-input]")
            this.dropdown = this.el.querySelector("[data-cb-dropdown]")
            this.list     = this.el.querySelector("[data-cb-list]")
            this.onDocClick = (e) => { if (!this.el.contains(e.target)) this.close() }
            this.onKey      = (e) => { if (e.key === "Escape") { this.close(); this.input.blur() } }
            this.input.addEventListener("focus", () => { this.renderList(this.input.value); this.open() })
            this.input.addEventListener("input", () => { this.renderList(this.input.value); this.open() })
            this.input.addEventListener("keydown", (e) => {
              if (e.key === "ArrowDown") {
                e.preventDefault()
                const first = this.list.querySelector("button")
                if (first) first.focus()
              }
            })
            document.addEventListener("click", this.onDocClick)
            document.addEventListener("keydown", this.onKey)
          },
          opts() { return JSON.parse(this.el.dataset.options || "[]") },
          renderList(query) {
            this.list.innerHTML = ""
            const q = (query || "").toLowerCase().trim()
            const filtered = q === "" ? this.opts() : this.opts().filter(([label]) => label.toLowerCase().includes(q))
            if (filtered.length === 0) {
              if (q !== "") {
                const empty = document.createElement("div")
                empty.textContent = "No matches. Press Enter to add"
                empty.style.cssText = "padding:8px 12px;font-size:13px;color:var(--color-td-ink-3);text-align:center;"
                this.list.appendChild(empty)
                this.open()
              } else {
                this.close()
              }
              return
            }
            filtered.forEach(([label, val]) => {
              const b = document.createElement("button")
              b.type = "button"
              b.dataset.cbLabel = label
              b.dataset.cbVal = val
              b.textContent = label
              b.tabIndex = 0
              b.style.cssText = "display:block;width:100%;text-align:left;padding:8px 12px;font-size:14px;cursor:pointer;background:transparent;border:0;color:var(--color-td-accent);transition:background 80ms;outline:none;"
              b.onmouseenter = () => { b.style.background = "var(--color-td-hover)" }
              b.onmouseleave = () => { b.style.background = "transparent" }
              b.addEventListener("mousedown", (e) => { e.preventDefault() })
              b.addEventListener("click", () => {
                this.input.value = b.dataset.cbVal
                this.input.dispatchEvent(new Event("input",  { bubbles: true }))
                this.input.dispatchEvent(new Event("change", { bubbles: true }))
                this.close()
              })
              b.addEventListener("keydown", (e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault()
                  this.input.value = b.dataset.cbVal
                  this.input.dispatchEvent(new Event("input",  { bubbles: true }))
                  this.input.dispatchEvent(new Event("change", { bubbles: true }))
                  this.close()
                }
                if (e.key === "ArrowDown") { e.preventDefault(); const n = b.nextElementSibling; if (n) n.focus() }
                if (e.key === "ArrowUp")   { e.preventDefault(); const p = b.previousElementSibling; if (p) p.focus(); else this.input.focus() }
              })
              this.list.appendChild(b)
            })
            this.open()
          },
          open()  { this.dropdown.classList.remove("hidden") },
          close() { this.dropdown.classList.add("hidden") }
        }
      </script>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = ensure_id(assigns)

    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: var(--color-td-danger); margin-left: 2px;"
          >*</span>
        </span>
        <textarea
          id={@id}
          name={@name}
          class={[
            "thamani-input",
            @class,
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
    assigns = ensure_id(assigns)

    ~H"""
    <div class="mb-3">
      <label for={@id}>
        <span :if={@label} class="thamani-label">
          {@label}<span
            :if={@rest[:required]}
            aria-hidden="true"
            style="color: var(--color-td-danger); margin-left: 2px;"
          >*</span>
        </span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, assigns[:value])}
          class={[
            "thamani-input",
            @class,
            @errors != [] && (@error_class || "border-red-600")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp ensure_id(assigns, prefix \\ "input") do
    cond do
      assigns[:id] ->
        assigns

      name = assigns[:name] ->
        clean_name = name |> to_string() |> String.replace(~r/[^\w-]/, "_")
        assign(assigns, :id, "#{prefix}-#{clean_name}")

      true ->
        assign(assigns, :id, "#{prefix}-#{System.unique_integer([:positive])}")
    end
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="validation-error mt-1.5 flex items-center gap-2 text-sm text-thamani-error">
      <.icon name="hero-exclamation-circle" class="size-5 shrink-0 text-thamani-error" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  The one date field for the whole app (Doop TD DatePicker anatomy): a 32px
  TD trigger showing `23 Nov 2026`, and a month calendar popover with Phosphor
  carets, today and selected states, and Clear / Today text actions.   The month
  name opens the twelve months. The year opens twelve years in one click.
  Choosing a month or a year returns to that month's days. From the year
  grid, the range title opens the months. The value
  is submitted as ISO `yyyy-mm-dd` in a hidden input, so changesets, `phx-change`
  and `phx-submit` keep working unchanged. `<.input>` and `<.td_input>` with the
  date type render this component too, so the browser's native calendar never
  appears (guarded by `NoNativeDateInputsTest`).

  Keyboard: Enter, Space or ArrowDown on the trigger opens it; arrows move a day
  or a week, PageUp/PageDown a month (Shift for a year), Home/End the week,
  Enter selects, Escape closes and returns focus to the trigger.

  The popover is absolutely positioned inside the field (like `.td-select-pop`),
  flips above the trigger when there is no room below, and sits in the layer
  above modal content, so it is never clipped inside a modal. All visuals come
  from `--td-dp-*` custom properties in `app.css`.

  ## Examples

  ```heex
  <.date_picker field={@patient_form[:date_of_birth]} label="Date of birth" max="today" />
  <.date_picker field={@form[:expiry_date]} label="Expiry date" min="today" />
  ```
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any, default: nil
  attr :placeholder, :string, default: "Choose a date"
  attr :required, :boolean, default: false
  attr :disabled, :boolean, default: false

  attr :max, :string,
    default: nil,
    doc: ~S(latest selectable date: "today" or an ISO date)

  attr :min, :string,
    default: nil,
    doc: ~S(earliest selectable date: "today" or an ISO date)

  attr :align, :string,
    default: "left",
    doc: "popover alignment relative to the trigger: 'left' or 'right'"

  attr :time, :boolean,
    default: false,
    doc: "adds a 24-hour HH:MM field; the value is submitted as yyyy-mm-ddTHH:MM (datetime-local)"

  attr :class, :any, default: nil
  attr :errors, :list, default: []
  attr :field, Phoenix.HTML.FormField, doc: "a form field struct, e.g. @form[:date_of_birth]"

  def date_picker(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns[:id] || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:name, field.name)
    |> assign(:value, field.value)
    |> date_picker()
  end

  def date_picker(assigns) do
    assigns =
      assigns
      |> ensure_id("dp")
      |> assign_new(:max, fn -> nil end)
      |> assign_new(:min, fn -> nil end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:required, fn -> false end)
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:placeholder, fn -> "Choose a date" end)
      |> assign_new(:errors, fn -> [] end)
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:align, fn -> "left" end)
      |> assign_new(:time, fn -> false end)

    {date_part, time_part} = date_time_parts(assigns[:value])

    assigns =
      assigns
      |> assign(
        :iso_value,
        if(assigns.time, do: date_time_value(date_part, time_part), else: date_part)
      )
      |> assign(:time_value, time_part)
      |> assign(:display, display_date(date_part))

    ~H"""
    <div
      id={"#{@id}-dp"}
      class={[
        "td-dp",
        @time && "is-datetime",
        @align == "right" && "is-right",
        @errors != [] && "is-error",
        @class
      ]}
      phx-hook=".DatePicker"
      data-dp-mode={if @time, do: "datetime", else: "single"}
      data-max={@max}
      data-min={@min}
    >
      <label :if={@label} for={"#{@id}-trigger"} class="thamani-label">
        {@label}<span
          :if={@required}
          aria-hidden="true"
          style="color: var(--color-td-danger); margin-left: 2px;"
        >*</span>
      </label>

      <input
        type="text"
        name={@name}
        id={@id}
        value={@iso_value}
        data-dp-input
        required={@required}
        tabindex="-1"
        aria-hidden="true"
        class="td-dp-value"
      />

      <div class="td-dp-row">
        <button
          type="button"
          id={"#{@id}-trigger"}
          data-dp-trigger
          class="td-dp-trigger"
          aria-haspopup="dialog"
          aria-expanded="false"
          aria-controls={"#{@id}-dp-pop"}
          aria-invalid={@errors != [] && "true"}
          disabled={@disabled}
        >
          <span
            data-dp-display
            data-placeholder={@placeholder}
            class={["td-dp-display", is_nil(@display) && "is-placeholder"]}
          >
            {@display || @placeholder}
          </span>
          <ThamaniDawaWeb.TDComponents.td_icon name="calendar-blank" class="td-dp-icon" />
        </button>
        <input
          :if={@time}
          type="text"
          id={"#{@id}-time"}
          data-dp-time
          value={@time_value}
          inputmode="numeric"
          maxlength="5"
          placeholder="HH:MM"
          autocomplete="off"
          aria-label={if @label, do: "#{@label} time (24-hour)", else: "Time (24-hour)"}
          disabled={@disabled}
          class="td-dp-time"
        />
      </div>

      <div
        data-dp-pop
        id={"#{@id}-dp-pop"}
        class="td-dp-pop"
        role="dialog"
        aria-modal="false"
        aria-label={if @label, do: "Choose #{String.downcase(@label)}", else: "Choose a date"}
        phx-update="ignore"
        hidden
      >
      </div>

      <.error :for={msg <- @errors}>{msg}</.error>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".DatePicker">
      // One hook for the single, date-time and range variants of the TD DatePicker.
      const MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"]
      const SHORT = MONTHS.map(m => m.slice(0, 3))
      const DOW = ["Mo","Tu","We","Th","Fr","Sa","Su"]
      const CARET_L = '<svg aria-hidden="true" viewBox="0 0 256 256" width="14" height="14"><path fill="currentColor" d="M165.66 202.34a8 8 0 0 1-11.32 11.32l-80-80a8 8 0 0 1 0-11.32l80-80a8 8 0 0 1 11.32 11.32L91.31 128Z"/></svg>'
      const CARET_R = '<svg aria-hidden="true" viewBox="0 0 256 256" width="14" height="14"><path fill="currentColor" d="m181.66 133.66l-80 80a8 8 0 0 1-11.32-11.32L164.69 128L90.34 53.66a8 8 0 0 1 11.32-11.32l80 80a8 8 0 0 1 0 11.32"/></svg>'

      const sameDay = (a, b) => !!(a && b && a.getTime() === b.getTime())
      const parseIso = (v) => {
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(v || "")
        return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null
      }
      const TIME = /^([01]\d|2[0-3]):[0-5]\d$/

      export default {
        mounted() { this.setup() },
        updated() { this.syncFromInput() },
        destroyed() { document.removeEventListener("click", this.onDocClick, true) },
        setup() {
          this.mode = this.el.dataset.dpMode || "single"
          this.pop = this.el.querySelector("[data-dp-pop]")
          this.today = new Date(); this.today.setHours(0, 0, 0, 0)
          this.bind()
          this.readBounds()
          this.parseValue()
          this.onDocClick = (e) => { if (!this.el.contains(e.target)) this.close(false) }
          this.el.addEventListener("click", (e) => {
            if (e.target.closest("[data-dp-trigger]")) { e.preventDefault(); this.toggle() }
          })
          this.el.addEventListener("keydown", (e) => {
            if (!e.target.closest("[data-dp-trigger]")) return
            if (e.key === "ArrowDown" || ((e.key === "Enter" || e.key === " ") && this.isClosed())) {
              e.preventDefault(); this.open()
            }
          })
          this.el.addEventListener("input", (e) => { if (e.target.matches("[data-dp-time]")) this.onTime(e.target) })
          this.pop.addEventListener("click", (e) => this.handleClick(e))
          this.pop.addEventListener("keydown", (e) => this.handleKey(e))
          document.addEventListener("click", this.onDocClick, true)
        },
        // LiveView patches can replace the field's children, so look them up again each time.
        bind() {
          this.trigger = this.el.querySelector("[data-dp-trigger]")
          this.display = this.el.querySelector("[data-dp-display]")
          this.timeEl = this.el.querySelector("[data-dp-time]")
          this.input = this.el.querySelector("[data-dp-input]")
          this.inFrom = this.el.querySelector('[data-dp-input="from"]')
          this.inTo = this.el.querySelector('[data-dp-input="to"]')
        },
        readBounds() {
          const b = (v) => v === "today" ? this.today : parseIso(v)
          this.max = b(this.el.dataset.max)
          this.min = b(this.el.dataset.min)
        },
        syncFromInput() {
          this.bind(); this.readBounds()
          if (this.isClosed()) this.parseValue()
          else this.trigger.setAttribute("aria-expanded", "true")
        },
        parseValue() {
          if (this.mode === "range") {
            this.start = parseIso(this.inFrom && this.inFrom.value)
            this.end = parseIso(this.inTo && this.inTo.value)
          } else {
            const v = this.input ? this.input.value : ""
            this.selected = parseIso(v)
            if (this.timeEl && document.activeElement !== this.timeEl) {
              const t = (v.split("T")[1] || "").slice(0, 5)
              if (t) this.timeEl.value = t
            }
          }
          this.renderDisplay()
        },
        iso(d) { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}` },
        fmt(d) { return `${d.getDate()} ${SHORT[d.getMonth()]} ${d.getFullYear()}` },
        displayText() {
          if (this.mode !== "range") return this.selected ? this.fmt(this.selected) : null
          if (this.start && this.end) return `${this.fmt(this.start)} – ${this.fmt(this.end)}`
          if (this.start) return `From ${this.fmt(this.start)}`
          if (this.end) return `Until ${this.fmt(this.end)}`
          return null
        },
        renderDisplay() {
          if (!this.display) return
          const text = this.displayText()
          this.display.textContent = text || this.display.dataset.placeholder || "Choose a date"
          this.display.classList.toggle("is-placeholder", !text)
        },
        hasValue() { return this.mode === "range" ? !!(this.start || this.end) : !!this.selected },
        disabledDay(d) {
          return !!((this.max && d.getTime() > this.max.getTime()) || (this.min && d.getTime() < this.min.getTime()))
        },
        isClosed() { return this.pop.hasAttribute("hidden") },
        toggle() { this.isClosed() ? this.open() : this.close(true) },
        open() {
          const anchor = this.mode === "range" ? (this.start || this.end) : this.selected
          this.focusDate = new Date((anchor || this.clampToBounds(this.today)).getTime())
          this.mode === "range" && (this.pending = null)
          this.view = "days"
          this.render()
          this.pop.removeAttribute("hidden")
          this.el.classList.add("is-open")
          this.trigger.setAttribute("aria-expanded", "true")
          this.place()
          this.focusActive()
        },
        close(returnFocus) {
          if (this.isClosed()) return
          this.pop.setAttribute("hidden", "")
          this.el.classList.remove("is-open", "is-up")
          this.trigger.setAttribute("aria-expanded", "false")
          if (this.mode === "range" && this.pending) { this.pending = null; this.parseValue() }
          if (returnFocus) this.trigger.focus()
        },
        clampToBounds(d) {
          if (this.max && d > this.max) return new Date(this.max.getTime())
          if (this.min && d < this.min) return new Date(this.min.getTime())
          return d
        },
        // Flip above the field when the viewport has no room below (same rule as .td-select-pop).
        place() {
          this.el.classList.remove("is-up")
          const t = this.trigger.getBoundingClientRect()
          const h = this.pop.offsetHeight
          if (t.bottom + h + 8 > window.innerHeight && t.top - h - 8 > 0) this.el.classList.add("is-up")
        },
        emit(input) {
          input.dispatchEvent(new Event("input", { bubbles: true }))
          input.dispatchEvent(new Event("change", { bubbles: true }))
        },
        singleValue() {
          if (!this.selected) return ""
          if (this.mode !== "datetime") return this.iso(this.selected)
          const t = this.timeEl && TIME.test(this.timeEl.value) ? this.timeEl.value : "00:00"
          return `${this.iso(this.selected)}T${t}`
        },
        onTime(el) {
          el.value = el.value.replace(/[^\d:]/g, "")
          if (/^\d{4}$/.test(el.value)) el.value = `${el.value.slice(0, 2)}:${el.value.slice(2)}`
          if (this.selected && TIME.test(el.value)) { this.input.value = this.singleValue(); this.emit(this.input) }
        },
        choose(d) {
          if (d && this.disabledDay(d)) return
          if (this.mode === "range") return this.chooseRange(d)
          this.selected = d
          this.input.value = this.singleValue()
          this.emit(this.input)
          this.renderDisplay()
          this.close(true)
          if (d && this.timeEl && !TIME.test(this.timeEl.value)) this.timeEl.focus()
        },
        // First click sets the start, the second the end (swapped if it is earlier).
        chooseRange(d) {
          if (!d) { this.start = this.end = null; return this.commitRange() }
          if (!this.pending) {
            this.pending = d; this.start = d; this.end = null
            this.focusDate = new Date(d.getTime())
            this.render(); this.renderDisplay(); return this.focusActive()
          }
          const a = this.pending
          this.start = d < a ? d : a
          this.end = d < a ? a : d
          this.pending = null
          this.commitRange()
        },
        commitRange() {
          this.pending = null
          this.inFrom.value = this.start ? this.iso(this.start) : ""
          this.inTo.value = this.end ? this.iso(this.end) : ""
          this.emit(this.inTo)
          this.renderDisplay()
          this.close(true)
        },
        shift(days, months) {
          const d = new Date(this.focusDate.getTime())
          if (months) {
            const day = d.getDate()
            d.setDate(1); d.setMonth(d.getMonth() + months)
            d.setDate(Math.min(day, new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()))
          }
          if (days) d.setDate(d.getDate() + days)
          this.focusDate = d
          this.render(); this.focusActive()
        },
        handleKey(e) {
          if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); this.close(true); return }
          if (this.view !== "days" || !e.target.matches("[data-dp-day]")) return
          const dow = (this.focusDate.getDay() + 6) % 7
          const map = {
            ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [-7, 0], ArrowDown: [7, 0],
            Home: [-dow, 0], End: [6 - dow, 0],
            PageUp: [0, e.shiftKey ? -12 : -1], PageDown: [0, e.shiftKey ? 12 : 1]
          }
          if (map[e.key]) { e.preventDefault(); this.shift(...map[e.key]); return }
          if (e.key === "Enter" || e.key === " ") { e.preventDefault(); this.choose(new Date(this.focusDate.getTime())) }
        },
        handleClick(e) {
          const t = e.target.closest("button")
          if (!t || t.disabled) return
          e.preventDefault()
          const a = t.dataset
          if (a.dpNav) {
            const n = parseInt(a.dpNav, 10)
            if (this.view === "days") return this.shift(0, n)
            this.focusDate.setFullYear(this.focusDate.getFullYear() + n * (this.view === "years" ? 12 : 1))
            return this.render()
          }
          if (a.dpView) { this.view = a.dpView; this.render(); return this.focusActive() }
          if (a.dpMonth) {
            this.focusDate = new Date(this.focusDate.getFullYear(), parseInt(a.dpMonth, 10), 1)
            this.view = "days"; this.render(); return this.focusActive()
          }
          if (a.dpYear) {
            const yr = parseInt(a.dpYear, 10)
            const month = this.focusDate.getMonth()
            const day = Math.min(this.focusDate.getDate(), new Date(yr, month + 1, 0).getDate())
            this.focusDate = new Date(yr, month, day)
            this.view = "days"; this.render(); return this.focusActive()
          }
          if (a.dpDay) return this.choose(parseIso(a.dpDay))
          if (a.dpAction === "today") {
            const t0 = new Date(this.today.getTime())
            if (this.mode === "range") { this.start = this.end = t0; return this.commitRange() }
            return this.choose(t0)
          }
          if (a.dpAction === "clear") return this.choose(null)
        },
        focusActive() {
          const el = this.pop.querySelector('[tabindex="0"]')
          if (el) el.focus({ preventScroll: true })
        },
        header(label, view, prevLabel, nextLabel) {
          return `<div class="td-dp-hd">
            <button type="button" class="td-dp-title" data-dp-view="${view}" aria-live="polite">${label}</button>
            <span class="td-dp-nv">
              <button type="button" class="td-dp-nb" data-dp-nav="-1" aria-label="${prevLabel}">${CARET_L}</button>
              <button type="button" class="td-dp-nb" data-dp-nav="1" aria-label="${nextLabel}">${CARET_R}</button>
            </span>
          </div>`
        },
        dayHeader(month, year) {
          return `<div class="td-dp-hd">
            <span class="td-dp-titles">
              <button type="button" class="td-dp-title" data-dp-view="months" aria-label="Choose month">${month}</button>
              <button type="button" class="td-dp-title" data-dp-view="years" aria-label="Choose year">${year}</button>
            </span>
            <span class="td-dp-nv">
              <button type="button" class="td-dp-nb" data-dp-nav="-1" aria-label="Previous month">${CARET_L}</button>
              <button type="button" class="td-dp-nb" data-dp-nav="1" aria-label="Next month">${CARET_R}</button>
            </span>
          </div>`
        },
        yearPageStart(y) {
          if (this.mode === "range") return y - (y % 12)
          const base = this.today.getFullYear()
          let offset = (y - base) % 12
          if (offset < 0) offset += 12
          return y - offset
        },
        footer() {
          const todayOff = this.disabledDay(this.today)
          return `<div class="td-dp-ft">
            <button type="button" class="td-dp-text" data-dp-action="clear" ${this.hasValue() ? "" : "disabled"}>Clear</button>
            <button type="button" class="td-dp-text" data-dp-action="today" ${todayOff ? "disabled" : ""}>Today</button>
          </div>`
        },
        render() {
          if (this.view === "months") return this.renderMonths()
          if (this.view === "years") return this.renderYears()
          this.renderDays()
        },
        dayClasses(d, m) {
          const cls = ["td-dp-day"]
          if (d.getMonth() !== m) cls.push("is-outside")
          if (sameDay(d, this.today)) cls.push("is-today")
          if (this.mode !== "range") {
            if (sameDay(d, this.selected)) cls.push("is-selected")
            return cls
          }
          const s = this.start, e = this.end
          if (sameDay(d, s) || sameDay(d, e)) cls.push("is-selected")
          if (s && e && !sameDay(s, e)) {
            if (sameDay(d, s)) cls.push("is-range-start")
            if (sameDay(d, e)) cls.push("is-range-end")
            if (d > s && d < e) cls.push("is-in-range")
          }
          return cls
        },
        renderDays() {
          const y = this.focusDate.getFullYear(), m = this.focusDate.getMonth()
          const first = new Date(y, m, 1)
          const start = new Date(y, m, 1 - ((first.getDay() + 6) % 7))
          let grid = ""
          for (let i = 0; i < 42; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            if (i === 35 && d.getMonth() !== m) break
            const cls = this.dayClasses(d, m)
            const sel = cls.includes("is-selected")
            grid += `<button type="button" role="gridcell" class="${cls.join(" ")}" data-dp-day="${this.iso(d)}"
              tabindex="${sameDay(d, this.focusDate) ? 0 : -1}" aria-selected="${sel}"
              ${sameDay(d, this.today) ? 'aria-current="date"' : ""}
              aria-label="${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}" ${this.disabledDay(d) ? "disabled" : ""}>${d.getDate()}</button>`
          }
          this.pop.innerHTML = this.dayHeader(MONTHS[m], y) +
            `<div class="td-dp-wk" aria-hidden="true">${DOW.map(d => `<span>${d}</span>`).join("")}</div>` +
            `<div class="td-dp-gr" role="grid">${grid}</div>` + this.footer()
        },
        renderMonths() {
          const y = this.focusDate.getFullYear()
          const ref = this.mode === "range" ? (this.start || this.end) : this.selected
          const cells = SHORT.map((name, i) => {
            const lastDay = new Date(y, i + 1, 0), firstDay = new Date(y, i, 1)
            const off = (this.max && firstDay > this.max) || (this.min && lastDay < this.min)
            const sel = ref && ref.getFullYear() === y && ref.getMonth() === i
            return `<button type="button" class="td-dp-cell${sel ? " is-selected" : ""}" data-dp-month="${i}"
              tabindex="${i === this.focusDate.getMonth() ? 0 : -1}" ${off ? "disabled" : ""}>${name}</button>`
          }).join("")
          this.pop.innerHTML = this.header(`${y}`, "years", "Previous year", "Next year") +
            `<div class="td-dp-cells">${cells}</div>` + this.footer()
        },
        renderYears() {
          const y = this.focusDate.getFullYear()
          const start = this.yearPageStart(y)
          const ref = this.mode === "range" ? (this.start || this.end) : this.selected
          let cells = ""
          for (let i = 0; i < 12; i++) {
            const yr = start + i
            const off = (this.max && yr > this.max.getFullYear()) || (this.min && yr < this.min.getFullYear())
            const sel = ref && ref.getFullYear() === yr
            cells += `<button type="button" class="td-dp-cell${sel ? " is-selected" : ""}" data-dp-year="${yr}"
              tabindex="${yr === y ? 0 : -1}" ${off ? "disabled" : ""}>${yr}</button>`
          }
          this.pop.innerHTML = this.header(`${start} – ${start + 11}`, "months", "Previous years", "Next years") +
            `<div class="td-dp-cells">${cells}</div>` + this.footer()
        }
      }
    </script>
    """
  end

  @doc """
  The TD DatePicker range variant (Doop `chdlkoodd2`, frame gGZGY4la6k) for From / To
  filter pairs. It uses the same month and year grids as the single date picker.
  One 32px field shows `1 Nov 2026 – 22 Nov 2026`; the popover takes a
  start and an end click, fills the days between with the accent tint and marks both
  ends in solid accent. Each end is submitted as ISO `yyyy-mm-dd` in its own hidden
  input, so the existing `from` / `to` params keep working.

  ## Examples

  ```heex
  <.date_range_picker
    id="earnings-dates"
    label="Date"
    from_name="filters[date_from]"
    from_value={@filters.date_from}
    to_name="filters[date_to]"
    to_value={@filters.date_to}
  />
  ```
  """
  attr :id, :string, required: true
  attr :label, :string, default: nil
  attr :from_name, :string, required: true
  attr :from_value, :any, default: nil
  attr :to_name, :string, required: true
  attr :to_value, :any, default: nil
  attr :placeholder, :string, default: "Choose dates"
  attr :max, :string, default: nil
  attr :min, :string, default: nil
  attr :align, :string, default: "left"
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil

  def date_range_picker(assigns) do
    {from, _} = date_time_parts(assigns.from_value)
    {to, _} = date_time_parts(assigns.to_value)

    assigns =
      assigns
      |> assign(:from_iso, from)
      |> assign(:to_iso, to)
      |> assign(:display, display_range(display_date(from), display_date(to)))

    ~H"""
    <div
      id={"#{@id}-dp"}
      class={["td-dp is-range", @align == "right" && "is-right", @class]}
      phx-hook=".DatePicker"
      data-dp-mode="range"
      data-max={@max}
      data-min={@min}
    >
      <label :if={@label} for={"#{@id}-trigger"} class="thamani-label">{@label}</label>
      <input
        type="text"
        name={@from_name}
        id={"#{@id}-from"}
        value={@from_iso}
        data-dp-input="from"
        tabindex="-1"
        aria-hidden="true"
        class="td-dp-value"
      />
      <input
        type="text"
        name={@to_name}
        id={"#{@id}-to"}
        value={@to_iso}
        data-dp-input="to"
        tabindex="-1"
        aria-hidden="true"
        class="td-dp-value"
      />
      <div class="td-dp-row">
        <button
          type="button"
          id={"#{@id}-trigger"}
          data-dp-trigger
          class="td-dp-trigger"
          aria-haspopup="dialog"
          aria-expanded="false"
          aria-controls={"#{@id}-dp-pop"}
          disabled={@disabled}
        >
          <span
            data-dp-display
            data-placeholder={@placeholder}
            class={["td-dp-display", is_nil(@display) && "is-placeholder"]}
          >
            {@display || @placeholder}
          </span>
          <ThamaniDawaWeb.TDComponents.td_icon name="calendar-blank" class="td-dp-icon" />
        </button>
      </div>
      <div
        data-dp-pop
        id={"#{@id}-dp-pop"}
        class="td-dp-pop"
        role="dialog"
        aria-modal="false"
        aria-label={
          if @label, do: "Choose #{String.downcase(@label)} range", else: "Choose a date range"
        }
        phx-update="ignore"
        hidden
      >
      </div>
    </div>
    """
  end

  defp display_range(nil, nil), do: nil
  defp display_range(from, nil), do: "From #{from}"
  defp display_range(nil, to), do: "Until #{to}"
  defp display_range(from, to), do: "#{from} – #{to}"

  # {"yyyy-mm-dd", "HH:MM"} from a Date, DateTime, NaiveDateTime or form string.
  defp date_time_parts(%Date{} = date), do: {Date.to_iso8601(date), ""}

  defp date_time_parts(%DateTime{} = dt),
    do: dt |> ThamaniDawaWeb.TimeFormat.to_eat() |> eat_parts()

  defp date_time_parts(%NaiveDateTime{} = dt),
    do: dt |> ThamaniDawaWeb.TimeFormat.to_eat() |> eat_parts()

  defp date_time_parts(value) when is_binary(value) do
    case String.split(value, ["T", " "], parts: 2) do
      [date, time] -> {date, String.slice(time, 0, 5)}
      [date] -> {date, ""}
    end
  end

  defp date_time_parts(_), do: {"", ""}

  defp eat_parts(%NaiveDateTime{} = eat) do
    {eat |> NaiveDateTime.to_date() |> Date.to_iso8601(), Calendar.strftime(eat, "%H:%M")}
  end

  defp date_time_value("", _time), do: ""
  defp date_time_value(date, ""), do: date <> "T00:00"
  defp date_time_value(date, time), do: date <> "T" <> time

  defp display_date(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> ThamaniDawaWeb.TimeFormat.date(date)
      _ -> nil
    end
  end

  defp display_date(_), do: nil

  @doc """
  Renders a checkbox-card group for choosing one or more site activities.

  ## Examples

      <.capability_select
        field={@form[:activities]}
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

    selected =
      assigns.field.value
      |> List.wrap()
      |> Enum.map(&to_string/1)

    assigns =
      assigns
      |> assign(:errors, errors)
      |> assign(:selected, selected)

    ~H"""
    <fieldset id={@id} class="fieldset mb-4">
      <legend class="label mb-2">
        Activities<span :if={@required} aria-hidden="true" class="text-error ml-0.5">*</span>
      </legend>
      <div class="grid grid-cols-2 gap-2">
        <label
          :for={{label, desc, value} <- @options}
          for={"#{@id}-#{value}"}
          class="card border cursor-pointer p-3"
        >
          <div class="flex items-center gap-2">
            <input
              type="checkbox"
              id={"#{@id}-#{value}"}
              name={"#{@field.name}[]"}
              value={value}
              checked={to_string(value) in @selected}
              class="checkbox checkbox-sm"
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
  Renders a single selectable "activity" card — a styled radio or checkbox
  input with an icon, label, and description, used anywhere a premises's
  licensed activities are picked (the signup wizard's operating-model and
  site-activity steps, `SiteLive.Index`'s "Add a site" form).

  ## Examples

      <.activity_card
        type="radio"
        name="site[activity_choice]"
        value="pharmacy"
        label="Retail pharmacy"
        description="Dispense medicines directly to patients"
        icon="hero-building-storefront"
        selected={true}
        compact
      />
  """
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, default: nil
  attr :selected, :boolean, default: false
  attr :compact, :boolean, default: false
  attr :type, :string, default: "checkbox"

  def activity_card(assigns) do
    ~H"""
    <label
      :if={@compact}
      class={[
        "group block cursor-pointer rounded-xl border-2 px-3.5 py-3 transition-all hover:border-[var(--thamani-forest)] focus-within:ring-2 focus-within:ring-[var(--color-td-accent-tint)] focus-within:ring-offset-2",
        @selected &&
          "border-[var(--thamani-forest)] bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)]",
        !@selected && "border-[var(--thamani-stone)] bg-td-surface"
      ]}
    >
      <input type={@type} name={@name} value={@value} checked={@selected} class="peer sr-only" />
      <div class="flex items-center gap-3">
        <span
          :if={@icon}
          class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-[color-mix(in_srgb,var(--color-td-accent-tint)_20%,white)] text-[var(--thamani-forest)]"
        >
          <.icon name={@icon} class="size-5" />
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-[13px] font-semibold text-[var(--thamani-forest)]">
            {@label}
          </span>
          <span class="mt-0.5 block text-[11px] leading-4 text-[var(--thamani-pewter)]">
            {@description}
          </span>
        </span>
        <span class={[
          "flex size-5 shrink-0 items-center justify-center rounded-md border transition-colors",
          @selected && "border-[var(--thamani-forest)] bg-[var(--thamani-forest)] text-white",
          !@selected &&
            "border-[var(--thamani-stone)] bg-td-surface group-hover:border-[var(--thamani-forest)]"
        ]}>
          <.icon :if={@selected} name="hero-check" class="size-3.5" />
        </span>
      </div>
    </label>

    <label
      :if={!@compact}
      class={[
        "group cursor-pointer rounded-xl border-2 p-4 transition-all hover:-translate-y-0.5 hover:border-[var(--thamani-forest)] focus-within:ring-2 focus-within:ring-[var(--color-td-accent-tint)] focus-within:ring-offset-2",
        @selected &&
          "border-[var(--thamani-forest)] bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] shadow-md",
        !@selected && "border-[var(--thamani-stone)] bg-td-surface"
      ]}
    >
      <input type="checkbox" name={@name} value={@value} checked={@selected} class="peer sr-only" />
      <div class={[
        "flex items-start",
        @icon && "justify-between gap-2",
        !@icon && "justify-end"
      ]}>
        <.icon :if={@icon} name={@icon} class="size-5 text-[var(--thamani-forest)]" />
        <span class={[
          "flex size-5 shrink-0 items-center justify-center rounded-md border transition-colors",
          @selected && "border-[var(--thamani-forest)] bg-[var(--thamani-forest)] text-white",
          !@selected &&
            "border-[var(--thamani-stone)] bg-td-surface group-hover:border-[var(--thamani-forest)]"
        ]}>
          <.icon :if={@selected} name="hero-check" class="size-3.5" />
        </span>
      </div>
      <span class="mt-3 block text-sm font-semibold text-[var(--thamani-forest)]">
        {@label}
      </span>
      <span class="mt-1 block text-[11px] leading-4 text-[var(--thamani-pewter)]">
        {@description}
      </span>
    </label>
    """
  end

  @doc """
  Renders a page header: title, optional subtitle and actions — every
  screen's title block should look like this. Pass `icon` for the leading
  tinted icon badge (e.g. a section's own hero icon); omit it for a plain
  title, same as before.

  Pass a `:toolbar` slot (a search box + `filter_drawer/1`, typically) to
  render it below the title and actions with an internal divider, instead of
  as a separate floating element — this is what every list page with
  search/filter should do, so the title and toolbar read as one unit.

  ## Examples

      <.header>Prescriptions</.header>

      <.header icon="hero-cube">
        Product catalog
        <:subtitle>Search, filter, and manage your product catalog.</:subtitle>
        <:actions>
          <.button variant="primary">+ Add product</.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1">
            <.search_input name="search" value={@search} placeholder="Search..." />
          </form>
          <.filter_drawer id="products-filters" apply_event="apply_filters">
            ...
          </.filter_drawer>
        </:toolbar>
      </.header>
  """
  attr :icon, :string, default: nil, doc: "optional hero-* icon name for the leading badge"

  attr :variant, :string,
    values: ~w(card plain),
    default: "card",
    doc:
      "\"card\" (default) provides page-header spacing; \"plain\" is a compact in-page section heading"

  slot :inner_block, required: true
  slot :subtitle
  slot :actions
  slot :toolbar, doc: "optional search/filter row, rendered below a divider in the same card"

  attr :back, :any,
    default: nil,
    doc: "optional route or true to render back button directly to the left of the title"

  attr :class, :any, default: nil

  def header(assigns) do
    ~H"""
    <div class={["td-header", @variant == "plain" && "is-plain", @class]}>
      <header class="td-header-row">
        <div class="td-header-title">
          <.link :if={is_binary(@back)} navigate={@back} aria-label="Go back" class="td-icon-btn">
            <.icon name="arrow-left" class="size-4" />
          </.link>
          <button
            :if={@back == true}
            type="button"
            aria-label="Go back"
            onclick="window.history.back()"
            class="td-icon-btn"
          >
            <.icon name="arrow-left" class="size-4" />
          </button>
          <div>
            <h1>{render_slot(@inner_block)}</h1>
            <p :if={@subtitle != []}>{render_slot(@subtitle)}</p>
          </div>
        </div>
        <div :if={@actions != []} class="td-header-actions">
          {render_slot(@actions)}
        </div>
      </header>
      <div :if={@toolbar != []} class="td-header-tools">
        {render_slot(@toolbar)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a table with generic styling.

  On narrow screens, the first column is promoted to the row's title and the
  remaining columns become compact label/value metadata. Put the record's most
  recognizable value (name, reference, site, etc.) in the first column. Set a
  column's `mobile="hidden"` when it belongs on the desktop/detail view rather
  than in the compact list, or `mobile="aside"` for a short status/badge that
  should sit beside the mobile title.

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
  attr :mobile_columns, :integer, values: [2, 3], default: 2
  attr :empty_class, :any, default: nil, doc: "additional classes for the empty-state cell"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
    attr :mobile, :string, values: ~w(hidden aside)
    attr :tablet, :string, values: ~w(hidden)
  end

  slot :action, doc: "the slot for showing user actions in the last table column"
  slot :empty_state, doc: "rendered in place of the table body when `rows` is empty"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="td-table responsive-table">
      <div class="sm:overflow-x-auto sm:overscroll-x-contain">
        <table class="block w-full text-left sm:table sm:min-w-[42rem]">
          <thead class="sr-only sm:not-sr-only sm:table-header-group sm:bg-thamani-table-head sm:text-left sm:text-thamani-forest">
            <tr>
              <th
                :for={col <- @col}
                scope="col"
                class={[
                  "whitespace-nowrap px-4 py-2 text-xs font-medium text-td-ink-2 sm:border-b sm:border-td-hairline sm:px-4 sm:py-2.5 sm:text-sm sm:font-semibold sm:leading-5 sm:text-thamani-forest",
                  col[:tablet] == "hidden" && "sm:max-lg:hidden"
                ]}
              >
                {col[:label]}
              </th>
              <th
                :if={@action != []}
                scope="col"
                class="px-4 py-2 text-right sm:border-b sm:border-td-hairline sm:py-2.5"
              >
                <span class="sr-only">{gettext("Actions")}</span>
              </th>
            </tr>
          </thead>
          <tbody
            id={@id}
            phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
            class="block space-y-2 sm:table-row-group sm:space-y-0 sm:text-sm sm:leading-6 sm:text-td-ink"
          >
            <tr
              :if={@empty_state != []}
              id={"#{@id}-empty"}
              class="hidden w-full only:block sm:only:table-row"
            >
              <td
                colspan={length(@col) + ((@action != [] && 1) || 0)}
                class={["block w-full px-4 py-8 sm:table-cell sm:px-5", @empty_class]}
              >
                {render_slot(@empty_state)}
              </td>
            </tr>
            <tr
              :for={row <- @rows}
              id={@row_id && @row_id.(row)}
              class={[
                "td-table-row group relative grid overflow-visible transition-colors duration-150 sm:table-row",
                if(@mobile_columns == 3, do: "grid-cols-3", else: "grid-cols-2"),
                @row_click && "cursor-pointer"
              ]}
            >
              <td
                :for={col <- @col}
                phx-click={@row_click && @row_click.(row)}
                data-label={col[:label]}
                class={[
                  "responsive-table-cell flex min-w-0 flex-col items-start gap-1 border-b border-thamani-stone/60 px-4 py-2 text-left text-sm leading-5 text-td-ink before:block before:text-sm before:font-normal before:text-thamani-pewter before:content-[attr(data-label)] first:col-span-full first:block first:bg-thamani-canvas/70 first:px-4 first:py-2.5 first:text-base first:font-semibold first:leading-6 first:text-thamani-forest first:before:hidden [&:nth-child(even)]:border-r [&:nth-child(even)]:border-thamani-stone/60 sm:table-cell sm:align-middle sm:border-r-0 sm:border-b sm:border-td-hairline sm:bg-transparent sm:px-4 sm:py-2 sm:text-left sm:text-sm sm:font-normal sm:leading-5 sm:text-td-ink sm:before:hidden sm:first:bg-transparent sm:first:text-sm sm:first:font-semibold sm:first:leading-5 sm:first:text-td-ink sm:first:whitespace-nowrap sm:[&:nth-child(even)]:border-r-0",
                  @mobile_columns == 3 &&
                    "max-sm:[&:nth-child(3)]:border-r max-sm:[&:nth-child(3)]:border-thamani-stone/60",
                  col[:mobile] == "hidden" && "max-sm:hidden",
                  col[:tablet] == "hidden" && "sm:max-lg:hidden",
                  col[:mobile] == "aside" &&
                    "max-sm:absolute max-sm:right-3 max-sm:top-3 max-sm:z-10 max-sm:border-0 max-sm:bg-transparent max-sm:p-0 max-sm:before:hidden",
                  @row_click && "cursor-pointer"
                ]}
              >
                <span class="td-cell">{render_slot(col, @row_item.(row))}</span>
              </td>
              <td
                :if={@action != []}
                data-label={gettext("Actions")}
                class="responsive-table-cell col-span-full flex items-center justify-end bg-thamani-canvas/60 px-3 py-3 text-right text-sm sm:table-cell sm:w-px sm:whitespace-nowrap sm:align-middle sm:border-b sm:border-td-hairline sm:bg-transparent sm:px-4 sm:py-2"
              >
                <div class="flex w-full min-w-0 flex-wrap items-center justify-end gap-2 [&>*]:flex-1 sm:w-max sm:flex-nowrap sm:gap-2 sm:[&>*]:flex-none sm:[&>*]:text-sm">
                  <%= for action <- @action do %>
                    {render_slot(action, @row_item.(row))}
                  <% end %>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc """
  Renders a status pill for a domain status atom (from `Prescription`, `LabOrder`,
  `LabOrderResult`, etc). Resolves the atom to one of five semantic categories via
  `status_semantic/1` and styles by meaning, not by the literal status word — so
  every schema's statuses read consistently. Always pairs color with the humanized
  status text, never color alone.

  ## Examples

      <.status_badge status={@prescription.status} />
      <.status_badge status={:verified} />
  """
  attr :status, :atom, required: true
  attr :label, :string, default: nil
  attr :class, :any, default: nil

  def status_badge(assigns) do
    assigns =
      assigns
      |> assign(:semantic, status_semantic(assigns.status))
      |> assign(:label, assigns.label || Phoenix.Naming.humanize(assigns.status))

    ~H"""
    <span class={[
      "td-badge",
      badge_classes(@semantic),
      @class
    ]}>
      {@label}
    </span>
    """
  end

  @doc """
  Maps a domain status atom to one of five semantic categories — success, warning,
  info, danger, neutral — regardless of which schema it comes from. This is the
  single source of truth `status_badge/1` renders from.
  """
  def status_semantic(status)
      when status in [
             :pending,
             :pending_review,
             :under_review,
             :pending_receipt,
             :invited,
             :low_stock,
             :unknown_serial,
             :quarantined,
             :expired,
             :returned
           ],
      do: :warning

  def status_semantic(status)
      when status in [
             :completed,
             :verified,
             :approved,
             :received,
             :accepted,
             :finalised,
             :grn_confirmed,
             :active,
             :paid,
             :ok
           ],
      do: :success

  def status_semantic(status)
      when status in [
             :in_progress,
             :collected,
             :partially_dispensed,
             :sent,
             :submitted,
             :acknowledged
           ],
      do: :info

  def status_semantic(status)
      when status in [
             :rejected,
             :flagged,
             :out_of_stock,
             :failed,
             :data_mismatch,
             :damaged,
             :stolen,
             :recalled,
             :destroyed,
             :non_sellable_other
           ],
      do: :danger

  # Brief 2: Cancelled reads as neutral, not as an error.
  def status_semantic(:cancelled), do: :neutral
  def status_semantic(_status), do: :neutral

  defp badge_classes(:success), do: "is-success"
  defp badge_classes(:warning), do: "is-warning"
  defp badge_classes(:info), do: "is-info"
  defp badge_classes(:danger), do: "is-danger"
  defp badge_classes(:neutral), do: "is-neutral"

  @doc """
  Renders an empty-state placeholder for a list/table with no rows, in Thamani's
  flat, shadowless style.

  ## Examples

      <.blank_state title="No prescriptions yet">
        Prescriptions will appear here once a patient visit creates one.
      </.blank_state>
  """
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block
  slot :actions

  def blank_state(assigns) do
    glyph =
      case phosphor_name(assigns.icon) do
        "question" -> "tray"
        name -> name
      end

    assigns = assign(assigns, :glyph, glyph)

    ~H"""
    <div class={["td-empty-state", @class]}>
      <ThamaniDawaWeb.TDComponents.td_icon name={@glyph} class="td-empty-state-icon" />
      <p class="td-empty-state-title">{@title}</p>
      <p :if={@inner_block != []} class="td-empty-state-text">{render_slot(@inner_block)}</p>
      <div :if={@actions != []} class="td-empty-state-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc """
  Renders a continuous animated progress bar for a multi-step flow (the
  signup wizard, the post-login onboarding checklist) — a thin filled track
  plus a "Step X of Y · label" caption underneath.

  ## Examples

      <.progress_bar current={2} total={4} label="Regulatory details" />
  """
  attr :current, :integer, required: true
  attr :total, :integer, required: true
  attr :label, :string, required: true

  attr :prefix, :string,
    default: nil,
    doc:
      "optional caption prefix (e.g. \"Getting started\") distinguishing this progress bar " <>
        "from another one shown earlier in the same session (e.g. the signup wizard's)"

  attr :class, :any, default: nil

  def progress_bar(assigns) do
    ~H"""
    <div class={["w-full", @class]} aria-label="Progress">
      <div class="h-1 w-full overflow-hidden rounded-full bg-[var(--thamani-stone)]">
        <div
          class="h-full rounded-full bg-[var(--thamani-forest)] transition-[width] duration-300 ease-out"
          style={"width: #{progress_pct(@current, @total)}%"}
        />
      </div>
      <p class="mt-2 text-[11px] font-medium text-[var(--thamani-pewter)]">
        <span :if={@prefix}>{@prefix} · </span>Step {@current} of {@total} · {@label}
      </p>
    </div>
    """
  end

  defp progress_pct(current, total) when total > 0, do: current / total * 100
  defp progress_pct(_current, _total), do: 0

  @doc """
  Full-screen chrome for a single onboarding task page (e.g. "Add a branch",
  "Add a product") reached from `OnboardingLive`'s checklist. Keeps the admin
  inside the same navigation-free shell used by `/onboarding` itself, instead
  of dropping them into the full org-shell platform page with its sidebar —
  so a step's "manage" CRUD page and its onboarding entry point can share one
  module, branching only on `return_to=onboarding`.

  ## Examples

      <.onboarding_task_shell
        flash={@flash}
        current_scope={@current_scope}
        icon="hero-building-office-2"
        title="Add a branch"
        description="Register another location once you're ready to operate from more than one."
      >
        <:right>
          ...task-specific list + add button...
        </:right>
        <:footer>
          ...back / skip / continue row...
        </:footer>
      </.onboarding_task_shell>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :progress_current, :integer, default: 0
  attr :progress_total, :integer, default: 0
  slot :right, required: true, doc: "the task-specific panel (list + add action)"
  slot :footer, required: true, doc: "the back / skip / continue row"

  def onboarding_task_shell(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={false}>
      <div class="flex min-h-svh flex-col bg-[var(--thamani-surface)]">
        <header class="border-b border-[color-mix(in_srgb,var(--thamani-stone)_70%,transparent)]">
          <div class="mx-auto flex h-20 w-full max-w-7xl items-center justify-between gap-6 px-5 sm:px-8 lg:px-12">
            <.link
              navigate={~p"/onboarding"}
              aria-label="Back to onboarding"
              class="w-36 sm:w-[148px]"
            >
              <img src="/images/logo-transparent.png" alt="" class="h-auto w-full" />
            </.link>

            <div class="flex min-w-0 items-center gap-3">
              <span
                class="flex size-9 shrink-0 items-center justify-center rounded-full bg-[var(--thamani-forest)] text-sm font-semibold uppercase text-[var(--thamani-on-accent)] shadow-sm"
                aria-hidden="true"
              >
                {String.first(@current_scope.user.name || "U")}
              </span>
              <span class="max-w-44 truncate text-sm font-medium text-[var(--thamani-forest)]">
                {@current_scope.user.name}
              </span>
            </div>
          </div>
        </header>

        <div class="h-1 w-full overflow-hidden bg-[var(--thamani-stone)]" aria-label="Setup progress">
          <div
            class="h-full bg-[var(--thamani-forest)] transition-[width] duration-300 ease-out"
            style={"width: #{progress_pct(@progress_current, @progress_total)}%"}
          />
        </div>

        <main class="mx-auto grid w-full max-w-6xl flex-1 items-start gap-10 px-5 pb-16 pt-10 sm:px-8 sm:pt-12 md:grid-cols-[minmax(0,0.7fr)_minmax(0,1.3fr)] md:gap-10 md:pt-16 lg:gap-16 lg:pt-20">
          <section class="thamani-step-enter flex flex-col items-center text-center md:block md:text-left">
            <div class="mb-7 flex size-12 items-center justify-center rounded-2xl bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] text-[var(--thamani-forest)]">
              <.icon name={@icon} class="size-6" />
            </div>
            <h1 class="w-full max-w-md text-[30px] font-light leading-[1.08] tracking-[-0.7px] text-[var(--thamani-forest)] sm:text-[38px]">
              {@title}
            </h1>
            <p class="mt-6 w-full max-w-md text-base leading-7 text-[var(--thamani-pewter)] sm:text-[17px]">
              {@description}
            </p>
          </section>

          <section class="thamani-step-enter min-w-0 rounded-3xl border border-[var(--thamani-stone)] bg-transparent p-6 sm:p-8">
            {render_slot(@right)}
          </section>

          <div class="flex items-center justify-between gap-4 md:col-span-2">
            {render_slot(@footer)}
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  @doc """
  Renders a pill-style tab group, e.g. the "Patients / Patient visits" toggle.

  ## Examples

      <.tab_group>
        <:tab id="patients-tab" active={@tab == "patients"} phx_click="switch_tab" phx_value_tab="patients">
          Patients
        </:tab>
        <:tab id="visits-tab" active={@tab == "visits"} phx_click="switch_tab" phx_value_tab="visits">
          Patient visits
        </:tab>
      </.tab_group>
  """
  attr :class, :any, default: nil
  attr :variant, :string, default: "compact", values: ~w(compact prominent)

  slot :tab, required: true do
    attr :id, :string
    attr :active, :boolean
    attr :phx_click, :string, required: true
    attr :phx_value_tab, :string
    attr :phx_value_view, :string
    attr :controls, :string
  end

  def tab_group(assigns) do
    ~H"""
    <div
      role="tablist"
      class={[
        "border border-thamani-stone bg-thamani-surface",
        @variant == "compact" && "inline-flex rounded-lg p-1",
        @variant == "prominent" &&
          "grid w-full grid-cols-2 gap-1 rounded-xl bg-thamani-canvas p-1 shadow-sm",
        @class
      ]}
    >
      <button
        :for={tab <- @tab}
        id={tab[:id]}
        type="button"
        role="tab"
        aria-selected={to_string(tab[:active])}
        aria-controls={tab[:controls]}
        tabindex={if(tab[:active], do: "0", else: "-1")}
        class={[
          "cursor-pointer rounded-md text-sm font-medium outline-none transition-all duration-200 focus-visible:ring-2 focus-visible:ring-thamani-forest focus-visible:ring-offset-2",
          @variant == "compact" && "px-3 py-2",
          @variant == "prominent" && "min-w-0 px-3 py-2.5 text-left sm:px-4",
          tab[:active] && @variant == "compact" && "bg-td-accent-tint text-thamani-forest",
          tab[:active] && @variant == "prominent" &&
            "bg-td-surface text-thamani-forest shadow-sm ring-1 ring-thamani-stone",
          !tab[:active] && @variant == "compact" &&
            "text-thamani-pewter hover:bg-td-surface/60 hover:text-thamani-forest",
          !tab[:active] && @variant == "prominent" &&
            "text-thamani-pewter hover:bg-td-surface/70 hover:text-thamani-forest"
        ]}
        phx-click={tab[:phx_click]}
        phx-value-tab={tab[:phx_value_tab]}
        phx-value-view={tab[:phx_value_view]}
      >{render_slot(tab)}</button>
    </div>
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
    <dl class="divide-y divide-thamani-stone overflow-hidden rounded-xl ff-surface-card">
      <div
        :for={item <- @item}
        class="grid gap-1 px-4 py-3 sm:grid-cols-[minmax(8rem,0.4fr)_minmax(0,1fr)] sm:gap-5 sm:px-5"
      >
        <dt class="text-xs font-medium text-thamani-subtle">{item.title}</dt>
        <dd class="min-w-0 break-words text-sm text-td-ink">{render_slot(item)}</dd>
      </div>
    </dl>
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
  # Product UI draws Phosphor. Names that are not real Heroicons stay as
  # class hooks for the few custom marks that are not glyphs.
  @hero_to_phosphor %{
    "adjustments-horizontal" => "faders-horizontal",
    "archive-box" => "archive",
    "arrow-down-circle" => "arrow-circle-down",
    "arrow-down-tray" => "download-simple",
    "arrow-left" => "arrow-left",
    "arrow-left-end-on-rectangle" => "sign-in",
    "arrow-path" => "arrows-clockwise",
    "arrow-right" => "arrow-right",
    "arrow-right-end-on-rectangle" => "sign-in",
    "arrow-right-start-on-rectangle" => "sign-out",
    "arrow-top-right-on-square" => "arrow-square-out",
    "arrow-trending-up" => "trend-up",
    "arrow-up-right" => "arrow-up-right",
    "arrow-up-tray" => "upload-simple",
    "arrow-uturn-left" => "arrow-u-up-left",
    "banknotes" => "money",
    "bars-3" => "list",
    "beaker" => "flask",
    "bolt" => "lightning",
    "bookmark-square" => "bookmark-simple",
    "building-library" => "bank",
    "building-office-2" => "buildings",
    "building-storefront" => "storefront",
    "calendar-days" => "calendar-blank",
    "chart-bar" => "chart-bar",
    "chart-bar-square" => "chart-bar",
    "chart-pie" => "chart-pie",
    "check" => "check",
    "check-badge" => "seal-check",
    "check-circle" => "check-circle",
    "check-square" => "check-square",
    "chevron-down" => "caret-down",
    "chevron-left" => "caret-left",
    "chevron-right" => "caret-right",
    "clipboard-document-check" => "clipboard-text",
    "clipboard-document-list" => "clipboard-text",
    "clock" => "clock",
    "code-bracket" => "code",
    "cog-6-tooth" => "gear",
    "cog-8-tooth" => "gear",
    "copy" => "copy",
    "credit-card" => "credit-card",
    "cube" => "cube",
    "cube-transparent" => "cube",
    "currency-dollar" => "currency-dollar",
    "device-phone-mobile" => "device-mobile",
    "document" => "file",
    "document-check" => "file-text",
    "document-text" => "file-text",
    "ellipsis-vertical" => "dots-three-vertical",
    "envelope" => "envelope",
    "exclamation-circle" => "warning-circle",
    "exclamation-triangle" => "warning",
    "eye" => "eye",
    "eye-slash" => "eye-slash",
    "globe-alt" => "globe",
    "hand-raised" => "hand-palm",
    "identification" => "identification-card",
    "inbox" => "tray",
    "inbox-arrow-down" => "tray",
    "information-circle" => "info",
    "key" => "key",
    "light-bulb" => "lightbulb",
    "list-bullet" => "list-bullets",
    "lock-closed" => "lock",
    "magnifying-glass" => "magnifying-glass",
    "map" => "map-trifold",
    "minus" => "minus",
    "no-symbol" => "prohibit",
    "paper-airplane" => "paper-plane-tilt",
    "paper-clip" => "paperclip",
    "pencil" => "pencil-simple",
    "pencil-square" => "note-pencil",
    "phone" => "phone",
    "photo" => "image",
    "plus" => "plus",
    "plus-circle" => "plus-circle",
    "printer" => "printer",
    "qr-code" => "qr-code",
    "queue-list" => "queue",
    "rocket-launch" => "rocket",
    "shield-check" => "shield-check",
    "shield-exclamation" => "shield-warning",
    "shopping-cart" => "shopping-cart",
    "signal" => "broadcast",
    "sparkles" => "circle",
    "square-2-stack" => "stack",
    "squares-2x2" => "squares-four",
    "squares-plus" => "plus-square",
    "star" => "star",
    "table-cells" => "table",
    "tag" => "tag",
    "trash" => "trash",
    "truck" => "truck",
    "user" => "user",
    "user-group" => "users",
    "users" => "users",
    "x-circle" => "x-circle",
    "x-mark" => "x"
  }

  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> rest} = assigns) do
    case Map.get(@hero_to_phosphor, icon_key(rest)) do
      nil ->
        ~H"""
        <span class={[@name, @class]} />
        """

      phosphor ->
        render_phosphor(assigns, phosphor)
    end
  end

  def icon(assigns) do
    render_phosphor(assigns, assigns.name)
  end

  @doc "Resolves a legacy `hero-*` name to its Phosphor name; Phosphor names pass through."
  def phosphor_name("hero-" <> rest), do: Map.get(@hero_to_phosphor, icon_key(rest), "question")
  def phosphor_name(name), do: name

  defp icon_key(rest) do
    rest
    |> String.replace_suffix("-solid", "")
    |> String.replace_suffix("-mini", "")
  end

  defp render_phosphor(assigns, name) do
    weight = if String.contains?(to_string(assigns.name), "-solid"), do: "fill", else: "regular"

    assigns =
      assigns
      |> assign(:phosphor_name, name)
      |> assign(:phosphor_weight, weight)
      |> assign(:phosphor_class, icon_class(assigns.class))

    ~H"""
    <Phosphor.icon
      name={@phosphor_name}
      weight={@phosphor_weight}
      class={@phosphor_class}
    />
    """
  end

  defp icon_class(class) when is_list(class) do
    class
    |> List.flatten()
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
    |> icon_class()
  end

  defp icon_class(class) when is_binary(class) and class != "" do
    "inline-block shrink-0 " <> class
  end

  defp icon_class(_class), do: "inline-block size-4 shrink-0"

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
  @btn_loading "phx-submit-loading:opacity-75 phx-click-loading:opacity-75"

  defp thamani_btn_classes("primary"),
    do: "td-btn is-primary is-lg w-full #{@btn_loading}"

  defp thamani_btn_classes("ghost"),
    do: "td-btn is-secondary is-lg w-full #{@btn_loading}"

  defp thamani_btn_classes("ghost_inv"),
    do: "td-btn is-secondary is-lg w-full #{@btn_loading}"

  defp thamani_btn_classes("lime"),
    do: "td-btn is-primary is-lg w-full #{@btn_loading}"

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
    values: ~w(text email url password textarea select combobox),
    doc: "HTML input type"

  attr :placeholder, :string, default: nil
  attr :autocomplete, :string, default: nil
  attr :class, :any, default: nil, doc: "extra classes on the wrapper div"
  attr :required, :boolean, default: false, doc: "shows a required marker next to the label"
  attr :icon, :string, default: nil, doc: "optional hero-* icon name shown leading the input"

  attr :sensitive, :boolean,
    default: false,
    doc: "visually masks non-password secrets without invoking browser password managers"

  attr :options, :list, default: [], doc: "options for select inputs, as label/value pairs"
  attr :rest, :global, include: ~w(disabled readonly rows)

  slot :badge, doc: "optional trailing badge rendered vertically centered inside the input"

  def thamani_input(%{type: "combobox", field: field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    opts =
      Enum.map(assigns[:options] || [], fn
        {label, value} -> [to_string(label), to_string(value)]
        label -> [to_string(label), to_string(label)]
      end)

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &translate_error(&1)))
      |> assign(:input_id, field.id)
      |> assign(:name, field.name)
      |> assign(:value, field.value)
      |> assign(:opts_json, Jason.encode!(opts))

    ~H"""
    <div class={["mb-5", @class]}>
      <div class={[
        "flex items-baseline justify-between mb-2",
        @errors != [] && "mb-1"
      ]}>
        <label
          for={"#{@input_id}-trigger"}
          class="block text-[13px] font-medium text-thamani-pewter tracking-[0.01em]"
        >
          {@label}<span :if={@required} class="text-red-600">&nbsp;*</span>
        </label>
      </div>
      <div
        id={"#{@input_id}-combobox"}
        phx-hook=".ThamaniCombobox"
        data-options={@opts_json}
        data-prompt={@placeholder || ""}
        class="relative"
      >
        <select id={@input_id} name={@name} data-tc-input required={@required} class="hidden">
          <option :if={@placeholder} value="">{@placeholder}</option>
          <option
            :for={{label, value} <- @options}
            value={value}
            selected={to_string(@value) == to_string(value)}
          >
            {label}
          </option>
        </select>
        <button
          type="button"
          id={"#{@input_id}-trigger"}
          data-tc-trigger
          aria-haspopup="listbox"
          aria-expanded="false"
          class={[
            "flex w-full items-center justify-between gap-2 box-border px-4 py-3 text-left",
            "text-[15px] bg-thamani-snow border-[1.5px] rounded-lg outline-none cursor-pointer select-none",
            "transition-[border-color,box-shadow] duration-150 ease-in-out",
            "focus:border-thamani-accent focus:shadow-[0_0_0_3px_rgba(102,103,171,0.12)]",
            (@errors != [] && "border-thamani-error") || "border-thamani-stone"
          ]}
        >
          <span data-tc-display class="truncate text-[var(--thamani-pewter)]">
            {@placeholder || "Select…"}
          </span>
          <span
            data-tc-chevron
            class="inline-flex shrink-0 text-[var(--thamani-pewter)] transition-transform duration-150"
          >
            <.icon name="hero-chevron-down" class="size-4" />
          </span>
        </button>
        <div
          data-tc-dropdown
          role="listbox"
          class="absolute z-[70] mt-1 hidden w-full overflow-hidden rounded-xl border border-thamani-stone bg-thamani-snow shadow-lg"
        >
          <div class="border-b border-thamani-stone/50 px-2 pb-1.5 pt-2">
            <input
              data-tc-search
              type="text"
              placeholder="Search…"
              autocomplete="off"
              class="w-full rounded-lg border-0 bg-thamani-stone/40 px-2.5 py-1.5 text-sm text-thamani-forest outline-none placeholder:text-thamani-pewter/50"
            />
          </div>
          <div data-tc-list class="max-h-52 overflow-y-auto py-1"></div>
        </div>
      </div>
      <p :for={msg <- @errors} class="text-[13px] text-thamani-error mt-1.5">
        {msg}
      </p>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ThamaniCombobox">
        export default {
          mounted() { this.init() },
          updated() { this.syncDisplay() },
          destroyed() {
            document.removeEventListener("click", this.onDocClick)
            document.removeEventListener("keydown", this.onKey)
          },
          init() {
            this.input    = this.el.querySelector("[data-tc-input]")
            this.trigger  = this.el.querySelector("[data-tc-trigger]")
            this.display  = this.el.querySelector("[data-tc-display]")
            this.dropdown = this.el.querySelector("[data-tc-dropdown]")
            this.list     = this.el.querySelector("[data-tc-list]")
            this.search   = this.el.querySelector("[data-tc-search]")
            this.chevron  = this.el.querySelector("[data-tc-chevron]")
            this.renderList("")
            this.syncDisplay()
            this.onTrigger  = (e) => {
              e.preventDefault()
              e.stopPropagation()
              this.toggle()
            }
            this.onDocClick = (e) => { if (!this.el.contains(e.target)) this.close() }
            this.onKey      = (e) => { if (e.key === "Escape") this.close() }
            this.trigger.addEventListener("click", this.onTrigger)
            if (this.search) {
              this.search.addEventListener("input", () => this.renderList(this.search.value))
              this.search.addEventListener("click", (e) => e.stopPropagation())
              this.search.addEventListener("keydown", (e) => {
                if (e.key === "Escape") { e.stopPropagation(); this.close() }
                if (e.key === "ArrowDown") {
                  e.preventDefault()
                  const first = this.list.querySelector("[data-tc-val]")
                  if (first) first.focus()
                }
              })
            }
            document.addEventListener("click", this.onDocClick)
            document.addEventListener("keydown", this.onKey)
          },
          opts()   { return JSON.parse(this.el.dataset.options || "[]") },
          prompt() { return this.el.dataset.prompt || "" },
          renderList(query) {
            this.list.innerHTML = ""
            const q = (query || "").toLowerCase().trim()
            const cur = this.input ? String(this.input.value) : ""
            const allOpts = this.opts()
            const filtered = q === "" ? allOpts : allOpts.filter(([label]) => label.toLowerCase().includes(q))
            const p = this.prompt()
            if (p && q === "") this.list.appendChild(this.makeBtn("", p, false, true))
            if (filtered.length === 0) {
              const empty = document.createElement("div")
              empty.textContent = "No matches"
              empty.className = "px-3 py-2 text-sm text-center text-[var(--thamani-pewter)]"
              this.list.appendChild(empty)
              return
            }
            filtered.forEach(([label, val]) => {
              this.list.appendChild(this.makeBtn(String(val), label, String(val) === cur, false))
            })
          },
          makeBtn(val, label, active, isPrompt) {
            const b = document.createElement("button")
            b.type = "button"
            b.dataset.tcVal = val
            b.textContent = label
            b.tabIndex = 0
            b.className = active
              ? "block w-full text-left px-3 py-2 text-sm font-medium cursor-pointer outline-none text-[var(--thamani-forest)] bg-[color-mix(in_srgb,var(--thamani-lime)_26%,white)]"
              : "block w-full text-left px-3 py-2 text-sm cursor-pointer outline-none transition-colors hover:bg-thamani-stone/50 " +
                (isPrompt ? "text-[var(--thamani-pewter)]" : "text-base-content")
            b.addEventListener("mousedown", (e) => { e.preventDefault() })
            b.addEventListener("click", (e) => { e.stopPropagation(); this.select(b.dataset.tcVal) })
            b.addEventListener("keydown", (e) => {
              if (e.key === "Enter" || e.key === " ") { e.preventDefault(); this.select(b.dataset.tcVal) }
              if (e.key === "ArrowDown") { e.preventDefault(); const n = b.nextElementSibling; if (n) n.focus() }
              if (e.key === "ArrowUp")   {
                e.preventDefault()
                const p = b.previousElementSibling
                if (p && p.dataset.tcVal !== undefined) p.focus()
                else if (this.search) this.search.focus()
              }
            })
            return b
          },
          select(val) {
            this.input.value = val
            this.input.dispatchEvent(new Event("input",  { bubbles: true }))
            this.input.dispatchEvent(new Event("change", { bubbles: true }))
            this.renderList("")
            this.syncDisplay()
            this.close()
          },
          syncDisplay() {
            if (!this.input || !this.display) return
            const val   = String(this.input.value)
            const match = this.opts().find(([, v]) => String(v) === val)
            if (match) {
              this.display.textContent = match[0]
              this.display.classList.remove("text-[var(--thamani-pewter)]")
            } else {
              this.display.textContent = this.prompt() || "Select…"
              this.display.classList.add("text-[var(--thamani-pewter)]")
            }
          },
          toggle() { this.dropdown.classList.contains("hidden") ? this.open() : this.close() },
          open() {
            if (this.search) this.search.value = ""
            this.renderList("")
            this.dropdown.classList.remove("hidden")
            this.trigger.setAttribute("aria-expanded", "true")
            if (this.chevron) this.chevron.style.transform = "rotate(180deg)"
            setTimeout(() => { if (this.search) this.search.focus() }, 10)
          },
          close() {
            this.dropdown.classList.add("hidden")
            this.trigger.setAttribute("aria-expanded", "false")
            if (this.chevron) this.chevron.style.transform = ""
            if (this.search) this.search.value = ""
          }
        }
      </script>
    </div>
    """
  end

  def thamani_input(%{type: "select", field: field} = assigns) do
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
          class="block text-[13px] font-medium text-thamani-pewter tracking-[0.01em]"
        >
          {@label}<span :if={@required} class="text-red-600">&nbsp;*</span>
        </label>
      </div>
      <select
        id={@input_id}
        name={@name}
        required={@required}
        class={[
          "w-full box-border px-4 py-3 text-[15px] text-base-content bg-thamani-snow",
          "border-[1.5px] rounded-lg outline-none",
          "transition-[border-color,box-shadow] duration-150 ease-in-out",
          "focus:border-thamani-accent focus:shadow-[0_0_0_3px_rgba(102,103,171,0.12)]",
          (@errors != [] && "border-thamani-error") || "border-thamani-stone"
        ]}
        {@rest}
      >
        <option :if={@placeholder} value="">{@placeholder}</option>
        <option
          :for={{label, value} <- @options}
          value={value}
          selected={to_string(@value) == to_string(value)}
        >
          {label}
        </option>
      </select>
      <p :for={msg <- @errors} class="text-[13px] text-thamani-error mt-1.5">
        {msg}
      </p>
    </div>
    """
  end

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
          class="block text-[13px] font-medium text-thamani-pewter tracking-[0.01em]"
        >
          {@label}<span :if={@required} class="text-red-600">&nbsp;*</span>
        </label>
      </div>
      <textarea
        id={@input_id}
        name={@name}
        placeholder={@placeholder}
        required={@required}
        class={[
          "w-full box-border px-4 py-3 text-[15px] text-base-content bg-thamani-surface",
          "border-[1.5px] rounded-lg outline-none",
          "transition-[border-color,box-shadow] duration-150 ease-in-out",
          "focus:border-thamani-accent focus:shadow-[0_0_0_3px_rgba(102,103,171,0.12)]",
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
      |> assign(:input_type, if(assigns.sensitive, do: "text", else: assigns.type))

    ~H"""
    <div class={["mb-5", @class]}>
      <div class={[
        "flex items-baseline justify-between mb-2",
        @errors != [] && "mb-1"
      ]}>
        <label
          for={@input_id}
          class="block text-[13px] font-medium text-thamani-pewter tracking-[0.01em]"
        >
          {@label}<span :if={@required} class="text-red-600">&nbsp;*</span>
        </label>
      </div>
      <div class="relative">
        <span
          :if={@icon}
          class="pointer-events-none absolute inset-y-0 left-3.5 flex items-center text-thamani-pewter"
        >
          <.icon name={@icon} class="size-[18px]" />
        </span>
        <input
          id={@input_id}
          type={@input_type}
          name={@name}
          value={Phoenix.HTML.Form.normalize_value(@input_type, assigns[:value])}
          placeholder={@placeholder}
          autocomplete={@autocomplete}
          required={@required}
          class={[
            "w-full box-border px-4 py-3 text-[15px] text-base-content bg-thamani-surface",
            "border-[1.5px] rounded-lg outline-none",
            "transition-[border-color,box-shadow] duration-150 ease-in-out",
            "focus:border-thamani-accent focus:shadow-[0_0_0_3px_rgba(102,103,171,0.12)]",
            if(@icon, do: "pl-11!", else: "pl-4!"),
            (@type == "password" || @sensitive) && "pr-11!",
            @sensitive && "[-webkit-text-security:disc]",
            (@errors != [] && "border-thamani-error") || "border-thamani-stone"
          ]}
          {@rest}
        />
        <span
          :if={@badge != []}
          class={[
            "pointer-events-none absolute inset-y-0 flex items-center",
            (@type == "password" || @sensitive) && "right-11",
            !(@type == "password" || @sensitive) && "right-3"
          ]}
        >
          {render_slot(@badge)}
        </span>
        <button
          :if={@type == "password" || @sensitive}
          type="button"
          id={"#{@input_id}-toggle"}
          aria-label="Show password"
          class="absolute inset-y-0 right-3 flex items-center text-thamani-pewter hover:text-thamani-forest"
          phx-click={
            if @sensitive do
              JS.toggle_class("[-webkit-text-security:disc]", to: "##{@input_id}")
            else
              JS.toggle_attribute({"type", "text", "password"}, to: "##{@input_id}")
            end
            |> JS.toggle(to: "##{@input_id}-eye")
            |> JS.toggle(to: "##{@input_id}-eye-slash")
          }
        >
          <span id={"#{@input_id}-eye"}><.icon name="hero-eye" class="size-5" /></span>
          <span id={"#{@input_id}-eye-slash"} class="hidden">
            <.icon name="hero-eye-slash" class="size-5" />
          </span>
        </button>
      </div>
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
  attr :close_on_click_away, :boolean, default: true
  attr :class, :any, default: nil

  attr :title, :string,
    default: nil,
    doc: "dialog title (Doop TD Modal HtFGl5-GrG); every converted dialog sets it"

  attr :subtitle, :string, default: nil

  attr :size, :string,
    values: ~w(form confirm wide),
    default: "form",
    doc: "form = 560px, confirm = 480px, wide = 640px (multi-step flows)"

  slot :inner_block, required: true
  slot :header_actions, doc: "optional actions in the title row, before close"
  slot :footer, doc: "right-aligned actions: secondary Cancel, then the primary"

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0"
        style="background: var(--color-td-scrim);"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="td-modal-stage">
          <div class={["td-modal-slot", "is-#{@size}", @class]}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={
                if @close_on_click_away,
                  do: JS.exec("data-cancel", to: "##{@id}"),
                  else: nil
              }
              class="td-modal hidden"
            >
              <div :if={@title} class="td-modal-hd">
                <div class="td-modal-tt">
                  <h2 id={"#{@id}-title"}>{@title}</h2>
                  <p :if={@subtitle} id={"#{@id}-description"}>{@subtitle}</p>
                </div>
                <div class="td-modal-hd-end">
                  <div :if={@header_actions != []} class="td-modal-hd-actions">
                    {render_slot(@header_actions)}
                  </div>
                  <button
                    phx-click={JS.exec(@on_cancel, "phx-remove")}
                    type="button"
                    class="td-icon-btn td-modal-close"
                    aria-label="Close"
                  >
                    <.icon name="x" class="size-4" />
                  </button>
                </div>
              </div>
              <%!-- Legacy dialogs without a title keep their in-body heading
                   until each is rebuilt to its Doop frame; they get only a
                   floating close button, never an empty header band. --%>
              <button
                :if={!@title}
                phx-click={JS.exec(@on_cancel, "phx-remove")}
                type="button"
                class="td-icon-btn td-modal-close is-floating"
                aria-label="Cancel"
              >
                <.icon name="x" class="size-4" />
              </button>
              <div id={"#{@id}-content"} class="td-modal-bd">
                {render_slot(@inner_block)}
              </div>
              <div :if={@footer != []} class="td-modal-ft">{render_slot(@footer)}</div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the canonical toolbar search box: a plain text input styled the
  same way everywhere it appears. Pair with `phx-change`/`phx-submit` on
  the wrapping `<form>`.

  ## Examples

      <form phx-change="search">
        <.search_input name="search" value={@search} placeholder="Search by name, GTIN, or category" />
      </form>
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, required: true
  attr :debounce, :string, default: "300"
  attr :rest, :global

  def search_input(assigns) do
    ~H"""
    <input
      type="text"
      name={@name}
      value={@value}
      placeholder={@placeholder}
      phx-debounce={@debounce}
      phx-key="escape"
      phx-keydown={JS.push("search", value: %{"search" => ""})}
      class="thamani-input h-[40px] w-full rounded-xl px-4 text-sm focus:border-thamani-forest focus:outline-none focus:ring-0 transition-colors"
      {@rest}
    />
    """
  end

  @doc """
  Renders a "Filters" trigger button that opens an anchored dropdown panel
  below it.

  Groups filter fields under labeled sections and applies them as a single
  batch via an explicit "Apply filters" button, rather than firing an event
  per field change. Opening and closing is pure client-side JS — no
  LiveView round trip — mirroring how `modal/1` opens and closes. The
  panel is sized to its content (not the full viewport height) and
  anchored to the trigger button, like a dropdown menu.

  The caller keeps its existing `phx-submit`/`phx-click` event names
  (typically the same handlers an inline filter form already used); this
  component only supplies the surrounding chrome.

  ## Examples

      <.filter_drawer
        id="products-filters"
        title="Filter products"
        apply_event="apply_filters"
        active_count={count_active_filters(@filters)}
      >
        <:group label="Category">
          <.input type="select" name="filters[category]" ... />
        </:group>
        <:chip :for={chip <- filter_chips(@filters)} label={chip.label} clear={chip.clear} />
      </.filter_drawer>
  """
  attr :id, :string, required: true
  attr :title, :string, default: "Filters"
  attr :trigger_label, :string, default: "Filters"
  attr :active_count, :integer, default: 0

  attr :variant, :string,
    default: "outline",
    values: ~w(outline solid),
    doc:
      ~s|"outline" (default) keeps the light/gray trigger; "solid" renders it filled with| <>
        " the primary purple even when no filters are active, for pages that want the button" <>
        " to read as a primary action"

  attr :apply_event, :string,
    required: true,
    doc: "phx-submit (or, when instant: true, phx-change) target for the filter fields"

  attr :clear_event, :string, default: "clear_filters"

  attr :instant, :boolean,
    default: false,
    doc:
      "if true, fields apply on every change instead of requiring an explicit Apply click; " <>
        "the drawer stays open and hides the Apply button, since there's nothing to apply"

  slot :group, required: true do
    attr :label, :string, required: true
  end

  slot :chip,
    doc:
      "one per currently-active filter value, rendered as a removable pill below the " <>
        "search/filter bar, plus a trailing \"Clear all\" link. The parent element the " <>
        "caller places <.filter_drawer> in should allow wrapping (e.g. `flex flex-wrap`), " <>
        "since the chip row renders as a `w-full` sibling of the trigger button." do
    attr :label, :string, required: true

    attr :clear, :any,
      required: true,
      doc: "phx-click value (event name string, or a JS command) fired to remove just this chip"
  end

  def filter_drawer(assigns) do
    ~H"""
    <div
      id={"#{@id}-wrap"}
      class="td-fd relative block w-full min-[480px]:inline-block min-[480px]:w-auto"
      phx-hook=".FilterDrawerAlign"
    >
      <button
        type="button"
        phx-click={show_filter_drawer(@id)}
        class={[
          "flex h-[40px] w-full items-center justify-center gap-2 rounded-md border px-4 text-sm font-medium whitespace-nowrap transition min-[480px]:w-auto",
          @active_count > 0 &&
            "border-transparent bg-td-accent-tint text-thamani-forest hover:bg-td-accent-tint",
          @active_count == 0 && @variant == "outline" &&
            "border-transparent bg-[var(--color-td-control)] text-[var(--color-td-ink)] hover:bg-[var(--color-td-selected)]",
          @active_count == 0 && @variant == "solid" &&
            "border-thamani-forest bg-thamani-forest text-thamani-on-accent hover:bg-thamani-forest/90"
        ]}
      >
        <.icon name="hero-adjustments-horizontal" class="h-4 w-4" />
        {@trigger_label}
        <span
          :if={@active_count > 0}
          class="inline-flex h-5 w-5 items-center justify-center rounded-full bg-thamani-forest text-xs font-semibold text-thamani-on-accent"
        >
          {@active_count}
        </span>
      </button>

      <div id={@id} class="relative z-50 hidden" phx-remove={hide_filter_drawer(@id)}>
        <div
          id={"#{@id}-panel"}
          class="td-fd-panel absolute top-full z-50 mt-2 hidden w-[min(30rem,calc(100vw-2rem))] sm:w-[34rem] max-w-2xl scale-95 transform flex-col rounded-2xl ff-surface-modal opacity-0 transition shadow-2xl border border-thamani-stone bg-[var(--color-td-raised)] overflow-visible"
          role="dialog"
          aria-modal="true"
          aria-labelledby={"#{@id}-title"}
          tabindex="0"
          phx-click-away={hide_filter_drawer(@id)}
          phx-window-keydown={hide_filter_drawer(@id)}
          phx-key="escape"
        >
          <div class="flex items-center justify-between gap-4 border-b border-thamani-stone px-5 py-4 sm:px-6">
            <h2 id={"#{@id}-title"} class="min-w-0 flex-1 text-lg font-semibold text-thamani-forest">
              {@title}
            </h2>
            <div class="flex shrink-0 items-center gap-2">
              <button
                type="button"
                phx-click={JS.push(@clear_event) |> hide_filter_drawer(@id)}
                class="rounded-md px-2.5 py-1.5 text-sm font-semibold text-thamani-forest hover:bg-thamani-stone/70 hover:underline cursor-pointer"
              >
                Reset all
              </button>
              <button
                type="button"
                phx-click={hide_filter_drawer(@id)}
                class="rounded-md p-2 text-td-ink-3 hover:bg-td-wash hover:text-td-ink-2"
                aria-label={gettext("close")}
              >
                <.icon name="hero-x-mark-solid" class="h-5 w-5" />
              </button>
            </div>
          </div>

          <form
            id={"#{@id}-form"}
            phx-change={@instant && @apply_event}
            phx-submit={
              if @instant,
                do: JS.push(@apply_event),
                else: JS.push(@apply_event) |> hide_filter_drawer(@id)
            }
            class="flex min-h-0 flex-1 flex-col overflow-visible"
          >
            <button type="reset" id={"#{@id}-reset-btn"} class="hidden" aria-hidden="true" />

            <div class="flex-1 overflow-visible px-5 py-5 sm:px-6 min-h-[16rem]">
              <div class={["grid grid-cols-1 gap-6", length(@group) > 1 && "sm:grid-cols-2"]}>
                <div :for={group <- @group} class="overflow-visible">
                  <h3 class="mb-3 text-xs font-semibold tracking-wide text-td-ink-2 uppercase">
                    {group.label}
                  </h3>
                  <div class="overflow-visible">
                    {render_slot(group)}
                  </div>
                </div>
              </div>
            </div>

            <div class="flex items-center justify-end gap-3 border-t border-thamani-stone bg-thamani-canvas px-5 py-4 sm:px-6">
              <button
                type="button"
                phx-click={JS.push(@clear_event) |> hide_filter_drawer(@id)}
                class="rounded-md bg-thamani-surface px-4 py-2 text-sm font-medium text-td-ink ring-1 ring-td-hairline hover:bg-td-wash"
              >
                Clear filters
              </button>
              <button
                :if={!@instant}
                type="submit"
                class="rounded-md bg-thamani-forest px-4 py-2 text-sm font-medium text-td-on-accent shadow-sm hover:bg-thamani-forest/90"
              >
                Apply filters
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>

    <div
      :if={@chip != []}
      class="mt-3 flex w-full flex-wrap items-center gap-2 min-[480px]:col-span-2"
    >
      <span
        :for={chip <- @chip}
        class="inline-flex items-center gap-1.5 rounded-full bg-td-accent-tint px-3 py-1 text-sm font-medium text-thamani-forest"
      >
        {chip.label}
        <button
          type="button"
          phx-click={chip.clear}
          class="text-thamani-forest/70 hover:text-thamani-forest"
          aria-label={"Remove #{chip.label} filter"}
        >
          <.icon name="hero-x-mark-solid" class="h-3.5 w-3.5" />
        </button>
      </span>
      <button
        type="button"
        phx-click={@clear_event}
        class="text-sm font-medium text-thamani-forest hover:underline"
      >
        Clear all
      </button>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".FilterDrawerAlign">
      // The panel opens toward the side with room, so it never slides under the sidebar
      // or off the right edge of the content area.
      export default {
        mounted() { this.align(); this.onResize = () => this.align(); window.addEventListener("resize", this.onResize); this.el.addEventListener("click", () => this.align(), true) },
        updated() { this.align() },
        destroyed() { window.removeEventListener("resize", this.onResize) },
        align() {
          const panel = this.el.querySelector(".td-fd-panel")
          if (!panel) return
          const r = this.el.getBoundingClientRect()
          const area = (this.el.closest("main") || document.body).getBoundingClientRect()
          const w = Math.min(544, window.innerWidth - 32)
          this.el.classList.toggle("is-left", r.right - w < area.left && r.left + w <= area.right)
        }
      }
    </script>
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

  def show_filter_drawer(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.dispatch("click", to: "##{id}-reset-btn")
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-panel",
      display: "flex",
      time: 150,
      transition:
        {"transition transform ease-out duration-150", "opacity-0 scale-95",
         "opacity-100 scale-100"}
    )
    |> JS.focus_first(to: "##{id}-panel")
  end

  def hide_filter_drawer(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-panel",
      time: 100,
      transition:
        {"transition transform ease-in duration-100", "opacity-100 scale-100",
         "opacity-0 scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"}, time: 150)
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

  @doc """
  Renders pagination controls for Scrivener pagination.

  ## Examples

      <.pagination page={@page} path={~p"/org/products"} />
  """
  attr :page, :map, required: true, doc: "Scrivener page object"
  attr :path, :string, required: true, doc: "Base path for pagination links"
  attr :query_param, :string, default: "page", doc: "Query parameter name for page number"

  def pagination(assigns) do
    page = assigns.page
    total_pages = page.total_pages || 1
    current_page = page.page_number || 1
    total_entries = page.total_entries || 0
    page_size = page.page_size || 10

    from_item = (current_page - 1) * page_size + 1
    to_item = min(current_page * page_size, total_entries)

    has_prev = current_page > 1
    has_next = current_page < total_pages

    page_numbers = get_page_numbers(current_page, total_pages)

    assigns =
      assigns
      |> assign(:current_page, current_page)
      |> assign(:total_pages, total_pages)
      |> assign(:total_entries, total_entries)
      |> assign(:from_item, from_item)
      |> assign(:to_item, to_item)
      |> assign(:has_prev, has_prev)
      |> assign(:has_next, has_next)
      |> assign(:page_numbers, page_numbers)

    ~H"""
    <div class="mt-8 flex flex-col sm:flex-row items-center justify-between gap-4 border-t border-thamani-stone pt-6">
      <p class="pagination-summary order-2 sm:order-1 text-sm">
        Showing <span class="pagination-summary-value font-medium">{@from_item}</span>–<span class="pagination-summary-value font-medium">{@to_item}</span>
        of <span class="pagination-summary-value font-medium">{@total_entries}</span>
        results
      </p>

      <nav
        :if={@total_pages > 1}
        class="order-1 sm:order-2 flex items-center gap-1"
        aria-label="Pagination"
      >
        <.link
          navigate={build_pagination_url(@path, @current_page - 1, @query_param)}
          class={[
            "pagination-link inline-flex items-center justify-center size-10 rounded-lg transition-[background-color,color,scale] duration-150 active:scale-[0.96]",
            if(@has_prev,
              do: "",
              else: "pointer-events-none"
            )
          ]}
          aria-disabled={!@has_prev}
          title="Previous page"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </.link>

        <div class="flex items-center gap-1">
          <.link
            :for={page_num <- @page_numbers}
            navigate={
              if page_num != :ellipsis, do: build_pagination_url(@path, page_num, @query_param)
            }
            class={[
              "inline-flex items-center justify-center size-10 rounded-lg text-sm transition-[background-color,color,scale] duration-150 active:scale-[0.96]",
              if(page_num == :ellipsis,
                do: "pagination-ellipsis cursor-default",
                else: "pagination-link"
              )
            ]}
            aria-current={page_num == @current_page && "page"}
          >
            {if page_num == :ellipsis, do: "…", else: page_num}
          </.link>
        </div>

        <.link
          navigate={build_pagination_url(@path, @current_page + 1, @query_param)}
          class={[
            "pagination-link inline-flex items-center justify-center size-10 rounded-lg transition-[background-color,color,scale] duration-150 active:scale-[0.96]",
            if(@has_next,
              do: "",
              else: "pointer-events-none"
            )
          ]}
          aria-disabled={!@has_next}
          title="Next page"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </.link>
      </nav>
    </div>
    """
  end

  defp get_page_numbers(current_page, total_pages) do
    cond do
      total_pages <= 7 ->
        Enum.to_list(1..total_pages)

      current_page <= 4 ->
        Enum.to_list(1..5) ++ [:ellipsis, total_pages]

      current_page >= total_pages - 3 ->
        [1, :ellipsis] ++ Enum.to_list((total_pages - 4)..total_pages)

      true ->
        [1, :ellipsis] ++
          Enum.to_list((current_page - 1)..(current_page + 1)) ++ [:ellipsis, total_pages]
    end
  end

  defp build_pagination_url(path, page, query_param) do
    separator = if String.contains?(path, "?"), do: "&", else: "?"
    "#{path}#{separator}#{query_param}=#{page}"
  end
end
