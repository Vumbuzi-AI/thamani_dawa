const GTIN_LENGTHS = new Set([8, 12, 13, 14])

export const ConditionalBatchField = {
  mounted() {
    this.barcodeInput = this.el.querySelector('input[name="barcode"]')
    this.batchInput = this.el.querySelector('input[name="batch_no"]')
    this.batchField = this.el.querySelector("[data-batch-field]")

    if (!this.barcodeInput || !this.batchInput || !this.batchField) return

    this.updateBatchField = () => {
      const barcode = this.barcodeInput.value.trim()
      const isGtinOnly = /^\d+$/.test(barcode) && GTIN_LENGTHS.has(barcode.length)

      this.batchField.classList.toggle("hidden", !isGtinOnly)
      this.batchInput.required = isGtinOnly
      if (!isGtinOnly) this.batchInput.value = ""
    }

    this.barcodeInput.addEventListener("input", this.updateBatchField)
    this.updateBatchField()
  },

  destroyed() {
    if (this.barcodeInput && this.updateBatchField) {
      this.barcodeInput.removeEventListener("input", this.updateBatchField)
    }
  },
}
