const GAP = 8
const MARGIN = 8
const ARROW_INSET = 10
const OPPOSITE = {top: "bottom", bottom: "top", left: "right", right: "left"}

function clamp(n, min, max) {
  return Math.max(min, Math.min(n, max))
}

function point(side, ar, tw, th, align) {
  if (side === "top" || side === "bottom") {
    const top = side === "top" ? ar.top - th - GAP : ar.bottom + GAP
    let left = ar.left + ar.width / 2 - tw / 2
    if (align === "end") left = ar.right - tw
    if (align === "start") left = ar.left
    return {top, left}
  }
  const left = side === "left" ? ar.left - tw - GAP : ar.right + GAP
  return {top: ar.top + ar.height / 2 - th / 2, left}
}

function fits(p, tw, th, vw, vh) {
  return (
    p.left >= MARGIN &&
    p.top >= MARGIN &&
    p.left + tw <= vw - MARGIN &&
    p.top + th <= vh - MARGIN
  )
}

function visibleArea(p, tw, th, vw, vh) {
  const x1 = Math.max(p.left, MARGIN)
  const y1 = Math.max(p.top, MARGIN)
  const x2 = Math.min(p.left + tw, vw - MARGIN)
  const y2 = Math.min(p.top + th, vh - MARGIN)
  return Math.max(0, x2 - x1) * Math.max(0, y2 - y1)
}

function order(preferred) {
  const first = preferred === "auto" || !OPPOSITE[preferred] ? "top" : preferred
  const rest = ["top", "bottom", "left", "right"].filter((side) => side !== first && side !== OPPOSITE[first])
  return [first, OPPOSITE[first], ...rest]
}

export function placeTip(anchor, tipEl, {preferred = "auto", align = "center"} = {}) {
  const ar = anchor.getBoundingClientRect()
  const tw = tipEl.offsetWidth
  const th = tipEl.offsetHeight
  const vw = window.innerWidth
  const vh = window.innerHeight
  const sides = order(preferred)

  let side = sides[0]
  let p = point(side, ar, tw, th, align)

  for (const next of sides) {
    const cand = point(next, ar, tw, th, align)
    if (fits(cand, tw, th, vw, vh)) {
      side = next
      p = cand
      break
    }
    if (visibleArea(cand, tw, th, vw, vh) > visibleArea(p, tw, th, vw, vh)) {
      side = next
      p = cand
    }
  }

  p.left = clamp(p.left, MARGIN, Math.max(MARGIN, vw - tw - MARGIN))
  p.top = clamp(p.top, MARGIN, Math.max(MARGIN, vh - th - MARGIN))

  const along = side === "top" || side === "bottom" ? tw : th
  const mid =
    side === "top" || side === "bottom"
      ? ar.left + ar.width / 2 - p.left
      : ar.top + ar.height / 2 - p.top

  return {
    side,
    top: p.top,
    left: p.left,
    arrow: clamp(mid, ARROW_INSET, Math.max(ARROW_INSET, along - ARROW_INSET))
  }
}
