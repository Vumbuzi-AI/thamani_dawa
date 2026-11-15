defmodule ThamaniDawa.Products.ImporterTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Products.Importer

  describe "auto_map_columns/1" do
    test "maps decorated headings and conservative spreadsheet synonyms" do
      headers = [
        "Medicine / Product",
        "Trade label",
        "Barcode (GTIN)",
        "Retail price (KES)",
        "Selling unit",
        "Product group",
        "Made by",
        "Reorder threshold",
        "OTC?",
        "Controlled drug?"
      ]

      assert Importer.auto_map_columns(headers) == %{
               generic_name: "Medicine / Product",
               brand_name: "Trade label",
               gtin: "Barcode (GTIN)",
               price: "Retail price (KES)",
               uom: "Selling unit",
               category: "Product group",
               manufacturer: "Made by",
               reorder_level: "Reorder threshold",
               is_otc: "OTC?",
               is_dangerous_drug: "Controlled drug?"
             }
    end

    test "prefers an exact heading over a decorated alternative" do
      mapping = Importer.auto_map_columns(["Price", "Retail price (KES)"])

      assert mapping.price == "Price"
    end

    test "leaves multiple equally strong candidates for review" do
      mapping = Importer.auto_map_columns(["Retail price", "Selling price"])

      assert is_nil(mapping.price)
    end

    test "does not match partial words" do
      mapping = Importer.auto_map_columns(["Surprise", "Community"])

      assert is_nil(mapping.price)
      assert is_nil(mapping.uom)
    end
  end
end
