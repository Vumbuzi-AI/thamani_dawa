export const TdSelect = {
  mounted() {
    this.init()
  },
  updated() {
    this.syncDisplay()
  },
  destroyed() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
  },
  init() {
    this.input = this.el.querySelector("[data-cs-input]")
    this.trigger = this.el.querySelector("[data-cs-trigger]")
    this.display = this.el.querySelector("[data-cs-display]")
    this.dropdown = this.el.querySelector("[data-cs-dropdown]")
    this.list = this.el.querySelector("[data-cs-list]")
    this.search = this.el.querySelector("[data-cs-search]")
    this.chevron = this.el.querySelector("[data-cs-chevron]")
    this.renderList("")
    this.syncDisplay()
    this.onTrigger = (e) => {
      if (this.trigger.disabled) return
      e.preventDefault()
      e.stopPropagation()
      this.toggle()
    }
    this.onDocClick = (e) => {
      if (!this.el.contains(e.target)) this.close()
    }
    this.onKey = (e) => {
      if (e.key === "Escape") this.close()
    }
    this.trigger.addEventListener("click", this.onTrigger)
    if (this.search) {
      this.search.addEventListener("input", () => this.renderList(this.search.value))
      this.search.addEventListener("click", (e) => e.stopPropagation())
      this.search.addEventListener("keydown", (e) => {
        if (e.key === "Escape") {
          e.stopPropagation()
          this.close()
        }
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
  opts() {
    return JSON.parse(this.el.dataset.options || "[]")
  },
  prompt() {
    return this.el.dataset.prompt || ""
  },
  renderList(query) {
    this.list.innerHTML = ""
    const q = (query || "").toLowerCase().trim()
    const cur = this.input ? String(this.input.value) : ""
    const allOpts = this.opts()
    const filtered =
      q === "" ? allOpts : allOpts.filter(([label]) => label.toLowerCase().includes(q))
    const p = this.prompt()
    if (p && q === "") this.list.appendChild(this.makeBtn("", p, false, true))
    if (filtered.length === 0) {
      const empty = document.createElement("div")
      empty.textContent = "No matches"
      empty.className = "td-select-empty"
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
    b.className = ["td-select-opt", active && "is-active", isPrompt && "is-prompt"]
      .filter(Boolean)
      .join(" ")
    b.addEventListener("mousedown", (e) => {
      e.preventDefault()
    })
    b.addEventListener("click", (e) => {
      e.stopPropagation()
      this.select(b.dataset.csVal)
    })
    b.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault()
        this.select(b.dataset.csVal)
      }
      if (e.key === "ArrowDown") {
        e.preventDefault()
        const n = b.nextElementSibling
        if (n) n.focus()
      }
      if (e.key === "ArrowUp") {
        e.preventDefault()
        const prev = b.previousElementSibling
        if (prev && prev.dataset.csVal !== undefined) prev.focus()
        else if (this.search) this.search.focus()
      }
    })
    return b
  },
  select(val) {
    this.input.value = val
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
    this.input.dispatchEvent(new Event("change", {bubbles: true}))
    this.renderList("")
    this.syncDisplay()
    this.close()
  },
  syncDisplay() {
    if (!this.input || !this.display) return
    const val = String(this.input.value)
    const match = this.opts().find(([, v]) => String(v) === val)
    if (match) {
      this.display.textContent = match[0]
      this.el.dataset.state = "default"
    } else {
      this.display.textContent = this.prompt() || "Select…"
      this.el.dataset.state = "placeholder"
    }
  },
  toggle() {
    this.dropdown.classList.contains("hidden") ? this.open() : this.close()
  },
  open() {
    if (this.search) this.search.value = ""
    this.renderList("")
    this.dropdown.classList.remove("hidden")
    this.dropdown.classList.remove("is-up")
    const r = this.trigger.getBoundingClientRect()
    const h = this.dropdown.offsetHeight
    if (window.innerHeight - r.bottom < h + 12 && r.top > h + 12) {
      this.dropdown.classList.add("is-up")
    }
    this.trigger.setAttribute("aria-expanded", "true")
    this.el.dataset.state = "focus"
    if (this.chevron) this.chevron.style.transform = "rotate(180deg)"
    setTimeout(() => {
      if (this.search) this.search.focus()
    }, 10)
  },
  close() {
    this.dropdown.classList.add("hidden")
    this.trigger.setAttribute("aria-expanded", "false")
    if (this.chevron) this.chevron.style.transform = ""
    if (this.search) this.search.value = ""
    this.syncDisplay()
  },
}
