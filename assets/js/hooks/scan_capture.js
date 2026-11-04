// A keyboard-wedge scanner may emit the GS1 FNC1 separator as ASCII 29, Tab,
// or Enter. Tab is preserved as ASCII 29; an Enter is briefly delayed so a
// following field can prove it was an internal separator rather than the end
// of the symbol.
export const ScanCapture = {
  endDelayMs: 250,

  mounted() {
    this.onKeydown = (event) => {
      if (event.key === "Enter") {
        event.preventDefault()
        this.scheduleFlush()
      } else if (event.key === "Tab" && this.el.value && !event.shiftKey) {
        event.preventDefault()
        this.cancelScheduledFlush()
        this.insertBoundary()
      } else if (this.flushTimer) {
        this.cancelScheduledFlush()
        this.insertBoundary()
      }
    }

    this.el.addEventListener("keydown", this.onKeydown)
  },

  scheduleFlush() {
    this.cancelScheduledFlush()
    this.flushTimer = setTimeout(() => {
      this.flushTimer = undefined
      this.flush()
    }, this.endDelayMs)
  },

  cancelScheduledFlush() {
    if (!this.flushTimer) return

    clearTimeout(this.flushTimer)
    this.flushTimer = undefined
  },

  insertBoundary() {
    if (this.el.value.startsWith("(")) return

    const start = this.el.selectionStart ?? this.el.value.length
    const end = this.el.selectionEnd ?? start
    this.el.setRangeText("\x1D", start, end, "end")
  },

  flush() {
    const raw_gs1 = this.el.value.trim()
    this.el.value = ""

    if (raw_gs1) {
      this.pushEvent(this.el.dataset.scanEvent || "scan", {raw_gs1})
    }
  },

  destroyed() {
    this.cancelScheduledFlush()
    this.el.removeEventListener("keydown", this.onKeydown)
  },
}
