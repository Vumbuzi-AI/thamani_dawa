import {hideTip, showTip} from "./td_tip"

export const TdChartTip = {
  mounted() {
    this.onOver = (event) => {
      const col = event.target.closest("[data-tip-title]")
      if (col && this.el.contains(col)) showTip(col)
    }
    this.onOut = (event) => {
      const col = event.target.closest("[data-tip-title]")
      if (!col) return
      if (event.relatedTarget && col.contains(event.relatedTarget)) return
      hideTip()
    }
    this.onFocusIn = (event) => {
      const col = event.target.closest("[data-tip-title]")
      if (col && this.el.contains(col)) showTip(col)
    }
    this.onFocusOut = () => hideTip()
    this.onKey = (event) => {
      if (event.key === "Escape") hideTip()
    }
    this.el.addEventListener("mouseover", this.onOver)
    this.el.addEventListener("mouseout", this.onOut)
    this.el.addEventListener("focusin", this.onFocusIn)
    this.el.addEventListener("focusout", this.onFocusOut)
    window.addEventListener("keydown", this.onKey)
  },
  updated() {
    hideTip()
  },
  destroyed() {
    this.el.removeEventListener("mouseover", this.onOver)
    this.el.removeEventListener("mouseout", this.onOut)
    this.el.removeEventListener("focusin", this.onFocusIn)
    this.el.removeEventListener("focusout", this.onFocusOut)
    window.removeEventListener("keydown", this.onKey)
    hideTip()
  }
}
