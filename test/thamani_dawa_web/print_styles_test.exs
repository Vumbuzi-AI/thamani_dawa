defmodule ThamaniDawaWeb.PrintStylesTest do
  use ExUnit.Case, async: true

  @app_css Path.expand("../../assets/css/app.css", __DIR__)
  @receipt_hook Path.expand("../../assets/js/hooks/quick_sale_receipt_print.js", __DIR__)
  @label_hook Path.expand("../../assets/js/hooks/label_print.js", __DIR__)
  @shipper_label Path.expand(
                   "../../lib/thamani_dawa_web/live/manufacturer_sscc_live/label.ex",
                   __DIR__
                 )
  @label_download_hook Path.expand("../../assets/js/hooks/label_svg_download.js", __DIR__)
  @datamatrix_hook Path.expand("../../assets/js/hooks/datamatrix.js", __DIR__)

  test "shared print foundation uses white paper and allows documents to paginate" do
    css = File.read!(@app_css)

    assert css =~ "background-color: var(--print-page) !important;"
    assert css =~ ~r/\.printable-lab-report\s*\{\s*position: static !important;/s
    assert css =~ ~r/\.printable-invoice\s*\{\s*position: static !important;/s

    refute css =~
             ~r/\.printable-(?:lab-report|invoice)\s*\{[^}]*position: fixed !important;/s

    assert css =~ ~r/@page sscc-label\s*\{\s*size: 4in 6in;\s*margin: 0;/s
    assert css =~ ~r/\.printable-sscc-label:last-child\s*\{[^}]*break-after: auto;/s
    assert css =~ "#shipper-label-modal .printable-sscc-label,"
    assert css =~ "#shipper-label-modal .td-modal-scrim,"
  end

  test "isolated receipt print document uses a white print canvas" do
    hook = File.read!(@receipt_hook)

    assert hook =~ ~r/@media print\s*\{[^}]*html, body\s*\{[^}]*background: #fff;/s
  end

  test "shipper label printing supports full-label previews and scopes bulk printing" do
    hook = File.read!(@label_hook)
    shipper_label = File.read!(@shipper_label)

    assert hook =~ ~s|label.querySelector("[data-print-content]")|
    assert hook =~ "img { display: block; max-width: 100%; } "
    assert hook =~ "@page { margin: 10mm; }"
    assert hook =~ "contentSizedPage"
    assert hook =~ "resolvedSize?.endsWith(\" auto\")"
    assert hook =~ "this.el.dataset.printContainer"
    assert hook =~ ~s(this.el.dataset.printTarget || ".printable-sscc-label")
    assert hook =~ "root.querySelectorAll(selector)"
    assert shipper_label =~ ~s(data-label-size="100mm auto")
    refute shipper_label =~ "data-print-content"

    download_hook = File.read!(@label_download_hook)
    assert download_hook =~ "this.el.dataset.downloadContainer"
    assert download_hook =~ ~s|root.querySelectorAll('[data-role="download-label-svg"]')|
  end

  test "shipper DataMatrix uses the raw GS-delimited payload without AI parsing" do
    hook = File.read!(@datamatrix_hook)

    assert hook =~ "this.el.dataset.barcode"
    assert hook =~ ~s|bcid: rawPayload ? "datamatrix" : gs1Text ? "gs1datamatrix" : "datamatrix"|
    assert hook =~ "backgroundcolor: rawPayload ? \"f2f4f8\" : \"ffffff\""
  end
end
