export const FlashAutoDismiss = {
  mounted() {
    this.lastMessage = this.currentMessage()
    this.scheduleDismiss()
  },

  updated() {
    const message = this.currentMessage()
    if (message !== this.lastMessage) {
      this.lastMessage = message
      this.scheduleDismiss()
    }
  },

  currentMessage() {
    return this.el.textContent
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
