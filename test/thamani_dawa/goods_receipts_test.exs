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
      SitesFixtures.site_fixture(%{organization_id: organization.id, site_type: :warehouse})

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
