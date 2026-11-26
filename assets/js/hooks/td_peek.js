// TD Peek (Doop cuo1ccz0cc): the card opens on hover/focus through CSS
// (300ms delay). This hook positions it fixed to the viewport so horizontal
// table scroll wrappers never clip it, adds Esc to close it, and stops clicks
// inside the card from triggering the clickable table row underneath.
import {placeTip} from "../lib/td_tip_place"

export const TdPeek = {
  mounted() {
    const anchor = () => this.el.querySelector(".td-pid") || this.el
    const pop = () => this.el.querySelector(".td-peek-pop")

    this.place = () => {
      const popEl = pop()
      if (!popEl) return
      const align = this.el.classList.contains("is-right") ? "end" : "start"
      const {side, top, left} = placeTip(anchor(), popEl, {preferred: "bottom", align})
      popEl.style.position = "fixed"
      popEl.style.top = `${top}px`
      popEl.style.left = `${left}px`
      popEl.style.right = "auto"
      popEl.dataset.side = side
    }

    this.onEnter = () => this.place()
    this.onScroll = () => {
      if (this.el.matches(":hover, :focus-within")) this.place()
    }
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
    this.el.addEventListener("mouseenter", this.onEnter)
    this.el.addEventListener("focusin", this.onEnter)
    this.el.addEventListener("keydown", this.onKey)
    this.el.addEventListener("mouseleave", this.onLeave)
    this.el.addEventListener("click", this.onClick)
    window.addEventListener("scroll", this.onScroll, {passive: true, capture: true})
  },
  destroyed() {
    this.el.removeEventListener("mouseenter", this.onEnter)
    this.el.removeEventListener("focusin", this.onEnter)
    this.el.removeEventListener("keydown", this.onKey)
    this.el.removeEventListener("mouseleave", this.onLeave)
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("scroll", this.onScroll, {capture: true})
  }
}
