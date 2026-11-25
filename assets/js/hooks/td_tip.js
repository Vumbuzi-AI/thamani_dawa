import {placeTip} from "../lib/td_tip_place"

const ID = "td-tip-float"

function floatEl() {
  let el = document.getElementById(ID)
  if (!el) {
    el = document.createElement("div")
    el.id = ID
    el.setAttribute("role", "tooltip")
    el.hidden = true
    el.innerHTML = "<b></b><span></span>"
    document.body.appendChild(el)
  }
  return el
}

export function hideTip() {
  const el = document.getElementById(ID)
  if (el) el.hidden = true
}

function anchorFrom(node) {
  if (!node || !(node instanceof Element)) return null
  const tip = node.closest(".td-tip")
  if (tip && tip.querySelector(".td-tip-trigger")) {
    return {
      el: tip.querySelector(".td-tip-trigger") || tip,
      title: tip.getAttribute("data-tooltip") || "",
      delta: "",
      variant: "label",
      preferred: tip.getAttribute("data-side") || "auto",
      align: tip.getAttribute("data-align") || "center"
    }
  }
  const col = node.closest("[data-tip-title]")
  if (col) {
    return {
      el: col.querySelector(".td-fill i") || col,
      title: col.getAttribute("data-tip-title") || "",
      delta: col.getAttribute("data-tip-delta") || "",
      variant: "stat",
      preferred: "auto",
      align: col.getAttribute("data-tip-align") || "center"
    }
  }
  return null
}

export function showTip(target) {
  const src = anchorFrom(target)
  if (!src || !src.title) return
  const el = floatEl()
  el.dataset.variant = src.variant
  el.querySelector("b").textContent = src.title
  const line = el.querySelector("span")
  line.textContent = src.delta
  line.hidden = src.delta === ""
  el.hidden = false
  const placed = placeTip(src.el, el, {preferred: src.preferred, align: src.align})
  el.dataset.side = placed.side
  el.style.top = `${placed.top}px`
  el.style.left = `${placed.left}px`
  el.style.setProperty("--td-tip-arrow", `${placed.arrow}px`)
}

export function bindTdTips() {
  if (window.__tdTipsBound) return
  window.__tdTipsBound = true
  document.documentElement.classList.add("is-td-tip-js")

  const onOver = (event) => {
    const src = anchorFrom(event.target)
    if (src) showTip(event.target)
  }
  const onOut = (event) => {
    const src = anchorFrom(event.target)
    if (!src) return
    const next = event.relatedTarget
    if (next && src.el.closest(".td-tip, [data-tip-title]")?.contains(next)) return
    hideTip()
  }
  const onFocusIn = (event) => {
    if (anchorFrom(event.target)) showTip(event.target)
  }
  const onFocusOut = () => hideTip()
  const onKey = (event) => {
    if (event.key === "Escape") hideTip()
  }

  document.addEventListener("mouseover", onOver)
  document.addEventListener("mouseout", onOut)
  document.addEventListener("focusin", onFocusIn)
  document.addEventListener("focusout", onFocusOut)
  window.addEventListener("keydown", onKey)
  window.addEventListener("scroll", hideTip, true)
  window.addEventListener("resize", hideTip)
}
