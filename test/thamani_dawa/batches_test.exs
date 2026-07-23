defmodule ThamaniDawa.BatchesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  describe "create_batch/2" do
    test "requires gtin, batch_no, expiry_date, quantity, product_id, and site_id" do
      organization = organization_fixture()
      assert {:error, changeset} = Batches.create_batch(organization.id, %{})

      assert %{
               gtin: ["can't be blank"],
               batch_no: ["can't be blank"],
               expiry_date: ["can't be blank"],
               quantity: ["can't be blank"],
               product_id: ["can't be blank"],
               site_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "does not require approver_id at dispatch time" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, %Batch{approver_id: nil}} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50
               })
    end

    test "defaults remaining_quantity to quantity when omitted" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, %Batch{} = batch} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50
               })

      assert batch.organization_id == organization.id
      assert batch.quantity == 50
      assert batch.remaining_quantity == 50
    end

    test "keeps an explicit remaining_quantity that differs from quantity" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, %Batch{} = batch} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50,
                 remaining_quantity: 10
               })

      assert batch.remaining_quantity == 10
    end

    test "sets an optional supplier_id for a direct receipt" do
      organization = organization_fixture()
      supplier = supplier_fixture(%{organization_id: organization.id})

      batch = batch_fixture(%{organization_id: organization.id, supplier_id: supplier.id})

      assert batch.supplier_id == supplier.id
    end

    test "rejects a negative quantity" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: -5
               })

      assert %{quantity: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "rejects a site_id that belongs to a different organization" do
      organization = organization_fixture()
      other_org = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      hostile_site = site_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: hostile_site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert %{site_id: ["does not belong to this organization"]} = errors_on(changeset)
    end

    test "rejects a product_id that belongs to a different organization" do
      organization = organization_fixture()
      other_org = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      hostile_product = product_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Batches.create_batch(organization.id, %{
                 product_id: hostile_product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert %{product_id: ["does not belong to this organization"]} = errors_on(changeset)
    end

    test "rejects a gtin that fails the GS1 check digit" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000011",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50
               })

      assert %{gtin: ["is not a valid GTIN"]} = errors_on(changeset)
    end

    test "rejects dispatching the same batch_no for the same product to the same site twice" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      attrs = %{
        product_id: product.id,
        site_id: site.id,
        gtin: "00614141000012",
        batch_no: "LOT-DUP",
        expiry_date: ~D[2027-01-01],
        quantity: 50
      }

      assert {:ok, _batch} = Batches.create_batch(organization.id, attrs)
      assert {:error, changeset} = Batches.create_batch(organization.id, attrs)

      assert %{batch_no: ["has already been dispatched to this site"]} = errors_on(changeset)
    end

    test "allows the same batch_no for the same product across different sites" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site_a = site_fixture(%{organization_id: organization.id})
      site_b = site_fixture(%{organization_id: organization.id})

      common_attrs = %{
        product_id: product.id,
        gtin: "00614141000012",
        batch_no: "LOT-SPLIT",
        expiry_date: ~D[2027-01-01],
        quantity: 10
      }

      assert {:ok, _batch_a} =
               Batches.create_batch(organization.id, Map.put(common_attrs, :site_id, site_a.id))

      assert {:ok, _batch_b} =
               Batches.create_batch(organization.id, Map.put(common_attrs, :site_id, site_b.id))
    end
  end

  describe "receive_batch/2" do
    test "stamps approver_id and received_at" do
      organization = organization_fixture()
      user = user_fixture(%{organization_id: organization.id})
      batch = batch_fixture(%{organization_id: organization.id, pending: true})

      assert is_nil(batch.approver_id)
      assert is_nil(batch.received_at)

      assert {:ok, received} = Batches.receive_batch(batch, user.id)
      assert received.approver_id == user.id
      assert %DateTime{} = received.received_at
    end
  end

  describe "list_batches/1" do
    test "only returns batches for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      batch_a = batch_fixture(%{organization_id: organization_a.id})
      batch_fixture(%{organization_id: organization_b.id})

      assert [%Batch{id: id}] = Batches.list_batches(organization_a.id)
      assert id == batch_a.id
    end
  end

  describe "list_pending_batches/1" do
    test "returns only batches where received_at is nil" do
      organization = organization_fixture()
      pending = batch_fixture(%{organization_id: organization.id, pending: true})
      _active = batch_fixture(%{organization_id: organization.id})

      assert [%Batch{id: id}] = Batches.list_pending_batches(organization.id)
      assert id == pending.id
    end

    test "only returns pending batches for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      batch_fixture(%{organization_id: organization_a.id, pending: true})
      batch_fixture(%{organization_id: organization_b.id, pending: true})

      assert [_] = Batches.list_pending_batches(organization_a.id)
    end
  end

  describe "total_available_stock/3" do
    test "returns 0 when no batches exist for the site and product" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert Batches.total_available_stock(organization.id, site.id, product.id) === 0
    end

    test "sums remaining_quantity of approved batches and returns an integer" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 10,
        remaining_quantity: 10
      })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 20,
        remaining_quantity: 15
      })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 50,
        remaining_quantity: 50,
        pending: true
      })

      total = Batches.total_available_stock(organization.id, site.id, product.id)
      assert total === 25
      assert is_integer(total)
    end
  end

  describe "find_approved_batches_by_gtin/3" do
    test "finds an approved batch by gtin across the whole org when no site_id is given" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      gtin = unique_gtin()

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          gtin: gtin
        })

      assert {:ok, [found]} = Batches.find_approved_batches_by_gtin(organization.id, gtin)
      assert found.id == batch.id
    end
  end

  describe "find_pending_batch/4" do
    test "finds a pending batch by gtin and batch_no across the whole org when no site_id is given" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      gtin = unique_gtin()

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          gtin: gtin,
          batch_no: "LOT-NO-OPTS",
          pending: true
        })

      assert {:ok, found} = Batches.find_pending_batch(organization.id, gtin, "LOT-NO-OPTS")
      assert found.id == batch.id
    end
  end

  describe "get_batch!/2" do
    test "raises when the batch belongs to a different organization" do
      other_organization = organization_fixture()
      batch = batch_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Batches.get_batch!(other_organization.id, batch.id)
      end
    end
  end

  describe "fefo_batches/3" do
    test "picks active batches with stock, soonest expiry first" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      soon_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: ~D[2026-08-01]
        })

      later_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: ~D[2027-01-01]
        })

      assert {:ok, batches} =
               Repo.transaction(fn ->
                 Batches.fefo_batches(organization.id, site.id, product.id)
               end)

      assert [%{id: id1}, %{id: id2}] = batches
      assert id1 == soon_batch.id
      assert id2 == later_batch.id
    end

    test "skips a batch at a different site, even with an earlier expiry" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      other_site = site_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: other_site.id,
        product_id: product.id,
        expiry_date: ~D[2026-08-15]
      })

      matching_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: ~D[2027-01-01]
        })

      assert {:ok, batches} =
               Repo.transaction(fn ->
                 Batches.fefo_batches(organization.id, site.id, product.id)
               end)

      assert [%{id: id}] = batches
      assert id == matching_batch.id
    end

    test "skips a batch with no remaining stock" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        remaining_quantity: 0
      })

      assert {:ok, []} =
               Repo.transaction(fn ->
                 Batches.fefo_batches(organization.id, site.id, product.id)
               end)
    end

    test "skips a batch with no approver_id (not yet received)" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        pending: true
      })

      assert {:ok, []} =
               Repo.transaction(fn ->
                 Batches.fefo_batches(organization.id, site.id, product.id)
               end)
    end

    test "returns empty when no batch exists for that site/product" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, []} =
               Repo.transaction(fn ->
                 Batches.fefo_batches(organization.id, site.id, product.id)
               end)
    end

    test "raises if called outside a transaction" do
      assert_raise RuntimeError,
                   "Batches.fefo_batches/3 must be called within a Repo.transaction/1 to safely lock stock",
                   fn ->
                     Batches.fefo_batches(1, 1, 1)
                   end
    end
  end

  describe "decrement_remaining_quantity/2" do
    test "decrements remaining_quantity by the given amount" do
      batch = batch_fixture(%{quantity: 50})

      assert {:ok, %Batch{remaining_quantity: 40}} =
               Batches.decrement_remaining_quantity(batch, 10)
    end

    test "rejects a decrement that would take remaining_quantity below zero" do
      batch = batch_fixture(%{quantity: 5})

      assert {:error, changeset} = Batches.decrement_remaining_quantity(batch, 10)
      assert %{remaining_quantity: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end
  end
end
