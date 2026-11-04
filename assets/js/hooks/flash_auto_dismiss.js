export const FlashAutoDismiss = {
  mounted() {
    this.scheduleDismiss()
  },

  updated() {
    this.scheduleDismiss()
  },

  scheduleDismiss() {
    window.clearTimeout(this.dismissTimer)

    const timeout = Number(this.el.dataset.timeout)
    if (!timeout || timeout < 1) return

    this.dismissTimer = window.setTimeout(() => {
      this.el.querySelector("[data-flash-dismiss]")?.click()
    }, timeout)
  },

  destroyed() {
    window.clearTimeout(this.dismissTimer)
  }
}
