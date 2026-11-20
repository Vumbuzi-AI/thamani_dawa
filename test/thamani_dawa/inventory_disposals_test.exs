defmodule ThamaniDawa.InventoryDisposalsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.InventoryDisposals.InventoryDisposalItem

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.InventoryDisposalsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  describe "create_disposal/2" do
    test "creates a draft disposal with valid attributes" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      assert {:ok, %InventoryDisposal{} = disposal} =
               InventoryDisposals.create_disposal(org.id, %{
                 site_id: site.id,
                 kind: :expiry,
                 inventory_type: :medicine,
                 requested_by_id: user.id,
                 reason: "Past expiry"
               })

      assert disposal.organization_id == org.id
      assert disposal.site_id == site.id
      assert disposal.kind == :expiry
      assert disposal.requested_by_id == user.id
      assert disposal.status == :draft
    end

    test "requires site_id, kind, and inventory_type" do
      org = organization_fixture()

      assert {:error, changeset} = InventoryDisposals.create_disposal(org.id, %{})

      assert %{
               site_id: ["can't be blank"],
               kind: ["can't be blank"],
               inventory_type: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires either admin_id or requested_by_id, not both" do
      org = organization_fixture()
      site = site_fixture(%{organization_id: org.id})

      assert {:error, changeset} =
               InventoryDisposals.create_disposal(org.id, %{
                 site_id: site.id,
                 kind: :expiry,
                 inventory_type: :medicine
               })

      assert %{requested_by_id: ["either admin_id or requested_by_id is required"]} =
               errors_on(changeset)

      admin = user_fixture(%{organization_id: org.id})
      requester = user_fixture(%{organization_id: org.id})

      assert {:error, changeset} =
               InventoryDisposals.create_disposal(org.id, %{
                 site_id: site.id,
                 kind: :expiry,
                 inventory_type: :medicine,
                 admin_id: admin.id,
                 requested_by_id: requester.id
               })

      assert %{admin_id: ["only one of admin_id or requested_by_id may be set"]} =
               errors_on(changeset)
    end
  end

  describe "add_item/3" do
    test "adds a past-date lot for the whole remaining quantity" do
      org = organization_fixture()
      disposal = disposal_fixture(%{organization_id: org.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 40}))

      assert {:ok, %InventoryDisposalItem{} = item} =
               InventoryDisposals.add_item(disposal, batch, 40)

      assert item.batch_id == batch.id
      assert item.available_quantity == 40
      assert item.quantity == 40
    end

    test "rejects an expiry write-off of a lot that has not expired" do
      org = organization_fixture()
      disposal = disposal_fixture(%{organization_id: org.id})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})

      assert {:error, :not_expired} = InventoryDisposals.add_item(disposal, batch, 10)
    end

    test "rejects a partial expiry write-off" do
      org = organization_fixture()
      disposal = disposal_fixture(%{organization_id: org.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 40}))

      assert {:error, :partial_expiry} = InventoryDisposals.add_item(disposal, batch, 10)
    end

    test "rejects a quantity greater than available" do
      org = organization_fixture()
      supplier = supplier_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, kind: :returned})

      batch =
        batch_fixture(%{organization_id: org.id, quantity: 10, supplier_id: supplier.id})

      assert {:error, changeset} = InventoryDisposals.add_item(disposal, batch, 11)
      assert %{quantity: ["cannot exceed the available quantity"]} = errors_on(changeset)
    end

    test "rejects adding the same batch twice" do
      org = organization_fixture()
      disposal = disposal_fixture(%{organization_id: org.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 10}))

      {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 10)
      assert {:error, changeset} = InventoryDisposals.add_item(disposal, batch, 10)

      assert %{batch_id: ["this batch is already included in this disposal"]} =
               errors_on(changeset)
    end

    test "rejects a supplier-less batch on a :returned disposal" do
      org = organization_fixture()
      disposal = disposal_fixture(%{organization_id: org.id, kind: :returned})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10})

      assert {:error, :no_supplier} = InventoryDisposals.add_item(disposal, batch, 5)
    end

    test "allows a supplied batch on a :returned disposal" do
      org = organization_fixture()
      supplier = supplier_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, kind: :returned})
      batch = batch_fixture(%{organization_id: org.id, quantity: 10, supplier_id: supplier.id})

      assert {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 5)
    end

    test "returns :not_draft for a non-draft disposal" do
      org = organization_fixture()
      disposal = disposal_fixture(%{organization_id: org.id})
      pending_disposal = %InventoryDisposal{disposal | status: :pending}
      batch = batch_fixture(%{organization_id: org.id})

      assert {:error, :not_draft} = InventoryDisposals.add_item(pending_disposal, batch, 1)
    end
  end

  describe "remove_item/1" do
    test "removes an item from a draft disposal" do
      org = organization_fixture()
      item = disposal_item_fixture(%{organization_id: org.id})

      assert {:ok, _item} = InventoryDisposals.remove_item(item)
      refute Repo.get(InventoryDisposalItem, item.id)
    end

    test "returns :not_draft for a non-draft disposal" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      item = disposal_item_fixture(%{organization_id: org.id, disposal: disposal})
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:error, :not_draft} = InventoryDisposals.remove_item(item)
    end
  end

  describe "submit_disposal/3" do
    test "moves a draft with items to pending" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      _item = disposal_item_fixture(%{organization_id: org.id, disposal: disposal})

      assert {:ok, %InventoryDisposal{status: :pending}} =
               InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)
    end

    test "rejects submission with no items" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})

      assert {:error, :no_items} =
               InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)
    end

    test "rejects submission from someone other than the requester" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      other = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      _item = disposal_item_fixture(%{organization_id: org.id, disposal: disposal})

      assert {:error, :not_requester} =
               InventoryDisposals.submit_disposal(org.id, disposal.id, other.id)
    end

    test "rejects submission when stock has changed since an item was added" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 10}))
      {:ok, item} = InventoryDisposals.add_item(disposal, batch, 10)

      {:ok, _} = Batches.decrement_remaining_quantity(batch, 5)

      assert {:error, {:stock_changed, item_id}} =
               InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert item_id == item.id

      assert %InventoryDisposal{status: :draft} =
               Repo.get!(InventoryDisposal, disposal.id)
    end
  end

  describe "approve_disposal/3" do
    test "decrements the batch and marks it expired when fully disposed (kind: :expiry)" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 30}))
      {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 30)
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:ok, %InventoryDisposal{status: :approved}} =
               InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)

      updated = Batches.get_batch!(org.id, batch.id)
      assert updated.remaining_quantity == 0
      assert updated.status == :expired
    end

    test "decrements the batch and marks it returned when fully disposed (kind: :returned)" do
      org = organization_fixture()
      supplier = supplier_fixture(%{organization_id: org.id})
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})

      disposal =
        disposal_fixture(%{
          organization_id: org.id,
          requested_by_id: requester.id,
          kind: :returned
        })

      batch = batch_fixture(%{organization_id: org.id, quantity: 20, supplier_id: supplier.id})
      {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 20)
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:ok, _approved} = InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)

      updated = Batches.get_batch!(org.id, batch.id)
      assert updated.remaining_quantity == 0
      assert updated.status == :returned
    end

    test "a partial supplier return decrements quantity but leaves status :active" do
      org = organization_fixture()
      supplier = supplier_fixture(%{organization_id: org.id})
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})

      disposal =
        disposal_fixture(%{
          organization_id: org.id,
          requested_by_id: requester.id,
          kind: :returned
        })

      batch =
        batch_fixture(%{organization_id: org.id, quantity: 30, supplier_id: supplier.id})

      {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 10)
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:ok, _approved} = InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)

      updated = Batches.get_batch!(org.id, batch.id)
      assert updated.remaining_quantity == 20
      assert updated.status == :active
    end

    test "fully disposing an already-quarantined batch zeroes it without changing status" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 15}))

      {:ok, quarantined} =
        batch |> ThamaniDawa.Batches.Batch.status_changeset(:quarantined) |> Repo.update()

      {:ok, _item} = InventoryDisposals.add_item(disposal, quarantined, 15)
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:ok, _approved} = InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)

      updated = Batches.get_batch!(org.id, batch.id)
      assert updated.remaining_quantity == 0
      assert updated.status == :quarantined
    end

    test "allows an admin to approve directly from draft (skip-the-request path)" do
      org = organization_fixture()
      admin = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, admin_id: admin.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 12}))
      {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 12)

      assert {:ok, %InventoryDisposal{status: :approved}} =
               InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)
    end

    test "rejects approval of an already-approved disposal" do
      org = organization_fixture()
      admin = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, admin_id: admin.id})

      assert {:ok, _approved} = InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)

      assert {:error, :not_approvable} =
               InventoryDisposals.approve_disposal(org.id, disposal.id, admin.id)
    end
  end

  describe "reject_disposal/4" do
    test "rejects a pending disposal with a reason and makes no batch mutation" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      batch = batch_fixture(expired_batch_attrs(%{organization_id: org.id, quantity: 25}))
      {:ok, _item} = InventoryDisposals.add_item(disposal, batch, 25)
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:ok, %InventoryDisposal{status: :rejected} = rejected} =
               InventoryDisposals.reject_disposal(
                 org.id,
                 disposal.id,
                 admin.id,
                 "Not past expiry"
               )

      assert rejected.rejection_reason == "Not past expiry"
      assert Batches.get_batch!(org.id, batch.id).remaining_quantity == 25
    end

    test "requires a rejection reason" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      admin = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      _item = disposal_item_fixture(%{organization_id: org.id, disposal: disposal})
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:error, changeset} =
               InventoryDisposals.reject_disposal(org.id, disposal.id, admin.id, "")

      assert %{rejection_reason: [_]} = errors_on(changeset)
    end
  end

  describe "reopen_disposal/3" do
    test "moves a pending disposal back to draft for its requester" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      _item = disposal_item_fixture(%{organization_id: org.id, disposal: disposal})
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:ok, %InventoryDisposal{status: :draft}} =
               InventoryDisposals.reopen_disposal(org.id, disposal.id, requester.id)
    end

    test "rejects reopening by someone other than the requester" do
      org = organization_fixture()
      requester = user_fixture(%{organization_id: org.id})
      other = user_fixture(%{organization_id: org.id})
      disposal = disposal_fixture(%{organization_id: org.id, requested_by_id: requester.id})
      _item = disposal_item_fixture(%{organization_id: org.id, disposal: disposal})
      {:ok, _pending} = InventoryDisposals.submit_disposal(org.id, disposal.id, requester.id)

      assert {:error, :not_requester} =
               InventoryDisposals.reopen_disposal(org.id, disposal.id, other.id)
    end
  end

  describe "list_disposals_for_site/4" do
    test "returns disposals only for the given site, kind, and inventory type" do
      org = organization_fixture()
      site_a = site_fixture(%{organization_id: org.id})
      site_b = site_fixture(%{organization_id: org.id})
      user = user_fixture(%{organization_id: org.id})

      disposal_a =
        disposal_fixture(%{organization_id: org.id, site_id: site_a.id, requested_by_id: user.id})

      _disposal_b =
        disposal_fixture(%{organization_id: org.id, site_id: site_b.id, requested_by_id: user.id})

      result = InventoryDisposals.list_disposals_for_site(org.id, site_a.id, :expiry, :medicine)
      assert [%InventoryDisposal{id: id}] = result
      assert id == disposal_a.id
    end
  end

  defp expired_batch_attrs(attrs) do
    Map.put(attrs, :expiry_date, Date.add(Date.utc_today(), -1))
  end
end
