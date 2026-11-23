// Prints one or more SSCC labels by rasterising each already-rendered
// label div with html2canvas, then printing the resulting images from a
// hidden iframe — ported from gs1_admin's label-printing approach. This
// sidesteps any stylesheet/CSS problem entirely (no stylesheet is needed,
// the print job is just images) and leaves the live page's own DOM and
// LiveView socket completely untouched.
async function printLabelDivs(divs, size) {
  if (!window.html2canvas) {
    console.error("html2canvas is not loaded; cannot print labels")
    return
  }

  const images = []

  for (const div of divs) {
    const canvas = await window.html2canvas(div, {scale: 3, useCORS: true, allowTaint: true})
    images.push(canvas.toDataURL("image/png"))
  }

  if (images.length === 0) return

  return printImagesInIframe(images, size)
}

// size is "WIDTH HEIGHT" in CSS units, e.g. "50mm 25mm"; shipper labels default to 4in x 6in.
function printImagesInIframe(images, size = "4in 6in") {
  const [width, height] = size.split(" ")
  const iframe = document.createElement("iframe")
  iframe.style.position = "fixed"
  iframe.style.right = "0"
  iframe.style.bottom = "0"
  iframe.style.width = "1px"
  iframe.style.height = "1px"
  iframe.style.border = "0"
  iframe.setAttribute("aria-hidden", "true")

  const pages = images
    .map(
      (src, i) =>
        `<div class="page"${i > 0 ? ' style="page-break-before: always;"' : ""}><img src="${src}" /></div>`,
    )
    .join("")

  const html =
    "<!DOCTYPE html><html><head><title>Print</title><style>" +
    `@page { size: ${width} ${height}; margin: 0; } ` +
    "html, body { margin: 0; padding: 0; } " +
    `.page { width: ${width}; height: ${height}; page-break-after: always; overflow: hidden; display: flex; align-items: center; justify-content: center; } ` +
    ".page:last-child { page-break-after: auto; } " +
    "img { display: block; max-width: 100%; max-height: 100%; width: auto; height: auto; object-fit: contain; }" +
    "</style></head><body>" +
    pages +
    "</body></html>"

  return new Promise((resolve, reject) => {
    const cleanup = () => iframe.remove()

    iframe.onload = async () => {
      try {
        const printWindow = iframe.contentWindow
        const doc = printWindow.document
        await Promise.all(Array.from(doc.images, (image) => image.decode()))
        if (doc.fonts) await doc.fonts.ready
        printWindow.addEventListener("afterprint", cleanup, {once: true})
        printWindow.focus()
        printWindow.print()
        setTimeout(cleanup, 60_000)
        resolve()
      } catch (error) {
        cleanup()
        reject(error)
      }
    }

    iframe.srcdoc = html
    document.body.appendChild(iframe)
  })
}

export const LabelPrint = {
  mounted() {
    this.handleClick = async () => {
      const selector = this.el.dataset.printTarget
      const div = selector && document.querySelector(selector)
      if (!div) return

      try {
        await printLabelDivs([div])
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
        await printLabelDivs(divs, this.el.dataset.labelSize)
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
