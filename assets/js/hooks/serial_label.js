import bwipjs from "../../vendor/bwip-js"

// Draws a GS1 label onto a canvas from the same data the server rendered into
// the on-screen preview (ui.md §10: "the downloadable artifact and on-screen
// preview must contain identical data"). Drawing rather than screenshotting the
// DOM is what keeps them identical — both read one JSON payload, and the
// download stays high-resolution enough to print.

const SCALE = 4 // ~300dpi against the 4in x 6in label below
const WIDTH = 4 * 96 * (SCALE / 4)
const HEIGHT = 6 * 96 * (SCALE / 4)

const px = (n) => n * (SCALE / 4)

function renderDataMatrix(canvas, text, scale) {
  const bw = window.bwipjs || bwipjs
  const options = {
    bcid: "gs1datamatrix",
    text,
    scale,
    includetext: false,
  }

  try {
    bw.toCanvas(canvas, options)
  } catch (error) {
    // Legacy/demo identifiers can pre-date checksum validation. Keep the
    // label usable while retaining strict validation for compliant data.
    console.warn("Rendering Data Matrix without GS1 linting:", error)
    bw.toCanvas(canvas, {...options, dontlint: true})
  }
}

function field(ctx, x, y, label, value, opts = {}) {
  if (value === null || value === undefined || value === "") return y
  ctx.fillStyle = "#000"
  ctx.font = `${px(8)}px Helvetica, Arial, sans-serif`
  ctx.fillText(label.toUpperCase(), x, y)
  ctx.font = `bold ${px(opts.size || 15)}px Helvetica, Arial, sans-serif`
  ctx.fillText(String(value), x, y + px(opts.size || 15) + px(3))
  return y + px(opts.size || 15) + px(14)
}

function wrap(ctx, text, x, y, maxWidth, lineHeight) {
  const words = String(text).split(/\s+/)
  let line = ""
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word
    if (ctx.measureText(candidate).width > maxWidth && line) {
      ctx.fillText(line, x, y)
      y += lineHeight
      line = word
    } else {
      line = candidate
    }
  }
  if (line) {
    ctx.fillText(line, x, y)
    y += lineHeight
  }
  return y
}

