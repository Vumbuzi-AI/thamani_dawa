import bwipjs from "../../vendor/bwip-js"

export const DataMatrix = {
  mounted() {
    this.renderBarcode();
  },
  updated() {
    this.renderBarcode();
  },
  renderBarcode() {
    const gs1Text =
      this.el.dataset.gs1Text || this.el.getAttribute("data-gs1-text");
    const plainText =
      this.el.dataset.text || this.el.getAttribute("data-text");
    const text = gs1Text || plainText;
    if (!text) return;

    try {
      const bw = window.bwipjs || bwipjs;
      if (bw && typeof bw.toCanvas === "function") {
        bw.toCanvas(this.el, {
          bcid: gs1Text ? "gs1datamatrix" : "datamatrix",
          text: text,
          parse: !!gs1Text,
          scale: 3,
          includetext: false,
        });
      }
    } catch (err) {
      console.error("DataMatrix barcode generation failed:", err);
    }
  },
};
