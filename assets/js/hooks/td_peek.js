// TD Peek (Doop cuo1ccz0cc): the card opens on hover/focus through CSS
// (300ms delay). This hook adds Esc to close it, and stops clicks inside
// the card from triggering the clickable table row underneath.
export const TdPeek = {
  mounted() {
    this.onKey = (e) => {
      if (e.key === "Escape") {
        this.el.classList.add("is-dismissed")
        const focused = this.el.querySelector(":focus")
        if (focused) focused.blur()
      }
    }
    this.onLeave = () => this.el.classList.remove("is-dismissed")
    this.onClick = (e) => {
      if (!e.target.closest(".td-peek-pop") && !e.target.closest("a.td-pid")) return
      // Keep the click off the row underneath; follow links ourselves.
      e.stopPropagation()
      const link = e.target.closest("a[href]")
      if (link && !e.metaKey && !e.ctrlKey) {
        e.preventDefault()
        this.js().navigate(link.getAttribute("href"))
      }
    }
    this.el.addEventListener("keydown", this.onKey)
    this.el.addEventListener("mouseleave", this.onLeave)
    this.el.addEventListener("click", this.onClick)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKey)
    this.el.removeEventListener("mouseleave", this.onLeave)
    this.el.removeEventListener("click", this.onClick)
  }
}
