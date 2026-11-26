import bwipjs from "../../vendor/bwip-js"

export const DataMatrix = {
  mounted() {
    this.renderBarcode();
  },
  updated() {
    this.renderBarcode();
  },
  renderBarcode() {
    const rawPayload =
      this.el.dataset.barcode || this.el.getAttribute("data-barcode");
    const gs1Text =
      this.el.dataset.gs1Text || this.el.getAttribute("data-gs1-text");
    const plainText =
      this.el.dataset.text || this.el.getAttribute("data-text");
    const text = rawPayload || gs1Text || plainText;
    if (!text) return;

    try {
      const bw = window.bwipjs || bwipjs;
      if (bw && typeof bw.toCanvas === "function") {
        bw.toCanvas(this.el, {
          // gs1_admin ships a raw GS-delimited element string (see its
          // DataMatrix helper). Plain `datamatrix` encodes it verbatim without
          // applying GS1 AI rules that reject the (01)+(37) shipper payload.
          bcid: rawPayload ? "datamatrix" : gs1Text ? "gs1datamatrix" : "datamatrix",
          text: text,
          parse: !rawPayload && !!gs1Text,
          scale: 3,
          includetext: false,
          barcolor: "000000",
          backgroundcolor: rawPayload ? "f2f4f8" : "ffffff",
        });
      }
    } catch (err) {
      console.error("DataMatrix barcode generation failed:", err);
    }
  },
};
