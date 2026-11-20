defmodule ThamaniDawa.RecallsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.Batches
  alias ThamaniDawa.BatchesFixtures
  alias ThamaniDawa.Recalls

  describe "initiate_recall/6" do
    test "creates a Recall and a RecallHolder per matching batch, cascading :recalled" do
      gtin = BatchesFixtures.unique_gtin()
      batch_no = "BATCH-SHARED-#{System.unique_integer()}"

      batch_a = BatchesFixtures.batch_fixture(%{gtin: gtin, batch_no: batch_no})
      batch_b = BatchesFixtures.batch_fixture(%{gtin: gtin, batch_no: batch_no})
      superadmin = AccountsFixtures.superadmin_fixture()

      assert {:ok, recall} =
               Recalls.initiate_recall(
                 gtin,
                 batch_no,
                 "INC-1",
                 :class_ii,
                 "contamination",
                 superadmin
               )

      assert recall.status == :open
      assert recall.classification == :class_ii

      reloaded = Recalls.get_recall!(recall.id)
      assert length(reloaded.holders) == 2

      assert reloaded.holders |> Enum.map(& &1.organization_id) |> Enum.sort() ==
               Enum.sort([batch_a.organization_id, batch_b.organization_id])

      assert Batches.get_batch!(batch_a.organization_id, batch_a.id).status == :recalled
      assert Batches.get_batch!(batch_b.organization_id, batch_b.id).status == :recalled
    end

    test "does not recall a batch already destroyed" do
      gtin = BatchesFixtures.unique_gtin()
      batch_no = "BATCH-SHARED-#{System.unique_integer()}"

      destroyed = BatchesFixtures.batch_fixture(%{gtin: gtin, batch_no: batch_no})
      superadmin = AccountsFixtures.superadmin_fixture()
      {:ok, destroyed} = Batches.mark_damaged(destroyed, "DMG-1", superadmin)
      {:ok, destroyed} = Batches.mark_destroyed(destroyed, "DST-1", superadmin)

      assert {:ok, recall} =
               Recalls.initiate_recall(gtin, batch_no, "INC-2", :class_i, nil, superadmin)

      reloaded = Recalls.get_recall!(recall.id)
      assert reloaded.holders == []
      assert Batches.get_batch!(destroyed.organization_id, destroyed.id).status == :destroyed
    end
  end

  describe "acknowledge_holder/2" do
    test "succeeds for an admin of the holder's own organization" do
      gtin = BatchesFixtures.unique_gtin()
      batch_no = "BATCH-SHARED-#{System.unique_integer()}"
      batch = BatchesFixtures.batch_fixture(%{gtin: gtin, batch_no: batch_no})
      superadmin = AccountsFixtures.superadmin_fixture()

      {:ok, recall} =
        Recalls.initiate_recall(gtin, batch_no, "INC-3", :class_iii, nil, superadmin)

      [holder] = Recalls.get_recall!(recall.id).holders
      admin = AccountsFixtures.user_fixture(%{organization_id: batch.organization_id})

      assert {:ok, acknowledged} = Recalls.acknowledge_holder(holder.id, admin)
      assert acknowledged.acknowledged_at
      assert acknowledged.acknowledged_by_id == admin.id
    end

    test "rejects an admin from a different organization" do
      gtin = BatchesFixtures.unique_gtin()
      batch_no = "BATCH-SHARED-#{System.unique_integer()}"
      _batch = BatchesFixtures.batch_fixture(%{gtin: gtin, batch_no: batch_no})
      superadmin = AccountsFixtures.superadmin_fixture()

      {:ok, recall} =
        Recalls.initiate_recall(gtin, batch_no, "INC-4", :class_iii, nil, superadmin)

      [holder] = Recalls.get_recall!(recall.id).holders
      outsider = AccountsFixtures.user_fixture()

      assert {:error, :not_authorized} = Recalls.acknowledge_holder(holder.id, outsider)
    end
  end

  describe "progress/1" do
    test "reflects acknowledgement and recovery read live off batch status" do
      gtin = BatchesFixtures.unique_gtin()
      batch_no = "BATCH-SHARED-#{System.unique_integer()}"
      batch = BatchesFixtures.batch_fixture(%{gtin: gtin, batch_no: batch_no, quantity: 50})
      superadmin = AccountsFixtures.superadmin_fixture()

      {:ok, recall} = Recalls.initiate_recall(gtin, batch_no, "INC-5", :class_i, nil, superadmin)
      reloaded = Recalls.get_recall!(recall.id)

      assert Recalls.progress(reloaded) == %{
               holders: 1,
               acknowledged: 0,
               units_total: 50,
               units_recovered: 0
             }

      recalled_batch = Batches.get_batch!(batch.organization_id, batch.id)
      {:ok, _} = Batches.mark_destroyed(recalled_batch, "DST-2", superadmin)

      assert Recalls.progress(Recalls.get_recall!(recall.id)) == %{
               holders: 1,
               acknowledged: 0,
               units_total: 50,
               units_recovered: 50
             }
    end
  end
end