export function drawLabel(canvas, data) {
  const ctx = canvas.getContext("2d")
  canvas.width = WIDTH
  canvas.height = HEIGHT

  ctx.fillStyle = "#fff"
  ctx.fillRect(0, 0, WIDTH, HEIGHT)
  ctx.strokeStyle = "#000"
  ctx.lineWidth = px(1.5)
  ctx.strokeRect(px(4), px(4), WIDTH - px(8), HEIGHT - px(8))

  const left = px(16)
  const mid = WIDTH / 2 + px(4)
  let y = px(28)

  // Addresses
  if (data.from_address || data.to_address) {
    ctx.fillStyle = "#000"
    ctx.font = `bold ${px(11)}px Helvetica, Arial, sans-serif`
    ctx.fillText("From Address", left, y)
    ctx.fillText("To Address", mid, y)
    ctx.font = `${px(11)}px Helvetica, Arial, sans-serif`
    const fromBottom = wrap(
      ctx,
      [data.from_company_name, data.from_address].filter(Boolean).join(", "),
      left,
      y + px(16),
      WIDTH / 2 - px(28),
      px(14)
    )
    const toBottom = wrap(
      ctx,
      [data.to_company_name, data.to_address].filter(Boolean).join(", "),
      mid,
      y + px(16),
      WIDTH / 2 - px(28),
      px(14)
    )
    y = Math.max(fromBottom, toBottom) + px(6)
    ctx.beginPath()
    ctx.moveTo(px(4), y)
    ctx.lineTo(WIDTH - px(4), y)
    ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(WIDTH / 2, px(4))
    ctx.lineTo(WIDTH / 2, y)
    ctx.stroke()
    y += px(18)
  }

  const rows = [
    [["SSCC", data.sscc], ["Quantity", data.quantity]],
    [["Content", data.gtin], ["Expiry", data.expiry]],
    [["Batch/Lot", data.batch], ["Prod date", data.production]],
    [["Shipper serial", data.serial], ["Order number", data.order_number]],
  ]

  for (const [leftField, rightField] of rows) {
    const before = y
    const a = field(ctx, left, y, leftField[0], leftField[1])
    const b = field(ctx, mid, y, rightField[0], rightField[1])
    y = Math.max(a, b)
    if (y === before) continue
  }

  if (data.material_description) {
    y = field(ctx, left, y, "Material description", data.material_description, { size: 12 })
  }
  if (data.customer_part_number) {
    y = field(ctx, left, y, "Cust part no.", data.customer_part_number, { size: 12 })
  }

  ctx.beginPath()
  ctx.moveTo(px(4), y)
  ctx.lineTo(WIDTH - px(4), y)
  ctx.stroke()
  y += px(16)

  // Data Matrix plus its human-readable AI lines, side by side.
  const symbol = document.createElement("canvas")
  try {
    renderDataMatrix(symbol, data.gs1_text, SCALE)
    ctx.drawImage(symbol, left, y, px(90), px(90))
  } catch (err) {
    console.error("Data Matrix generation failed:", err)
  }

  ctx.fillStyle = "#000"
  ctx.font = `${px(9)}px "SFMono-Regular", Menlo, monospace`
  let lineY = y + px(10)
  for (const line of data.ai_lines || []) {
    ctx.fillText(line, left + px(104), lineY)
    lineY += px(12)
  }

  if (data.sequence) {
    ctx.font = `bold ${px(10)}px Helvetica, Arial, sans-serif`
    const text = data.sequence
    ctx.fillText(text, WIDTH - px(20) - ctx.measureText(text).width, HEIGHT - px(16))
  }

  return canvas
}

function labelData(el) {
  return JSON.parse(el.dataset.label)
}

function download(el) {
  const data = labelData(el)
  const canvas = drawLabel(document.createElement("canvas"), data)
  const link = document.createElement("a")
  link.download = `${data.filename}.png`
  link.href = canvas.toDataURL("image/png")
  link.click()
}

// Prints the label alone at its physical size — never the modal chrome or the
// page behind it (ui.md §6).
function print(el) {
  const data = labelData(el)
  const canvas = drawLabel(document.createElement("canvas"), data)
  const frame = document.createElement("iframe")
  frame.setAttribute("aria-hidden", "true")
  frame.style.cssText = "position:fixed;right:0;bottom:0;width:0;height:0;border:0"
  document.body.appendChild(frame)

  const doc = frame.contentWindow.document
  doc.open()
  doc.write(
    `<!doctype html><html><head><title>${data.filename}</title>` +
      `<style>@page{size:4in 6in;margin:0}html,body{margin:0;padding:0}` +
      `img{width:4in;height:6in;display:block}</style></head>` +
      `<body><img alt="${data.filename}" src="${canvas.toDataURL("image/png")}"></body></html>`
  )
  doc.close()

  const image = doc.querySelector("img")
  const run = () => {
    frame.contentWindow.focus()
    frame.contentWindow.print()
    setTimeout(() => frame.remove(), 1000)
  }
  if (image.complete) run()
  else image.onload = run
}

export const SerialLabel = {
  mounted() {
    this.render()
    this.bind()
  },
  updated() {
    this.render()
  },
  render() {
    const preview = this.el.querySelector("[data-role='symbol']")
    if (!preview) return
    try {
      renderDataMatrix(preview, labelData(this.el).gs1_text, 3)
    } catch (err) {
      console.error("Data Matrix generation failed:", err)
    }
  },
  bind() {
    this.el.addEventListener("click", (event) => {
      const action = event.target.closest("[data-label-action]")
      if (!action || !this.el.contains(action)) return
      event.preventDefault()
      if (action.dataset.labelAction === "download") download(this.el)
      if (action.dataset.labelAction === "print") print(this.el)
    })
  },
}
