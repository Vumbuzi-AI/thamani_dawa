defmodule ThamaniDawa.StockTakesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeItem

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.StockTakesFixtures

  describe "create_stock_take/2" do
    test "creates a draft stock take with valid attributes" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      assert {:ok, %StockTake{} = take} =
               StockTakes.create_stock_take(org.id, %{
                 site_id: site.id,
                 started_by_id: user.id,
                 notes: "Q1 count"
               })

      assert take.organization_id == org.id
      assert take.site_id == site.id
      assert take.started_by_id == user.id
      assert take.status == :draft
      assert take.notes == "Q1 count"
      assert is_nil(take.finalized_at)
      assert is_nil(take.finalized_by_id)
    end

    test "requires site_id and started_by_id" do
      org = organization_fixture()

      assert {:error, changeset} = StockTakes.create_stock_take(org.id, %{})

      assert %{site_id: ["can't be blank"], started_by_id: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "pre-populates a count row for every active batch at the site" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      batch_a = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 30})
      batch_b = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 15})
      _pending = batch_fixture(%{organization_id: org.id, site_id: site.id, pending: true})

      {:ok, take} =
        StockTakes.create_stock_take(org.id, %{site_id: site.id, started_by_id: user.id})

      loaded = StockTakes.get_stock_take!(org.id, take.id)
      item_batch_ids = loaded.items |> Enum.map(& &1.batch_id) |> MapSet.new()

      assert MapSet.member?(item_batch_ids, batch_a.id)
      assert MapSet.member?(item_batch_ids, batch_b.id)
      assert length(loaded.items) == 2

      assert Enum.find(loaded.items, &(&1.batch_id == batch_a.id)).expected_quantity == 30
      assert Enum.find(loaded.items, &(&1.batch_id == batch_b.id)).expected_quantity == 15
    end

    test "notes is optional" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      assert {:ok, %StockTake{notes: nil}} =
               StockTakes.create_stock_take(org.id, %{
                 site_id: site.id,
                 started_by_id: user.id
               })
    end
  end

  describe "populate_items_for_site/3" do
    test "is idempotent — calling it twice does not create duplicate rows" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      _batch = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 10})

      {:ok, take} =
        StockTakes.create_stock_take(org.id, %{site_id: site.id, started_by_id: user.id})

      StockTakes.populate_items_for_site(take, org.id, site.id)
      StockTakes.populate_items_for_site(take, org.id, site.id)

      loaded = StockTakes.get_stock_take!(org.id, take.id)
      assert length(loaded.items) == 1
    end

    test "adds rows for newly active batches without touching existing rows" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      batch_a = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 20})

      {:ok, take} =
        StockTakes.create_stock_take(org.id, %{site_id: site.id, started_by_id: user.id})

      loaded_before = StockTakes.get_stock_take!(org.id, take.id)
      assert length(loaded_before.items) == 1

      batch_b = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 5})

      StockTakes.populate_items_for_site(take, org.id, site.id)

      loaded_after = StockTakes.get_stock_take!(org.id, take.id)
      assert length(loaded_after.items) == 2

      item_batch_ids = loaded_after.items |> Enum.map(& &1.batch_id) |> MapSet.new()
      assert MapSet.member?(item_batch_ids, batch_a.id)
      assert MapSet.member?(item_batch_ids, batch_b.id)
    end

    test "skips pending batches" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      _active = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 10})
      _pending = batch_fixture(%{organization_id: org.id, site_id: site.id, pending: true})

      {:ok, take} =
        StockTakes.create_stock_take(org.id, %{site_id: site.id, started_by_id: user.id})

      loaded = StockTakes.get_stock_take!(org.id, take.id)
      assert length(loaded.items) == 1
    end
  end

  describe "list_stock_takes_for_site/2" do
    test "returns stock takes only for the given site" do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id})
      site_b = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      {:ok, take_a} =
        StockTakes.create_stock_take(org.id, %{site_id: site_a.id, started_by_id: user.id})

      _take_b =
        stock_take_fixture(%{organization_id: org.id, site_id: site_b.id, started_by_id: user.id})

      result = StockTakes.list_stock_takes_for_site(org.id, site_a.id)
      assert [%StockTake{id: id}] = result
      assert id == take_a.id
    end

    test "does not cross organization boundaries" do
      org_a = organization_fixture()
      org_b = organization_fixture()
      site_a = site_fixture(%{organization_id: org_a.id})
      user_a = user_fixture(%{organization_id: org_a.id})

      {:ok, _take} =
        StockTakes.create_stock_take(org_a.id, %{site_id: site_a.id, started_by_id: user_a.id})

      assert [] = StockTakes.list_stock_takes_for_site(org_b.id, site_a.id)
    end
  end

  describe "add_item/2" do
    test "adds a batch to a draft stock take, snapshotting remaining_quantity" do
      org = organization_fixture()
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 40})

      assert {:ok, %StockTakeItem{} = item} = StockTakes.add_item(take, batch)
      assert item.stock_take_id == take.id
      assert item.batch_id == batch.id
      assert item.expected_quantity == batch.remaining_quantity
      assert is_nil(item.counted_quantity)
      assert is_nil(item.variance)
    end

    test "rejects adding the same batch twice" do
      org = organization_fixture()
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id})

      {:ok, _item} = StockTakes.add_item(take, batch)
      assert {:error, changeset} = StockTakes.add_item(take, batch)

      assert %{batch_id: ["this batch is already included in the stock take"]} =
               errors_on(changeset)
    end

    test "returns :already_finalized for a finalized session" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      %StockTake{} = take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})

      finalized_take = %StockTake{take | status: :finalized}
      batch = batch_fixture(%{organization_id: org.id})

      assert {:error, :already_finalized} = StockTakes.add_item(finalized_take, batch)
    end
  end

  describe "record_count/4" do
    test "records a physical count, computes variance, stamps counter and timestamp" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 50})
      {:ok, item} = StockTakes.add_item(take, batch)

      assert {:ok, %StockTakeItem{} = counted} = StockTakes.record_count(item, 45, user.id)
      assert counted.counted_quantity == 45
      assert counted.variance == 45 - item.expected_quantity
      assert counted.counted_by_id == user.id
      assert not is_nil(counted.counted_at)
    end

    test "rejects negative counted_quantity" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id})
      {:ok, item} = StockTakes.add_item(take, batch)

      assert {:error, changeset} = StockTakes.record_count(item, -1, user.id)
      assert %{counted_quantity: [_]} = errors_on(changeset)
    end

    test "accepts a counted_quantity of zero" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})
      {:ok, item} = StockTakes.add_item(take, batch)

      assert {:ok, counted} = StockTakes.record_count(item, 0, user.id)
      assert counted.counted_quantity == 0
      assert counted.variance == -item.expected_quantity
    end

    test "returns :already_finalized when parent session is finalized" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id})
      {:ok, item} = StockTakes.add_item(take, batch)

      # Finalize by patching status directly to avoid needing a fully-counted session
      Repo.update!(Ecto.Changeset.change(take, status: :finalized))

      assert {:error, :already_finalized} = StockTakes.record_count(item, 5, user.id)
    end
  end

  describe "finalize_stock_take/3" do
    test "sets batch remaining_quantity to counted_quantity for each item" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 100})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _counted} = StockTakes.record_count(item, 73, user.id)

      assert {:ok, %StockTake{status: :finalized} = finalized} =
               StockTakes.finalize_stock_take(take, user.id)

      assert finalized.finalized_by_id == user.id
      assert not is_nil(finalized.finalized_at)

      updated_batch = Batches.get_batch!(org.id, batch.id)
      assert updated_batch.remaining_quantity == 73
    end

    test "blocks finalization when any item has no count" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})
      batch = batch_fixture(%{organization_id: org.id})
      {:ok, _item} = StockTakes.add_item(take, batch)

      # item is un-counted
      assert {:error, :uncounted_items} = StockTakes.finalize_stock_take(take, user.id)
    end

    test "returns :already_finalized on a second call (concurrent-safety)" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 20})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _counted} = StockTakes.record_count(item, 20, user.id)

      assert {:ok, _finalized} = StockTakes.finalize_stock_take(take, user.id)
      assert {:error, :already_finalized} = StockTakes.finalize_stock_take(take, user.id)
    end

    test "finalizes a take with no items (empty session is valid)" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})

      assert {:ok, %StockTake{status: :finalized}} = StockTakes.finalize_stock_take(take, user.id)
    end

    test "handles multiple batches — all are reconciled" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})

      batch_a = batch_fixture(%{organization_id: org.id, quantity: 100})
      batch_b = batch_fixture(%{organization_id: org.id, quantity: 50})

      {:ok, item_a} = StockTakes.add_item(take, batch_a)
      {:ok, item_b} = StockTakes.add_item(take, batch_b)
      {:ok, _} = StockTakes.record_count(item_a, 90, user.id)
      {:ok, _} = StockTakes.record_count(item_b, 55, user.id)

      assert {:ok, _finalized} = StockTakes.finalize_stock_take(take, user.id)

      assert Batches.get_batch!(org.id, batch_a.id).remaining_quantity == 90
      assert Batches.get_batch!(org.id, batch_b.id).remaining_quantity == 55
    end
  end

  describe "get_stock_take!/2" do
    test "preloads items with their batches" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, started_by_id: user.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 30})
      {:ok, _item} = StockTakes.add_item(take, batch)

      loaded = StockTakes.get_stock_take!(org.id, take.id)
      assert [%StockTakeItem{batch: %{id: batch_id}} | _] = loaded.items
      assert batch_id == batch.id
    end

    test "raises for a stock take belonging to another organization" do
      org_a = organization_fixture()
      org_b = organization_fixture()
      take = stock_take_fixture(%{organization_id: org_a.id})

      assert_raise Ecto.NoResultsError, fn ->
        StockTakes.get_stock_take!(org_b.id, take.id)
      end
    end
  end
end
