defmodule ThamaniDawaWeb.PrintStylesTest do
  use ExUnit.Case, async: true

  @app_css Path.expand("../../assets/css/app.css", __DIR__)
  @receipt_hook Path.expand("../../assets/js/hooks/quick_sale_receipt_print.js", __DIR__)

  test "shared print foundation uses white paper and allows documents to paginate" do
    css = File.read!(@app_css)

    assert css =~ "background-color: var(--print-page) !important;"
    assert css =~ ~r/\.printable-lab-report\s*\{\s*position: static !important;/s
    assert css =~ ~r/\.printable-invoice\s*\{\s*position: static !important;/s

    refute css =~
             ~r/\.printable-(?:lab-report|invoice)\s*\{[^}]*position: fixed !important;/s

    assert css =~ ~r/@page sscc-label\s*\{\s*size: 4in 6in;\s*margin: 0;/s
    assert css =~ ~r/\.printable-sscc-label:last-child\s*\{[^}]*break-after: auto;/s
  end

  test "isolated receipt print document uses a white print canvas" do
    hook = File.read!(@receipt_hook)

    assert hook =~ ~r/@media print\s*\{[^}]*html, body\s*\{[^}]*background: #fff;/s
  end
end
