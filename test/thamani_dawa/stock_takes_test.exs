defmodule ThamaniDawa.StockTakesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.StockTakes
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeItem

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
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
                 inventory_type: :medicine,
                 requested_by_id: user.id,
                 notes: "Q1 count"
               })

      assert take.organization_id == org.id
      assert take.site_id == site.id
      assert take.requested_by_id == user.id
      assert take.status == :draft
      assert take.notes == "Q1 count"
      assert is_nil(take.approved_at)
      assert is_nil(take.approved_by_id)
    end

    test "requires site_id and inventory_type" do
      org = organization_fixture()

      assert {:error, changeset} = StockTakes.create_stock_take(org.id, %{})

      assert %{site_id: ["can't be blank"], inventory_type: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "requires either admin_id or requested_by_id, not both" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})

      assert {:error, changeset} =
               StockTakes.create_stock_take(org.id, %{site_id: site.id, inventory_type: :medicine})

      assert %{requested_by_id: ["either admin_id or requested_by_id is required"]} =
               errors_on(changeset)

      admin = user_fixture(%{organization_id: org.id})
      requester = user_fixture(%{organization_id: org.id})

      assert {:error, changeset} =
               StockTakes.create_stock_take(org.id, %{
                 site_id: site.id,
                 inventory_type: :medicine,
                 admin_id: admin.id,
                 requested_by_id: requester.id
               })

      assert %{admin_id: ["only one of admin_id or requested_by_id may be set"]} =
               errors_on(changeset)
    end

    test "allows an admin-direct draft without a requester" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})

      assert {:ok, %StockTake{admin_id: admin_id, requested_by_id: nil}} =
               StockTakes.create_stock_take(org.id, %{
                 site_id: site.id,
                 inventory_type: :medicine,
                 admin_id: admin.id
               })

      assert admin_id == admin.id
    end

    test "pre-populates a count row for every active batch of the matching inventory type at the site" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})
      lab_product = product_fixture(%{organization_id: org.id, inventory_type: :lab_consumable})

      batch_a = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 30})
      batch_b = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 15})

      _lab_batch =
        batch_fixture(%{
          organization_id: org.id,
          site_id: site.id,
          product_id: lab_product.id,
          quantity: 5
        })

      _pending = batch_fixture(%{organization_id: org.id, site_id: site.id, pending: true})

      {:ok, take} =
        StockTakes.create_stock_take(org.id, %{
          site_id: site.id,
          inventory_type: :medicine,
          requested_by_id: user.id
        })

      loaded = StockTakes.get_stock_take!(org.id, take.id)
      item_batch_ids = loaded.items |> Enum.map(& &1.batch_id) |> MapSet.new()

      assert MapSet.member?(item_batch_ids, batch_a.id)
      assert MapSet.member?(item_batch_ids, batch_b.id)
      assert length(loaded.items) == 2

      assert Enum.find(loaded.items, &(&1.batch_id == batch_a.id)).expected_quantity == 30
      assert Enum.find(loaded.items, &(&1.batch_id == batch_b.id)).expected_quantity == 15
    end
  end

  describe "populate_items_for_site/3" do
    test "is idempotent — calling it twice does not create duplicate rows" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      _batch = batch_fixture(%{organization_id: org.id, site_id: site.id, quantity: 10})

      {:ok, take} =
        StockTakes.create_stock_take(org.id, %{
          site_id: site.id,
          inventory_type: :medicine,
          requested_by_id: user.id
        })

      StockTakes.populate_items_for_site(take, org.id, site.id)
      StockTakes.populate_items_for_site(take, org.id, site.id)

      loaded = StockTakes.get_stock_take!(org.id, take.id)
      assert length(loaded.items) == 1
    end
  end

  describe "list_stock_takes_for_site/3" do
    test "returns stock takes only for the given site and inventory type" do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id})
      site_b = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      {:ok, take_a} =
        StockTakes.create_stock_take(org.id, %{
          site_id: site_a.id,
          inventory_type: :medicine,
          requested_by_id: user.id
        })

      _take_b =
        stock_take_fixture(%{
          organization_id: org.id,
          site_id: site_b.id,
          requested_by_id: user.id
        })

      result = StockTakes.list_stock_takes_for_site(org.id, site_a.id, :medicine)
      assert [%StockTake{id: id}] = result
      assert id == take_a.id
    end

    test "does not cross organization boundaries" do
      org_a = organization_fixture()
      org_b = organization_fixture()
      site_a = site_fixture(%{organization_id: org_a.id})
      user_a = user_fixture(%{organization_id: org_a.id})

      {:ok, _take} =
        StockTakes.create_stock_take(org_a.id, %{
          site_id: site_a.id,
          inventory_type: :medicine,
          requested_by_id: user_a.id
        })

      assert [] = StockTakes.list_stock_takes_for_site(org_b.id, site_a.id, :medicine)
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

    test "returns :not_draft for a non-draft session" do
      org = organization_fixture()
      take = stock_take_fixture(%{organization_id: org.id})
      pending_take = %StockTake{take | status: :pending}
      batch = batch_fixture(%{organization_id: org.id})

      assert {:error, :not_draft} = StockTakes.add_item(pending_take, batch)
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

    test "returns :not_draft when parent session is no longer a draft" do
      org = organization_fixture()
      user = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id})
      {:ok, item} = StockTakes.add_item(take, batch)

      Repo.update!(Ecto.Changeset.change(take, status: :pending))

      assert {:error, :not_draft} = StockTakes.record_count(item, 5, user.id)
    end
  end

  describe "submit_stock_take/3" do
    test "moves a draft with at least one counted item to pending" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 8, requester.id)

      assert {:ok, %StockTake{status: :pending}} =
               StockTakes.submit_stock_take(org.id, take.id, requester.id)
    end

    test "rejects submission with no counted items" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      _batch_only = batch_fixture(%{organization_id: org.id})

      assert {:error, :no_counted_items} =
               StockTakes.submit_stock_take(org.id, take.id, requester.id)
    end

    test "rejects submission from someone other than the requester" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      other = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 8, requester.id)

      assert {:error, :not_requester} = StockTakes.submit_stock_take(org.id, take.id, other.id)
    end
  end

  describe "approve_stock_take/3" do
    test "applies counted items' quantities and marks the session approved" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})

      batch_a = batch_fixture(%{organization_id: org.id, quantity: 100})
      batch_b = batch_fixture(%{organization_id: org.id, quantity: 50})

      {:ok, item_a} = StockTakes.add_item(take, batch_a)
      {:ok, item_b} = StockTakes.add_item(take, batch_b)
      {:ok, _} = StockTakes.record_count(item_a, 90, requester.id)
      {:ok, _} = StockTakes.record_count(item_b, 55, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(org.id, take.id, requester.id)

      assert {:ok, %StockTake{status: :approved} = approved} =
               StockTakes.approve_stock_take(org.id, take.id, admin.id)

      assert approved.approved_by_id == admin.id
      assert not is_nil(approved.approved_at)

      assert Batches.get_batch!(org.id, batch_a.id).remaining_quantity == 90
      assert Batches.get_batch!(org.id, batch_b.id).remaining_quantity == 55
    end

    test "leaves uncounted items' batches untouched" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})

      counted_batch = batch_fixture(%{organization_id: org.id, quantity: 20})
      uncounted_batch = batch_fixture(%{organization_id: org.id, quantity: 20})

      {:ok, counted_item} = StockTakes.add_item(take, counted_batch)
      {:ok, _uncounted_item} = StockTakes.add_item(take, uncounted_batch)
      {:ok, _} = StockTakes.record_count(counted_item, 15, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(org.id, take.id, requester.id)

      assert {:ok, _approved} = StockTakes.approve_stock_take(org.id, take.id, admin.id)

      assert Batches.get_batch!(org.id, counted_batch.id).remaining_quantity == 15
      assert Batches.get_batch!(org.id, uncounted_batch.id).remaining_quantity == 20
    end

    test "allows an admin to approve directly from draft (skip-the-request path)" do
      org = organization_fixture()
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, admin_id: admin.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 30})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 25, admin.id)

      assert {:ok, %StockTake{status: :approved}} =
               StockTakes.approve_stock_take(org.id, take.id, admin.id)

      assert Batches.get_batch!(org.id, batch.id).remaining_quantity == 25
    end

    test "rejects approval of an already-approved session" do
      org = organization_fixture()
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, admin_id: admin.id})

      assert {:ok, _approved} = StockTakes.approve_stock_take(org.id, take.id, admin.id)
      assert {:error, :not_approvable} = StockTakes.approve_stock_take(org.id, take.id, admin.id)
    end
  end

  describe "reject_stock_take/4" do
    test "rejects a pending session with a reason and makes no batch mutation" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 40})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 35, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(org.id, take.id, requester.id)

      assert {:ok, %StockTake{status: :rejected} = rejected} =
               StockTakes.reject_stock_take(org.id, take.id, admin.id, "Recount needed")

      assert rejected.rejection_reason == "Recount needed"
      assert Batches.get_batch!(org.id, batch.id).remaining_quantity == 40
    end

    test "requires a rejection reason" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(%{organization_id: org.id})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 1, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(org.id, take.id, requester.id)

      assert {:error, changeset} = StockTakes.reject_stock_take(org.id, take.id, admin.id, "")
      assert %{rejection_reason: [_]} = errors_on(changeset)
    end

    test "cannot reject a draft session" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})

      assert {:error, :not_pending} =
               StockTakes.reject_stock_take(org.id, take.id, admin.id, "No")
    end
  end

  describe "reopen_stock_take/3" do
    test "moves a pending session back to draft for its requester" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 8, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(org.id, take.id, requester.id)

      assert {:ok, %StockTake{status: :draft}} =
               StockTakes.reopen_stock_take(org.id, take.id, requester.id)
    end

    test "rejects reopening by someone other than the requester" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      other = user_fixture(%{organization_id: org.id})
      take = stock_take_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})
      {:ok, item} = StockTakes.add_item(take, batch)
      {:ok, _} = StockTakes.record_count(item, 8, requester.id)
      {:ok, _pending} = StockTakes.submit_stock_take(org.id, take.id, requester.id)

      assert {:error, :not_requester} = StockTakes.reopen_stock_take(org.id, take.id, other.id)
    end
  end

  describe "get_stock_take!/2" do
    test "preloads items with their batches" do
      org = organization_fixture()
      take = stock_take_fixture(%{organization_id: org.id})
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
