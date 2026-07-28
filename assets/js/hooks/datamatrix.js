import bwipjs from "../../vendor/bwip-js"

export const DataMatrix = {
  mounted() {
    this.renderBarcode();
  },
  updated() {
    this.renderBarcode();
  },
  renderBarcode() {
    const text =
      this.el.dataset.gs1Text || this.el.getAttribute("data-gs1-text");
    if (!text) return;

    try {
      const bw = window.bwipjs || bwipjs;
      if (bw && typeof bw.toCanvas === "function") {
        bw.toCanvas(this.el, {
          bcid: "gs1datamatrix",
          text: text,
          scale: 3,
          includetext: false,
        });
      }
    } catch (err) {
      console.error("DataMatrix barcode generation failed:", err);
    }
  },
};
