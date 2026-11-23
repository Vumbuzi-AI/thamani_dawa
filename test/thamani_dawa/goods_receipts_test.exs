defmodule ThamaniDawa.GoodsReceiptsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.Batches
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.SitesFixtures
  alias ThamaniDawa.SuppliersFixtures

  setup do
    organization = OrganizationsFixtures.organization_fixture()
    user = AccountsFixtures.user_fixture(%{organization_id: organization.id})

    warehouse =
      SitesFixtures.site_fixture(%{organization_id: organization.id, activities: [:distribution]})

    supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization.id})
    product = ProductsFixtures.product_fixture(%{organization_id: organization.id, uom: "U2"})

    %{
      organization: organization,
      user: user,
      warehouse: warehouse,
      supplier: supplier,
      product: product
    }
  end

  test "posts multiple delivery items as one receipt and activates inventory", ctx do
    items = [
      delivery_item(ctx, "LOT-ONE", 20),
      delivery_item(ctx, "LOT-TWO", 10)
    ]

    assert {:ok, receipt} =
             GoodsReceipts.receive_delivery(
               ctx.organization.id,
               ctx.user.id,
               items,
               Ecto.UUID.generate()
             )

    assert receipt.number =~ ~r/^GRN-\d{6}$/
    assert length(receipt.items) == 2
    assert receipt.items |> Enum.map(& &1.batch_no) |> Enum.sort() == ["LOT-ONE", "LOT-TWO"]

    assert Enum.all?(
             receipt.items,
             &(&1.goods_receipt_id == receipt.id and &1.remaining_quantity == &1.quantity)
           )

    assert Enum.all?(receipt.items, &(not is_nil(&1.received_at)))
  end

  test "keeps a receiving draft's verified origin for the same user", ctx do
    draft = GoodsReceipts.ensure_receiving_draft(ctx.organization.id, ctx.user.id)

    GoodsReceipts.save_draft_origin!(draft, %{
      "gln" => "6109876543210",
      "company" => "Draft sender",
      "address" => "1 Market Street",
      "po_box" => nil,
      "site_id" => nil
    })

    restored = GoodsReceipts.get_receiving_draft(ctx.organization.id, ctx.user.id)

    assert restored.origin["gln"] == "6109876543210"
    assert restored.origin["company"] == "Draft sender"
  end

  test "replaces a single-document draft attachment without retaining the old file", ctx do
    source_path = Path.join(System.tmp_dir!(), "receiving-draft-#{Ecto.UUID.generate()}.pdf")
    File.write!(source_path, "document")

    draft = GoodsReceipts.ensure_receiving_draft(ctx.organization.id, ctx.user.id)

    first =
      GoodsReceipts.store_draft_attachment!(draft, :delivery_note, source_path, %{
        client_name: "first-delivery-note.pdf",
        client_type: "application/pdf",
        client_size: 8
      })

    replacement =
      GoodsReceipts.store_draft_attachment!(draft, :delivery_note, source_path, %{
        client_name: "replacement-delivery-note.pdf",
        client_type: "application/pdf",
        client_size: 8
      })

    restored = GoodsReceipts.get_receiving_draft(ctx.organization.id, ctx.user.id)

    assert [saved] = restored.attachments
    assert saved.id == replacement.id
    assert saved.filename == "replacement-delivery-note.pdf"
    refute File.exists?(first.path)
    assert File.exists?(replacement.path)

    GoodsReceipts.delete_receiving_draft!(draft)
    File.rm(source_path)
  end

  test "retrying a posting key returns the original receipt without duplicate stock", ctx do
    key = Ecto.UUID.generate()
    items = [delivery_item(ctx, "LOT-RETRY", 12)]

    assert {:ok, first} =
             GoodsReceipts.receive_delivery(ctx.organization.id, ctx.user.id, items, key)

    assert {:ok, second} =
             GoodsReceipts.receive_delivery(ctx.organization.id, ctx.user.id, items, key)

    assert first.id == second.id
    assert [%{id: batch_id}] = second.items
    assert Batches.get_batch!(ctx.organization.id, batch_id).quantity == 12
    assert length(GoodsReceipts.list_receipts(ctx.organization.id)) == 1
  end

  test "posts a delivery into organization stock when no site is supplied", ctx do
    item = delivery_item(ctx, "LOT-ORG-STOCK", 15)
    item = update_in(item.attrs, &Map.delete(&1, "site_id"))

    assert {:ok, receipt} =
             GoodsReceipts.receive_delivery(
               ctx.organization.id,
               ctx.user.id,
               [item],
               Ecto.UUID.generate()
             )

    assert [batch] = receipt.items
    assert is_nil(batch.site_id)
    assert batch.remaining_quantity == 15

    assert [org_batch] =
             Batches.list_undispatched_batches_for_product(ctx.organization.id, ctx.product.id)

    assert org_batch.id == batch.id
  end

  test "invalid delivery rolls back its receipt and all inventory", ctx do
    duplicate_batch_no = "LOT-ATOMIC"
    items = [delivery_item(ctx, duplicate_batch_no, 5), delivery_item(ctx, duplicate_batch_no, 5)]

    assert {:error, _changeset} =
             GoodsReceipts.receive_delivery(
               ctx.organization.id,
               ctx.user.id,
               items,
               Ecto.UUID.generate()
             )

    assert GoodsReceipts.list_receipts(ctx.organization.id) == []
    assert Batches.list_batches(ctx.organization.id) == []
  end

  test "snapshots a live-resolved origin onto the receipt header when given one", ctx do
    item = delivery_item(ctx, "LOT-ORIGIN", 8)
    item = update_in(item.attrs, &Map.delete(&1, "supplier_id"))

    origin = %{
      gln: "6109876543210",
      company: "Acme Pharma Imports",
      address: "Industrial Area, Nairobi",
      po_box: "P.O. Box 500-00100",
      site_id: nil
    }

    assert {:ok, receipt} =
             GoodsReceipts.receive_delivery(
               ctx.organization.id,
               ctx.user.id,
               [item],
               Ecto.UUID.generate(),
               origin
             )

    assert receipt.origin_gln == origin.gln
    assert receipt.origin_company == origin.company
    assert receipt.origin_address == origin.address
    assert receipt.origin_po_box == origin.po_box
    assert [batch] = receipt.items
    assert is_nil(batch.supplier_id)
  end

  test "groups a cased delivery into one logistic unit and leaves loose stock unlinked", ctx do
    product_b =
      ProductsFixtures.product_fixture(%{organization_id: ctx.organization.id, uom: "U2"})

    sscc = "006141411234567890"

    items = [
      cased_item(ctx, ctx.product, "CASE-A", 20, sscc),
      cased_item(ctx, product_b, "CASE-B", 15, sscc),
      delivery_item(ctx, "LOOSE-1", 10)
    ]

    assert {:ok, _receipt} =
             GoodsReceipts.receive_delivery(
               ctx.organization.id,
               ctx.user.id,
               items,
               Ecto.UUID.generate()
             )

    by_no = ctx.organization.id |> Batches.list_batches() |> Map.new(&{&1.batch_no, &1})

    unit_a = by_no["CASE-A"].logistic_unit_id
    unit_b = by_no["CASE-B"].logistic_unit_id

    # One unit owns both cased lines (a mixed case); loose stock stays unit-less.
    assert unit_a && unit_a == unit_b
    assert is_nil(by_no["LOOSE-1"].logistic_unit_id)

    unit = ThamaniDawa.Repo.get!(ThamaniDawa.Batches.LogisticUnit, unit_a)
    assert unit.sscc == sscc
    assert unit.kind == :case
    assert unit.source == :inbound
  end

  defp cased_item(ctx, product, batch_no, quantity, sscc) do
    %{
      attrs: %{
        "product_id" => product.id,
        "site_id" => ctx.warehouse.id,
        "supplier_id" => ctx.supplier.id,
        "gtin" => product.gtin,
        "batch_no" => batch_no,
        "expiry_date" => "2028-12-31",
        "quantity" => Integer.to_string(quantity),
        "sscc" => sscc
      }
    }
  end

  defp delivery_item(ctx, batch_no, quantity) do
    %{
      attrs: %{
        "product_id" => ctx.product.id,
        "site_id" => ctx.warehouse.id,
        "supplier_id" => ctx.supplier.id,
        "gtin" => ctx.product.gtin,
        "batch_no" => batch_no,
        "expiry_date" => "2028-12-31",
        "quantity" => Integer.to_string(quantity)
      }
    }
  end
end
