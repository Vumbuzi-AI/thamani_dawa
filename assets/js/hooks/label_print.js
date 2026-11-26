// Prints one or more SSCC labels by rasterising each already-rendered
// label with html2canvas, then printing the resulting images from a hidden
// iframe — ported from gs1_admin's label-printing approach. This sidesteps
// any stylesheet/CSS problem entirely and leaves the page's DOM untouched.
async function printLabelDivs(divs, size, copies = 1) {
  if (!window.html2canvas) {
    console.error("html2canvas is not loaded; cannot print labels")
    return
  }

  const images = []
  let resolvedSize = size

  for (const div of divs) {
    const canvas = await window.html2canvas(labelPrintContent(div), {
      scale: 3,
      useCORS: true,
      allowTaint: true,
    })
    if (resolvedSize?.endsWith(" auto")) resolvedSize = contentSizedPage(resolvedSize, canvas)
    const image = canvas.toDataURL("image/png")
    for (let copy = 0; copy < copies; copy += 1) images.push(image)
  }

  if (images.length === 0) return

  return printImagesInIframe(images, resolvedSize)
}

// Keep the requested physical width while deriving the page height from the
// rasterised label. This makes the printed sheet hug variable-height shipper
// labels instead of centring them inside a fixed 100 × 150 mm page.
function contentSizedPage(size, canvas) {
  const [width] = size.split(" ")
  const match = width.match(/^([0-9]*\.?[0-9]+)(mm|cm|in)$/)
  if (!match || canvas.width <= 0) return "auto"

  const height = Number.parseFloat(match[1]) * (canvas.height / canvas.width)
  return `${width} ${height.toFixed(2)}${match[2]}`
}

// A label may explicitly mark a printable subsection. Without that marker,
// rasterise the complete preview so the printed label matches what the user saw.
function labelPrintContent(label) {
  return label.querySelector("[data-print-content]") || label
}

// size is "WIDTH HEIGHT" in CSS units, e.g. "50mm 25mm"; omitted for the
// shipper label so the browser's normal 10mm page margin applies.
function printImagesInIframe(images, size = "auto") {
  const fixedSize = size && size !== "auto"
  const [width, height] = fixedSize ? size.split(" ") : [null, null]
  const pages = images
    .map(
      (src, i) =>
        `<div class="page"${i > 0 ? ' style="page-break-before: always;"' : ""}><img src="${src}" /></div>`,
    )
    .join("")

  const html =
    "<!DOCTYPE html><html><head><title>Print</title><style>" +
    "html, body { margin: 0; padding: 0; } " +
    ".page { display: flex; justify-content: center; align-items: flex-start; } " +
    "img { display: block; max-width: 100%; } " +
    (fixedSize
      ? `@page { size: ${width} ${height}; margin: 0; } ` +
        `.page { width: ${width}; height: ${height}; overflow: hidden; align-items: center; } ` +
        ".page img { width: 100%; height: 100%; object-fit: contain; }"
      : "@page { margin: 10mm; }") +
    "</style></head><body>" +
    pages +
    "</body></html>"

  return printHtmlInIframe(hiddenPrintFrame(), html)
}

async function printHtmlInIframe(iframe, html) {
  const cleanup = () => iframe.remove()
  document.body.appendChild(iframe)

  try {
    const printWindow = iframe.contentWindow
    const doc = printWindow.document
    doc.open()
    doc.write(html)
    doc.close()
    await waitForStyles(doc)
    await Promise.all(Array.from(doc.images, (image) => image.decode().catch(() => {})))
    if (doc.fonts) await doc.fonts.ready
    printWindow.addEventListener("afterprint", cleanup, {once: true})
    printWindow.focus()
    printWindow.print()
    setTimeout(cleanup, 60_000)
  } catch (error) {
    cleanup()
    throw error
  }
}

