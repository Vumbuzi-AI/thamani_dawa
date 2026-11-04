const receiptStyles = `
  @page { size: A6 portrait; margin: 6mm; }
  @page thermal { size: 80mm auto; margin: 4mm; }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; color: #172414; font-family: Arial, Helvetica, sans-serif; }
  body { background: #f2f3ef; font-size: 10px; line-height: 1.35; }
  .receipt { page: thermal; width: 72mm; max-width: 100%; margin: 14px auto; padding: 4mm; background: #fff; }
  .receipt-header { text-align: center; }
  .receipt-logo { display: block; width: 19mm; height: 19mm; margin: 0 auto 2mm; object-fit: contain; }
  .receipt-site { margin: 0; font-size: 14px; font-weight: 700; }
  .receipt-title { margin: 2mm 0 3mm; font-size: 16px; font-weight: 700; text-transform: uppercase; }
  .receipt-meta { padding: 2mm 0; border-top: 1px dashed #62685e; border-bottom: 1px dashed #62685e; text-align: left; }
  .receipt-meta div, .receipt-payment div { display: flex; justify-content: space-between; gap: 2mm; margin: 1mm 0; }
  .receipt-meta span, .receipt-payment span { color: #4e554b; }
  .receipt-meta strong, .receipt-payment strong { text-align: right; overflow-wrap: anywhere; }
  .receipt-table { width: 100%; margin: 3mm 0; border-collapse: collapse; table-layout: fixed; font-size: 8px; }
  .receipt-table th { padding: 1.5mm 0; border-bottom: 1px dashed #62685e; text-align: left; font-size: 7px; text-transform: uppercase; }
  .receipt-table td { padding: 1.5mm 0; vertical-align: top; overflow-wrap: anywhere; }
  .receipt-table th:first-child, .receipt-table td:first-child { width: 8%; }
  .receipt-table th:nth-child(2), .receipt-table td:nth-child(2) { width: 36%; }
  .receipt-table th:nth-child(3), .receipt-table td:nth-child(3) { width: 25%; text-align: right; }
  .receipt-table th:nth-child(4), .receipt-table td:nth-child(4) { width: 31%; text-align: right; }
  .receipt-medicine strong, .receipt-medicine small { display: block; }
  .receipt-medicine small { margin-top: .5mm; color: #62685e; }
  .receipt-payment { padding-top: 2mm; border-top: 1px dashed #62685e; }
  .receipt-payment .receipt-total { padding-bottom: 1.5mm; margin-bottom: 1.5mm; border-bottom: 1px dashed #62685e; font-size: 13px; }
  .receipt-status-value { display: inline-block; padding: 1mm 3mm; border: 1px solid #8cdcb2; border-radius: 999px; color: #087443; background: #ecfdf3; font-size: 8px; font-weight: 700; }
  .receipt-status-value[data-paid="false"] { border-color: #f0a3a3; color: #a82020; background: #fff1f1; }
  .receipt-thanks { margin: 4mm 0 2mm; text-align: center; font-weight: 700; }
  .receipt-powered { padding-top: 2mm; border-top: 1px dashed #b5b9b0; color: #62685e; text-align: center; font-size: 8px; }
  @media print {
    html, body { width: 100%; background: #fff; }
    .receipt { margin: 0 auto; padding: 0; break-inside: avoid; page-break-inside: avoid; }
  }
`

export const QuickSaleReceiptPrint = {
  mounted() {
    this.handlePrint = () => this.printReceipt()
    this.el.addEventListener("click", this.handlePrint)
  },

  destroyed() {
    this.el.removeEventListener("click", this.handlePrint)
  },

  printReceipt() {
    const selector = this.el.dataset.receiptTarget
    const receipt = selector && document.querySelector(selector)

    if (!receipt) return

    const printWindow = window.open("", "_blank", "popup=yes,width=420,height=720")

    if (!printWindow) {
      window.alert("Allow pop-ups to print this receipt.")
      return
    }

    const printDocument = printWindow.document
    printDocument.open()

    let printStarted = false
    const printWhenReady = () => {
      if (printStarted) return
      printStarted = true
      printWindow.focus()
      printWindow.print()
    }

    printWindow.addEventListener("load", printWhenReady, {once: true})
    printWindow.addEventListener("afterprint", () => printWindow.close(), {once: true})

    printDocument.write(`<!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Sale Receipt</title>
          <style>${receiptStyles}</style>
        </head>
        <body><main class="receipt">${receipt.innerHTML}</main></body>
      </html>`)
    printDocument.close()

    if (printDocument.readyState === "complete") {
      printWindow.requestAnimationFrame(printWhenReady)
    }
  }
}
