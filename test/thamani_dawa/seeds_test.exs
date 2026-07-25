defmodule ThamaniDawa.SeedsTest do
  use ThamaniDawa.DataCase, async: false

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Payments.WalletEntry
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeItem
  alias ThamaniDawa.Suppliers.Supplier

  @moduletag timeout: 120_000

  @seeds_path Path.expand("../../priv/repo/seeds.exs", __DIR__)

  # Runs against an empty (sandboxed, non-transactional) database and again
  # on top of its own output, asserting the second run neither duplicates
  # rows nor raises — the two guarantees the seed script itself promises.
  test "seeds run on an empty database and are idempotent on rerun" do
    run_seeds!()

    organization = Repo.get_by!(Organization, slug: "demo-care")
    first_run = snapshot(organization.id)

    assert first_run.products > 0
    assert first_run.batches > 0
    assert first_run.suppliers > 0
    assert first_run.patients > 0
    assert first_run.payments > 0
    assert first_run.wallet_entries > 0
    assert first_run.stock_takes == 2
    assert first_run.stock_take_items > 0

    run_seeds!()

    second_run = snapshot(organization.id)

    assert second_run == first_run
  end

  defp run_seeds! do
    Code.eval_file(@seeds_path)
    :ok
  end

  defp snapshot(organization_id) do
    %{
      products: count(Product, organization_id),
      batches: count(Batch, organization_id),
      suppliers: count(Supplier, organization_id),
      patients: count(Patient, organization_id),
      payments: count(Payment, organization_id),
      wallet_entries: count(WalletEntry, organization_id),
      stock_takes: count(StockTake, organization_id),
      stock_take_items: count(StockTakeItem, organization_id)
    }
  end

  defp count(schema, organization_id) do
    Repo.aggregate(
      from(r in schema, where: r.organization_id == ^organization_id),
      :count
    )
  end
end
