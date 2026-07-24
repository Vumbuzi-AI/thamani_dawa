defmodule ThamaniDawa.StockTakesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes
  alias ThamaniDawa.StockTakes.StockTake

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.StockTakesFixtures

  describe "start_stock_take/4" do
    test "creates a draft stock take with one entry per active batch at the site" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      active =
        batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 40})

      assert {:ok, stock_take} =
               StockTakes.start_stock_take(organization.id, site.id, user.id)

      assert stock_take.status == :draft
      assert stock_take.site_id == site.id
      assert stock_take.started_by_id == user.id

      [entry] = StockTakes.get_stock_take!(organization.id, stock_take.id).entries
      assert entry.batch_id == active.id
      assert entry.expected_quantity == 40
      assert is_nil(entry.counted_quantity)
    end

    test "excludes pending (not yet received) batches" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      batch_fixture(%{organization_id: organization.id, site_id: site.id, pending: true})

      assert {:ok, stock_take} = StockTakes.start_stock_take(organization.id, site.id, user.id)
      assert StockTakes.get_stock_take!(organization.id, stock_take.id).entries == []
    end

    test "excludes depleted batches (zero remaining quantity)" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      depleted =
        batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 5})

      {:ok, _} = Batches.decrement_remaining_quantity(depleted, 5)

      assert {:ok, stock_take} = StockTakes.start_stock_take(organization.id, site.id, user.id)
      assert StockTakes.get_stock_take!(organization.id, stock_take.id).entries == []
    end

    test "fails when the site already has a stock take in progress" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      assert {:ok, _first} = StockTakes.start_stock_take(organization.id, site.id, user.id)

      assert {:error, changeset} =
               StockTakes.start_stock_take(organization.id, site.id, user.id)

      assert %{organization_id: ["already has a stock take in progress"]} = errors_on(changeset)
    end

    test "allows a new stock take once the previous one at the site is completed" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      assert {:ok, first} = StockTakes.start_stock_take(organization.id, site.id, user.id)

      assert {:ok, _completed, _summary} =
               StockTakes.finalize_stock_take(organization.id, first.id, user.id)

      assert {:ok, second} = StockTakes.start_stock_take(organization.id, site.id, user.id)
      assert second.id != first.id
    end

    test "a different site in the same organization can have its own concurrent draft" do
      organization = organization_fixture()
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      assert {:ok, _} = StockTakes.start_stock_take(organization.id, site_a.id, user.id)
      assert {:ok, _} = StockTakes.start_stock_take(organization.id, site_b.id, user.id)
    end
  end

  describe "get_active_stock_take/2" do
    test "returns the site's in-progress stock take" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})

      assert %StockTake{id: id} = StockTakes.get_active_stock_take(organization.id, site.id)
      assert id == stock_take.id
    end

    test "returns nil when the site has none in progress" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      assert StockTakes.get_active_stock_take(organization.id, site.id) == nil
    end

    test "returns nil once the stock take is completed" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      {:ok, _, _} = StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)

      assert StockTakes.get_active_stock_take(organization.id, site.id) == nil
    end
  end

  describe "get_stock_take!/2" do
    test "raises when the stock take belongs to a different organization" do
      other_organization = organization_fixture()
      stock_take = stock_take_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        StockTakes.get_stock_take!(other_organization.id, stock_take.id)
      end
    end
  end

  describe "record_count/4" do
    test "records the counted quantity and computes variance" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      [entry] = stock_take.entries

      assert {:ok, updated} =
               StockTakes.record_count(organization.id, entry.id, user.id, %{
                 "counted_quantity" => "35"
               })

      assert updated.counted_quantity == 35
      assert updated.variance == -5
      assert updated.counted_by_id == user.id
    end

    test "rejects a negative counted quantity" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      [entry] = stock_take.entries

      assert {:error, changeset} =
               StockTakes.record_count(organization.id, entry.id, user.id, %{
                 "counted_quantity" => "-1"
               })

      assert %{counted_quantity: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "returns :not_draft once the stock take is finalized" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, _, _} = StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)

      assert {:error, :not_draft} =
               StockTakes.record_count(organization.id, entry.id, user.id, %{
                 "counted_quantity" => "10"
               })
    end
  end

  describe "finalize_stock_take/3" do
    test "applies a counted entry to the batch's remaining_quantity" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch = batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, _} =
        StockTakes.record_count(organization.id, entry.id, user.id, %{
          "counted_quantity" => "33"
        })

      assert {:ok, completed, %{applied: applied, conflicted: []}} =
               StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)

      assert completed.status == :completed
      assert completed.completed_by_id == user.id
      assert applied == [entry.id]

      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 33
    end

    test "leaves an uncounted entry's batch untouched" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch = batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})

      assert {:ok, _completed, %{applied: [], conflicted: []}} =
               StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)

      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 40
    end

    test "flags a conflict instead of overwriting when the batch changed mid-count" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch = batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      [entry] = stock_take.entries

      {:ok, _} =
        StockTakes.record_count(organization.id, entry.id, user.id, %{
          "counted_quantity" => "33"
        })

      # Something else (e.g. a dispense) changes the batch after it was counted.
      {:ok, _} = Batches.decrement_remaining_quantity(batch, 10)

      assert {:ok, completed, %{applied: [], conflicted: conflicted}} =
               StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)

      assert completed.status == :completed
      assert conflicted == [entry.id]

      # The intervening dispense is preserved, not clobbered by the stale count.
      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 30

      [reloaded_entry] = StockTakes.get_stock_take!(organization.id, stock_take.id).entries
      refute reloaded_entry.has_been_applied
    end

    test "returns :not_draft when finalizing an already-completed stock take" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      {:ok, _, _} = StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)

      assert {:error, :not_draft} =
               StockTakes.finalize_stock_take(organization.id, stock_take.id, user.id)
    end
  end

  describe "StockTake.statuses/0" do
    test "lists the valid statuses" do
      assert StockTake.statuses() == [:draft, :completed]
    end
  end

  describe "record_count/4 with a blank quantity" do
    test "is invalid and leaves variance unset" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 40})

      stock_take = stock_take_fixture(%{organization_id: organization.id, site_id: site.id})
      [entry] = stock_take.entries

      assert {:error, changeset} =
               StockTakes.record_count(organization.id, entry.id, user.id, %{
                 "counted_quantity" => ""
               })

      assert %{counted_quantity: ["can't be blank"]} = errors_on(changeset)
      assert is_nil(Ecto.Changeset.get_change(changeset, :variance))
    end
  end
end
