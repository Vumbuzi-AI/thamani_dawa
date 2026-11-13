import bwipjs from "../../vendor/bwip-js"

export const SsccBarcode = {
  mounted() {
    this.renderBarcode()
  },

  updated() {
    this.renderBarcode()
  },

  renderBarcode() {
    const sscc = this.el.dataset.sscc
    if (!sscc) return

    try {
      const bw = window.bwipjs || bwipjs

      if (bw && typeof bw.toCanvas === "function") {
        bw.toCanvas(this.el, {
          bcid: "sscc18",
          text: `(00)${sscc}`,
          scale: 3,
          height: 18,
          includetext: false,
          paddingwidth: 8,
          paddingheight: 2,
        })
      }
    } catch (error) {
      console.error("SSCC barcode generation failed:", error)
    }
  },
}
