import bwipjs from "../../vendor/bwip-js"

// Ported from gs1_admin's label SVG builder (buildLabelSvg/svgText/svgLine/
// wrapLabelText/measureLabelText), so the exported file matches its layout
// algorithm exactly: a bordered card with a From/To address block, rows of
// [caption, value] pairs with real text-measurement-based wrapping, and a
// DataMatrix with its AI lines beside it. The DataMatrix itself is drawn by
// bwip-js (the GS1 DataMatrix library already vendored in this app) rather
// than gs1_admin's own `DATAMatrix()` function, since only bwip-js is
// available here — everything else is the same geometry.
const LABEL_FONT = "Arial, Helvetica, sans-serif"
const labelMeasureCtx = document.createElement("canvas").getContext("2d")

function measureLabelText(text, size, bold = false) {
  labelMeasureCtx.font = `${bold ? "bold " : ""}${size}px ${LABEL_FONT}`
  return labelMeasureCtx.measureText(text).width
}

function escapeSvgText(value) {
  return String(value ?? "")
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

function wrapLabelText(text, size, bold, maxWidth) {
  const lines = []

  for (const paragraph of String(text ?? "").split(/\r?\n/)) {
    let line = ""

    for (const word of paragraph.split(/\s+/).filter(Boolean)) {
      const candidate = line ? `${line} ${word}` : word
      if (measureLabelText(candidate, size, bold) <= maxWidth) {
        line = candidate
        continue
      }
      if (line) lines.push(line)
      line = ""

      for (const char of word) {
        if (line && measureLabelText(line + char, size, bold) > maxWidth) {
          lines.push(line)
          line = ""
        }
        line += char
      }
    }

    if (line) lines.push(line)
  }

  return lines
}

function svgText(x, y, text, size, bold = false) {
  return (
    `<text x="${x}" y="${y}" font-family="${LABEL_FONT}" font-size="${size}"` +
    `${bold ? ' font-weight="bold"' : ""} fill="#000">${escapeSvgText(text)}</text>`
  )
}

function svgLine(x1, y1, x2, y2) {
  return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="#000" stroke-width="2"/>`
}

function wrapLabelSvg(width, height, title, parts) {
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" ` +
    `viewBox="0 0 ${width} ${height}" role="img" aria-label="${escapeSvgText(title)}">` +
    `<rect width="100%" height="100%" fill="#fff"/>` +
    parts.join("") +
    `</svg>`
  )
}

function dataMatrixSvgMarkup(payload, x, y, size, bw) {
  const barcodeSvg = bw.toSVG({bcid: "gs1datamatrix", text: payload, parse: true, scale: 3})
  const inner = barcodeSvg.replace(/^[\s\S]*?<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "")
  const viewBoxMatch = barcodeSvg.match(/viewBox="([^"]+)"/)
  const viewBox = viewBoxMatch ? viewBoxMatch[1] : `0 0 ${size} ${size}`

  return (
    `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${viewBox}" ` +
    `preserveAspectRatio="xMidYMid meet">${inner}</svg>`
  )
}

export function buildLabelSvg(label, title, bw) {
  const hri = label.hri || []
  const rows = label.rows || []
  const hasAddresses = label.from_address != null || label.to_address != null
  const parts = []
  const dmSize = 120

  const width = 400
  const left = 10
  const right = width - 10
  let y = 0

  if (hasAddresses) {
    const colWidth = width / 2
    const columns = [
      ["From Address", label.from_address],
      ["To Address", label.to_address],
    ].map(([heading, address]) => [heading, wrapLabelText(address, 16, false, colWidth - 16)])

    columns.forEach(([heading, lines], col) => {
      const x = col * colWidth + 8
      parts.push(svgText(x, 26, heading, 16, true))
      lines.forEach((line, i) => parts.push(svgText(x, 26 + (i + 1) * 24, line, 16)))
    })

    y = 8 + 24 * (1 + Math.max(...columns.map(([, lines]) => lines.length))) + 8
    parts.push(svgLine(colWidth, 0, colWidth, y))
    parts.push(svgLine(left, y, right, y))
  }

  y += 8
  const colWidth = (right - left) / 2

  rows.forEach((row, rowIndex) => {
    let rowHeight = 0

    row.forEach(([caption, value], col) => {
      const valueSize = caption === "SSCC" ? 16 : 18
      const lines =
        caption === "SSCC" ? [String(value ?? "")] : wrapLabelText(value, valueSize, true, colWidth - 6)
      const cellWidth = Math.max(
        measureLabelText(caption, 12),
        ...lines.map((line) => measureLabelText(line, valueSize, true)),
      )
      const x = col === 0 ? left : Math.max(left + colWidth + 6, right - cellWidth)

      parts.push(svgText(x, y + 12, caption, 12))
      lines.forEach((line, i) => parts.push(svgText(x, y + 37 + i * 24, line, valueSize, true)))
      rowHeight = Math.max(rowHeight, 18 + 24 * Math.max(lines.length, 1))
    })

    y += rowHeight
    if (rowIndex === rows.length - 1) {
      y += 8
      parts.push(svgLine(left, y, right, y))
    }
    y += 12
  })

  const dmX = left + 35
  const textX = dmX + dmSize + 15
  parts.push(dataMatrixSvgMarkup(label.payload, dmX, y, dmSize, bw))
  hri.forEach((line, i) => parts.push(svgText(textX, y + 22 + i * 15.6, line, 12)))
  y += Math.max(dmSize, 10 + hri.length * 15.6) + 10

  const height = Math.ceil(y + 1)
  parts.unshift(`<rect x="1" y="1" width="${width - 2}" height="${height - 2}" fill="none" stroke="#000" stroke-width="2"/>`)

  return wrapLabelSvg(width, height, title, parts)
}