function waitForStyles(doc) {
  const links = Array.from(doc.querySelectorAll('link[rel="stylesheet"]'))
  const loaded = links.map(
    (link) =>
      new Promise((resolve) => {
        if (link.sheet) return resolve()
        link.addEventListener("load", resolve, {once: true})
        link.addEventListener("error", resolve, {once: true})
      }),
  )
  return Promise.race([Promise.all(loaded), new Promise((resolve) => setTimeout(resolve, 5000))])
}

function hiddenPrintFrame() {
  const iframe = document.createElement("iframe")
  iframe.style.position = "fixed"
  iframe.style.right = "0"
  iframe.style.bottom = "0"
  iframe.style.width = "1px"
  iframe.style.height = "1px"
  iframe.style.border = "0"
  iframe.setAttribute("aria-hidden", "true")
  return iframe
}

// Prints the labels as live markup: canvases become images, and the page's own
// stylesheets style the clones, so nothing is rasterised and no helper script is needed.
function printClonedDivs(divs, size = "50mm 25mm") {
  const [width, height] = size.split(" ")

  const pages = divs
    .map((div) => {
      const clone = div.cloneNode(true)
      const sources = div.querySelectorAll("canvas")

      clone.querySelectorAll("canvas").forEach((canvas, index) => {
        const img = document.createElement("img")
        img.src = sources[index].toDataURL("image/png")
        img.className = canvas.className
        img.style.imageRendering = "pixelated"
        canvas.replaceWith(img)
      })

      clone.removeAttribute("id")
      clone.querySelectorAll("[id]").forEach((node) => node.removeAttribute("id"))
      return `<div class="page">${clone.outerHTML}</div>`
    })
    .join("")

  const styles = Array.from(document.querySelectorAll('link[rel="stylesheet"], style'))
    .map((node) =>
      node.tagName === "LINK"
        ? `<link rel="stylesheet" href="${node.href}">`
        : `<style>${node.textContent}</style>`,
    )
    .join("")

  const html =
    '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Print</title>' +
    styles +
    "<style>" +
    `@page { size: ${width} ${height}; margin: 0; } ` +
    "html, body { margin: 0; padding: 0; background: #fff !important; } " +
    `.page { width: ${width}; height: ${height}; overflow: hidden; break-after: page; } ` +
    ".page:last-child { break-after: auto; } " +
    "html body, html body * { visibility: visible !important; } " +
    ".page > * { border: 0 !important; border-radius: 0 !important; }" +
    "</style></head><body>" +
    pages +
    "</body></html>"

  return printHtmlInIframe(hiddenPrintFrame(), html)
}

export const LabelPrint = {
  mounted() {
    this.handleClick = async () => {
      const selector = this.el.dataset.printTarget
      const div = selector && document.querySelector(selector)
      if (!div) return

      const copiesInput = this.el.dataset.copiesTarget
        ? document.querySelector(this.el.dataset.copiesTarget)
        : null
      const requestedCopies = Number.parseInt(copiesInput?.value || "1", 10)
      const copies = Number.isFinite(requestedCopies) ? Math.min(Math.max(requestedCopies, 1), 100) : 1

      try {
        await printLabelDivs([div], this.el.dataset.labelSize || "auto", copies)
      } catch (error) {
        console.error("Could not print label", error)
        window.alert("Could not prepare the label for printing. Please try again.")
      }
    }

    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  },
}

export const PrintAllLabels = {
  mounted() {
    this.handleClick = async () => {
      const container = this.el.dataset.printContainer
      const root = container ? document.querySelector(container) : document
      const selector = this.el.dataset.printTarget || ".printable-sscc-label"
      const divs = root ? Array.from(root.querySelectorAll(selector)) : []
      if (divs.length === 0) return

      try {
        if (this.el.dataset.printMode === "clone") {
          await printClonedDivs(divs, this.el.dataset.labelSize)
        } else {
          await printLabelDivs(divs, this.el.dataset.labelSize)
        }
      } catch (error) {
        console.error("Could not print labels", error)
        window.alert("Could not prepare the labels for printing. Please try again.")
      }
    }

    this.el.addEventListener("click", this.handleClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  },
}