function labelFromDataset(d) {
  return {
    payload: d.gs1Text,
    hri: d.gs1Text.match(/\([0-9]+\)[^(]*/g) || [],
    from_address: [d.fromCompany, d.fromAddress].filter(Boolean).join("\n"),
    to_address: [d.toCompany, d.toAddress, d.toPoBox].filter(Boolean).join("\n"),
    rows: [
      [["SSCC", d.sscc], ["QUANTITY", d.quantity]],
      [["CONTENT", d.gtin], ["EXPIRY", d.expiry]],
      [["BATCH/LOT", d.batch], ["PROD DATE", d.production]],
      [["MATERIAL DESCRIPTION", d.materialDescription], ["ORDER NUMBER", d.orderNumber]],
    ],
  }
}

export function downloadLabelSvg(d, bw) {
  if (!d.gs1Text || (!d.sscc && !d.serial)) return

  let svg
  let filename

  try {
    if (d.serial) {
      const barcodeSvg = bw.toSVG({bcid: "gs1datamatrix", text: d.gs1Text, parse: true, scale: 4})
      const inner = barcodeSvg.replace(/^[\s\S]*?<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "")
      const viewBox = barcodeSvg.match(/viewBox="([^"]+)"/)?.[1] || "0 0 200 200"
      const title = escapeSvgText(`GTIN ${d.gtin} · Batch ${d.batch} · Serial ${d.serial}`)
      svg = `<svg xmlns="http://www.w3.org/2000/svg" width="360" height="430" viewBox="0 0 360 430"><rect width="360" height="430" rx="20" fill="#fff" stroke="#000" stroke-width="2"/><svg x="55" y="35" width="250" height="250" viewBox="${viewBox}" preserveAspectRatio="xMidYMid meet">${inner}</svg><text x="180" y="325" text-anchor="middle" font-family="${LABEL_FONT}" font-size="14" fill="#000">${title}</text><text x="180" y="360" text-anchor="middle" font-family="${LABEL_FONT}" font-size="12" fill="#000">${escapeSvgText(d.gs1Text)}</text></svg>`
      filename = `serial-label-${d.serial}.svg`
    } else {
      svg = buildLabelSvg(labelFromDataset(d), `SSCC ${d.sscc}`, bw)
      filename = `sscc-label-${d.sscc}.svg`
    }
  } catch (error) {
    console.error("GS1 DataMatrix SVG generation failed:", error)
    return
  }

  const blob = new Blob([svg], {type: "image/svg+xml;charset=utf-8"})
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

export const LabelSvgDownload = {
  mounted() {
    this.handleClick = () => downloadLabelSvg(this.el.dataset, window.bwipjs || bwipjs)
    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  },
}

// Downloads every label on the page as a separate SVG file, one per
// shipper. Browsers throttle rapid-fire downloads, so each is staggered
// slightly rather than fired in the same tick.
export const DownloadAllLabelsSvg = {
  mounted() {
    this.handleClick = () => this.downloadAll()
    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  },

  downloadAll() {
    const bw = window.bwipjs || bwipjs
    const buttons = document.querySelectorAll('[data-role="download-label-svg"]')

    buttons.forEach((button, index) => {
      setTimeout(() => downloadLabelSvg(button.dataset, bw), index * 300)
    })
  },
}
