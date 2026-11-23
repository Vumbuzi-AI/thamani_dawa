defmodule ThamaniDawa.BatchesTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GS1.Sscc

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

    test "accepts a missing supplier_id for an inter-site transfer" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, %Batch{supplier_id: nil}} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50
               })
    end

    test "accepts an explicit nil supplier_id for an inter-site transfer" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, %Batch{supplier_id: nil}} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 supplier_id: nil,
                 gtin: "00614141000012",
                 batch_no: "LOT-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50
               })
    end

    test "rejects a supplier_id that belongs to a different organization without inserting stock" do
      organization = organization_fixture()
      other_org = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      hostile_supplier = supplier_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 supplier_id: hostile_supplier.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert %{supplier_id: ["does not belong to this organization"]} = errors_on(changeset)
      assert Batches.list_batches(organization.id) == []
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

    test "rejects a supplier_id that belongs to a different organization" do
      organization = organization_fixture()
      other_org = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      hostile_supplier = supplier_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 supplier_id: hostile_supplier.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert %{supplier_id: ["does not belong to this organization"]} = errors_on(changeset)
    end

    test "accepts a supplier_id that belongs to the same organization" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      supplier = supplier_fixture(%{organization_id: organization.id})

      assert {:ok, batch} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 supplier_id: supplier.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert batch.supplier_id == supplier.id
    end

    test "allows omitting supplier_id entirely (e.g. an inter-site transfer)" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, batch} =
               Batches.create_batch(organization.id, %{
                 product_id: product.id,
                 site_id: site.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert is_nil(batch.supplier_id)
    end

    test "accepts a blank-string supplier_id, matching a form select's 'no supplier' option" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, batch} =
               Batches.create_batch(organization.id, %{
                 "product_id" => to_string(product.id),
                 "site_id" => to_string(site.id),
                 "supplier_id" => "",
                 "gtin" => "00614141000012",
                 "batch_no" => "LOT-BLANK-SUPPLIER",
                 "expiry_date" => "2027-01-01",
                 "quantity" => "10"
               })

      assert is_nil(batch.supplier_id)
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

      assert %{batch_no: ["has already been dispatched to this site in this status"]} =
               errors_on(changeset)
    end

    test "allows the same batch_no for the same product at the same site in a different status" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      attrs = %{
        product_id: product.id,
        site_id: site.id,
        gtin: "00614141000012",
        batch_no: "LOT-SPLIT",
        expiry_date: ~D[2027-01-01],
        quantity: 8
      }

      assert {:ok, _active} = Batches.create_batch(organization.id, attrs)

      assert {:ok, _quarantined} =
               Batches.create_batch(
                 organization.id,
                 Map.merge(attrs, %{quantity: 2, status: :quarantined})
               )
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

  describe "receive_into_org_stock/2" do
    test "creates an org-level batch with no site_id" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})

      assert {:ok, %Batch{site_id: nil} = batch} =
               Batches.receive_into_org_stock(organization.id, %{
                 product_id: product.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-ORG-1",
                 expiry_date: ~D[2027-01-01],
                 quantity: 50
               })

      assert batch.remaining_quantity == 50
    end

    test "requires gtin, batch_no, expiry_date, quantity, and product_id (but not site_id)" do
      organization = organization_fixture()
      assert {:error, changeset} = Batches.receive_into_org_stock(organization.id, %{})

      assert %{
               gtin: ["can't be blank"],
               batch_no: ["can't be blank"],
               expiry_date: ["can't be blank"],
               quantity: ["can't be blank"],
               product_id: ["can't be blank"]
             } = errors_on(changeset)

      refute Map.has_key?(errors_on(changeset), :site_id)
    end

    test "rejects a product_id that belongs to a different organization" do
      organization = organization_fixture()
      other_org = organization_fixture()
      hostile_product = product_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Batches.receive_into_org_stock(organization.id, %{
                 product_id: hostile_product.id,
                 gtin: "00614141000012",
                 batch_no: "LOT-ORG-X",
                 expiry_date: ~D[2027-01-01],
                 quantity: 10
               })

      assert %{product_id: ["does not belong to this organization"]} = errors_on(changeset)
    end

    test "rejects recording the same batch_no twice for the same product as org stock" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})

      attrs = %{
        product_id: product.id,
        gtin: "00614141000012",
        batch_no: "LOT-ORG-DUP",
        expiry_date: ~D[2027-01-01],
        quantity: 50
      }

      assert {:ok, _batch} = Batches.receive_into_org_stock(organization.id, attrs)
      assert {:error, changeset} = Batches.receive_into_org_stock(organization.id, attrs)

      assert %{batch_no: ["already recorded as org stock for this product"]} =
               errors_on(changeset)
    end
  end

  describe "stock_summary_by_product/3" do
    test "excludes undispatched (org-level) batches from total_remaining" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 10,
        remaining_quantity: 10
      })

      org_batch_fixture(%{
        organization_id: organization.id,
        product_id: product.id,
        quantity: 100
      })

      summary = Batches.stock_summary_by_product(organization.id, [product.id])

      assert summary[product.id].total_remaining == 10
      assert summary[product.id].batch_count == 1
    end
  end

  describe "undispatched_summary_by_product/2" do
    test "returns the org-wide undispatched total regardless of a site filter" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 10,
        remaining_quantity: 10
      })

      org_batch_fixture(%{
        organization_id: organization.id,
        product_id: product.id,
        quantity: 100
      })

      summary = Batches.undispatched_summary_by_product(organization.id, [product.id])

      assert summary[product.id] == 100
    end

    test "returns nothing for a product with no undispatched stock" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, product_id: product.id})

      assert Batches.undispatched_summary_by_product(organization.id, [product.id]) == %{}
    end
  end

  describe "list_undispatched_batches_for_product/2" do
    test "returns org-level batches but not dispatched ones" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})

      org_batch = org_batch_fixture(%{organization_id: organization.id, product_id: product.id})
      batch_fixture(%{organization_id: organization.id, product_id: product.id})

      assert [%Batch{id: id}] =
               Batches.list_undispatched_batches_for_product(organization.id, product.id)

      assert id == org_batch.id
    end

    test "excludes an org batch once fully dispatched" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      org_batch = org_batch_fixture(%{organization_id: organization.id, product_id: product.id})

      assert {:ok, _dispatched} = Batches.dispatch_to_site(org_batch, site.id)

      assert Batches.list_undispatched_batches_for_product(organization.id, product.id) == []
    end
  end

  describe "dispatch_to_site/2 and /3" do
    test "creates a new site-bound batch linked back via source_batch_id" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 30
        })

      assert {:ok, dispatched} = Batches.dispatch_to_site(org_batch, site.id)

      assert dispatched.site_id == site.id
      assert dispatched.source_batch_id == org_batch.id
      assert dispatched.quantity == 30
      assert dispatched.remaining_quantity == 30
      assert is_nil(dispatched.approver_id)
      assert is_nil(dispatched.received_at)
    end

    test "zeroes out the org batch's remaining_quantity" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 30
        })

      assert {:ok, _dispatched} = Batches.dispatch_to_site(org_batch, site.id)

      assert Batches.get_batch!(organization.id, org_batch.id).remaining_quantity == 0
    end

    test "can dispatch part of a warehouse batch to different sites" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      first_site = site_fixture(%{organization_id: organization.id})
      second_site = site_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 100
        })

      assert {:ok, first_dispatch} = Batches.dispatch_to_site(org_batch, first_site.id, 40)
      assert first_dispatch.site_id == first_site.id
      assert first_dispatch.quantity == 40
      assert Batches.get_batch!(organization.id, org_batch.id).remaining_quantity == 60

      remaining_org_batch = Batches.get_batch!(organization.id, org_batch.id)

      assert {:ok, second_dispatch} =
               Batches.dispatch_to_site(remaining_org_batch, second_site.id, 60)

      assert second_dispatch.site_id == second_site.id
      assert second_dispatch.quantity == 60
      assert Batches.get_batch!(organization.id, org_batch.id).remaining_quantity == 0
    end

    test "rejects dispatching a batch that already has a site" do
      batch = batch_fixture()

      assert Batches.dispatch_to_site(batch, batch.site_id) == {:error, :already_dispatched}
    end

    test "rejects dispatching a batch with nothing left" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 30,
          remaining_quantity: 0
        })

      assert Batches.dispatch_to_site(org_batch, site.id) == {:error, :nothing_to_dispatch}
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
          expiry_date: ~D[2099-01-01]
        })

      later_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: ~D[2099-02-01]
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
        expiry_date: ~D[2098-12-15]
      })

      matching_batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          expiry_date: ~D[2099-02-01]
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

  describe "list_batches_paginated/4 site filter" do
    setup do
      admin = user_fixture()
      org_id = admin.organization_id

      # Two sites, one batch each, so a working filter has to actually discriminate.
      site = site_fixture(%{organization_id: org_id})
      other_site = site_fixture(%{organization_id: org_id})
      batch = batch_fixture(%{organization_id: org_id, site_id: site.id})
      other_batch = batch_fixture(%{organization_id: org_id, site_id: other_site.id})

      {:ok,
       org_id: org_id,
       site: site,
       batch: batch,
       other_batch: other_batch,
       other_site_ids: [other_site.id]}
    end

    test "accepts the site id as a string", %{org_id: org_id, site: site, batch: batch} do
      page = Batches.list_batches_paginated(org_id, 1, nil, site: to_string(site.id))
      assert Enum.map(page.entries, & &1.id) == [batch.id]
    end

    test "accepts the site id as an integer", %{org_id: org_id, site: site, batch: batch} do
      # Used to fall through to the catch-all clause and silently return every
      # site's batches — a fail-open filter.
      page = Batches.list_batches_paginated(org_id, 1, nil, site: site.id)
      assert Enum.map(page.entries, & &1.id) == [batch.id]
    end

    test "ignores a malformed site filter instead of raising", %{
      org_id: org_id,
      batch: batch,
      other_batch: other_batch
    } do
      page = Batches.list_batches_paginated(org_id, 1, nil, site: "abc")

      assert Enum.sort(Enum.map(page.entries, & &1.id)) == Enum.sort([batch.id, other_batch.id])
    end

    test "a malformed site filter still respects the permitted-site scoping", %{
      org_id: org_id,
      other_site_ids: other_site_ids,
      other_batch: other_batch
    } do
      page = Batches.list_batches_paginated(org_id, 1, other_site_ids, site: "abc")

      assert Enum.map(page.entries, & &1.id) == [other_batch.id]
    end
  end

  describe "inbound sscc capture" do
    setup do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})

      base_attrs = %{
        "product_id" => product.id,
        "site_id" => site.id,
        "gtin" => "00614141000012",
        "batch_no" => "LOT-SSCC",
        "expiry_date" => ~D[2027-01-01],
        "quantity" => 10
      }

      %{organization: organization, base_attrs: base_attrs}
    end

    test "stores a scanned inbound SSCC on the batch", %{organization: org, base_attrs: attrs} do
      assert {:ok, %Batch{sscc: sscc}} =
               Batches.create_batch(org.id, Map.put(attrs, "sscc", "006141411234567890"))

      assert sscc == "006141411234567890"
    end

    test "rejects an SSCC that is not 18 digits", %{organization: org, base_attrs: attrs} do
      assert {:error, changeset} = Batches.create_batch(org.id, Map.put(attrs, "sscc", "12345"))

      assert %{sscc: ["must be an 18-digit SSCC from the case label"]} = errors_on(changeset)
    end

    test "rejects an SSCC with a bad check digit", %{organization: org, base_attrs: attrs} do
      assert {:error, changeset} =
               Batches.create_batch(org.id, Map.put(attrs, "sscc", "006141411234567894"))

      assert %{sscc: ["check digit does not match, rescan the case label"]} =
               errors_on(changeset)
    end

    test "a blank SSCC is stored as nil instead of an empty string", %{
      organization: org,
      base_attrs: attrs
    } do
      assert {:ok, %Batch{sscc: nil}} = Batches.create_batch(org.id, Map.put(attrs, "sscc", "  "))
    end
  end

  describe "break_into_mini_ssccs/3" do
    test "fully disaggregates an unserialized batch, sweeping leftover into a remainder carton" do
      %{batch: batch, user: user, organization: organization} =
        splittable_batch(%{"quantity" => 60, "remaining_quantity" => 60, "serials" => []})

      before = Repo.get!(ThamaniDawa.Organizations.Organization, organization.id).next_sscc_serial

      assert {:ok, [first, second, remainder]} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [%{quantity: 25, serials: ["ignored"]}, %{quantity: 15, serials: []}],
                 user.id
               )

      parent = Batches.get_batch!(organization.id, batch.id)
      assert parent.remaining_quantity == 0
      assert parent.quantity == 60
      assert parent.serials == []
      assert parent.status == :disaggregated

      assert first.quantity == 25
      assert first.remaining_quantity == 25
      assert second.quantity == 15
      assert remainder.quantity == 20
      assert first.serials == []
      assert second.serials == []
      assert remainder.serials == []
      assert first.quantity + second.quantity + remainder.quantity == 60
      assert first.batch_no == "LOT123-S1"
      assert second.batch_no == "LOT123-S2"
      assert remainder.batch_no == "LOT123-S3"
      assert first.source_batch_id == batch.id
      assert remainder.source_batch_id == batch.id
      assert first.zone == :storage
      assert first.status == :active
      assert first.received_at
      assert first.approver_id == user.id
      assert second.approver_id == user.id
      assert first.product_id == batch.product_id
      assert first.site_id == batch.site_id
      assert first.gtin == batch.gtin
      assert first.manufacturer == "Acme"
      assert first.manufacture_date == ~D[2026-01-15]
      assert first.expiry_date == batch.expiry_date
      assert first.supplier_id == batch.supplier_id
      assert first.goods_receipt_id == batch.goods_receipt_id
      assert Decimal.equal?(first.cost_per_unit, Decimal.new("12.50"))

      after_serial =
        Repo.get!(ThamaniDawa.Organizations.Organization, organization.id).next_sscc_serial

      assert after_serial == before

      requests = ThamaniDawa.GS1.MemberApiStub.create_requests()
      assert length(requests) == 3

      assert Enum.all?(requests, fn request ->
               request["batch_info"] == [
                 %{
                   "gtin" => batch.gtin,
                   "batch" => "LOT123",
                   "production_date" => "2026-01-15",
                   "expiry_date" => "2027-06-01"
                 }
               ]
             end)

      ssccs = [first.sscc, second.sscc, remainder.sscc]
      assert Enum.uniq(ssccs) == ssccs
      assert Enum.all?(ssccs, &valid_sscc?/1)
    end

    test "distributes all of a serialized parent's serials across children and remainder" do
      serials = ["SN1", "SN2", "SN3", "SN4"]

      %{batch: batch, user: user, organization: organization} =
        splittable_batch(%{"quantity" => 4, "remaining_quantity" => 4, "serials" => serials})

      assert {:ok, [first, second, remainder]} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [
                   %{quantity: 2, serials: ["SN1", "SN3"]},
                   %{quantity: 1, serials: ["SN4"]}
                 ],
                 user.id
               )

      parent = Batches.get_batch!(organization.id, batch.id)
      assert parent.remaining_quantity == 0
      assert parent.serials == []
      assert parent.status == :disaggregated
      assert first.serials == ["SN1", "SN3"]
      assert second.serials == ["SN4"]
      assert remainder.serials == ["SN2"]

      all = first.serials ++ second.serials ++ remainder.serials
      assert Enum.sort(all) == Enum.sort(serials)
      assert length(Enum.uniq(all)) == 4
    end

    test "rejects breaking an already-disaggregated or empty parent" do
      %{batch: batch, user: user, organization: organization} = splittable_batch()

      assert {:ok, _children} =
               Batches.break_into_mini_ssccs(batch, [%{quantity: 10}], user.id)

      parent = Batches.get_batch!(organization.id, batch.id)
      assert parent.status == :disaggregated
      assert parent.remaining_quantity == 0

      assert {:error, :not_breakable} =
               Batches.break_into_mini_ssccs(parent, [%{quantity: 5}], user.id)
    end

    test "rejects an empty split, a non-positive quantity, and too large a split" do
      %{batch: batch, user: user, organization: organization} = splittable_batch()

      assert {:error, :no_groups} = Batches.break_into_mini_ssccs(batch, [], user.id)

      assert {:error, :invalid_group_quantity} =
               Batches.break_into_mini_ssccs(batch, [%{quantity: 0}], user.id)

      assert {:error, :invalid_group_quantity} =
               Batches.break_into_mini_ssccs(batch, [%{quantity: -5}], user.id)

      assert {:error, :insufficient_quantity} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [%{quantity: 50}, %{quantity: 20}],
                 user.id
               )

      assert Batches.get_batch!(organization.id, batch.id).remaining_quantity == 60
    end

    test "rejects serials that do not match the group or the parent" do
      %{batch: batch, user: user, organization: organization} =
        splittable_batch(%{
          "quantity" => 3,
          "remaining_quantity" => 3,
          "serials" => ["SN1", "SN2", "SN3"]
        })

      assert {:error, :invalid_serials} =
               Batches.break_into_mini_ssccs(batch, [%{quantity: 2, serials: ["SN1"]}], user.id)

      assert {:error, :invalid_serials} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [%{quantity: 1, serials: ["NOPE"]}],
                 user.id
               )

      assert {:error, :invalid_serials} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [
                   %{quantity: 1, serials: ["SN1"]},
                   %{quantity: 1, serials: ["SN1"]}
                 ],
                 user.id
               )

      parent = Batches.get_batch!(organization.id, batch.id)
      assert parent.remaining_quantity == 3
      assert parent.serials == ["SN1", "SN2", "SN3"]
    end

    test "suffixes each carton in a single break, remainder last" do
      %{batch: batch, user: user} = splittable_batch()

      assert {:ok, [first, second, remainder]} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [%{quantity: 10}, %{quantity: 10}],
                 user.id
               )

      assert first.batch_no == "LOT123-S1"
      assert second.batch_no == "LOT123-S2"
      assert remainder.batch_no == "LOT123-S3"
      assert remainder.quantity == 40
    end

    test "splitting a mini-SSCC chains source_batch_id and suffixes" do
      %{batch: batch, user: user, organization: organization} =
        splittable_batch(%{
          "quantity" => 4,
          "remaining_quantity" => 4,
          "serials" => ["SN1", "SN2", "SN3", "SN4"]
        })

      assert {:ok, [child, _parent_remainder]} =
               Batches.break_into_mini_ssccs(
                 batch,
                 [%{quantity: 2, serials: ["SN1", "SN2"]}],
                 user.id
               )

      assert child.batch_no == "LOT123-S1"
      assert child.source_batch_id == batch.id

      assert {:ok, [grandchild, child_remainder]} =
               Batches.break_into_mini_ssccs(
                 child,
                 [%{quantity: 1, serials: ["SN1"]}],
                 user.id
               )

      assert grandchild.batch_no == "LOT123-S1-S1"
      assert grandchild.source_batch_id == child.id
      assert grandchild.serials == ["SN1"]
      assert grandchild.sscc != child.sscc
      assert child_remainder.batch_no == "LOT123-S1-S2"
      assert child_remainder.serials == ["SN2"]

      reloaded_child = Batches.get_batch!(organization.id, child.id)
      assert reloaded_child.remaining_quantity == 0
      assert reloaded_child.serials == []
      assert reloaded_child.status == :disaggregated
    end

    test "a missing parent rolls back as not_found" do
      %{batch: batch, user: user} = splittable_batch()
      Repo.delete!(batch)

      assert {:error, :not_found} =
               Batches.break_into_mini_ssccs(batch, [%{quantity: 1}], user.id)
    end

    defp splittable_batch(overrides \\ %{}) do
      organization = organization_with_prefix_fixture()
      product = product_fixture(%{organization_id: organization.id})

      site =
        site_fixture(%{organization_id: organization.id, activities: [:distribution]})

      supplier = supplier_fixture(%{organization_id: organization.id})
      user = user_fixture(%{organization_id: organization.id})

      attrs =
        Map.merge(
          %{
            "product_id" => product.id,
            "site_id" => site.id,
            "supplier_id" => supplier.id,
            "gtin" => product.gtin,
            "batch_no" => "LOT123",
            "manufacturer" => "Acme",
            "manufacture_date" => ~D[2026-01-15],
            "expiry_date" => ~D[2027-06-01],
            "quantity" => 60,
            "remaining_quantity" => 60,
            "cost_per_unit" => "12.50",
            "serials" => [],
            "sscc" => "006141411234567890"
          },
          overrides
        )

      {:ok, batch} = Batches.create_batch(organization.id, attrs)
      {:ok, batch} = Batches.receive_batch(batch, user.id)

      %{organization: organization, product: product, site: site, user: user, batch: batch}
    end

    defp valid_sscc?(sscc) do
      String.match?(sscc, ~r/^\d{18}$/) and
        Integer.to_string(Sscc.mod10_check_digit(String.slice(sscc, 0..-2//1))) ==
          String.slice(sscc, -1, 1)
    end
  end

  describe "break_logistic_unit/3" do
    alias ThamaniDawa.Batches.LogisticUnit
    import Ecto.Query

    test "breaks a single-line case into child units and retires the unit" do
      %{organization: org, user: user, batch: batch} = splittable_batch()
      unit = link_case_unit(org.id, batch)

      assert {:ok, [%{children: children}]} =
               Batches.break_logistic_unit(
                 unit,
                 [%{batch_id: batch.id, groups: [%{quantity: 25}]}],
                 user.id
               )

      assert length(children) == 2
      assert Enum.all?(children, & &1.logistic_unit_id)

      child_units =
        ThamaniDawa.Repo.all(from u in LogisticUnit, where: u.parent_logistic_unit_id == ^unit.id)

      assert length(child_units) == 2
      assert Enum.all?(child_units, &(&1.source == :minted))

      assert ThamaniDawa.Repo.get!(LogisticUnit, unit.id).status == :disaggregated

      line = Batches.get_batch!(org.id, batch.id)
      assert line.status == :disaggregated
      assert line.remaining_quantity == 0
    end

    test "breaks a mixed case per line, one product per child" do
      %{organization: org, user: user, batch: batch_a, site: site} = splittable_batch()
      product_b = product_fixture(%{organization_id: org.id})

      {:ok, batch_b} =
        Batches.create_batch(org.id, %{
          "product_id" => product_b.id,
          "site_id" => site.id,
          "gtin" => product_b.gtin,
          "batch_no" => "LOTB",
          "expiry_date" => ~D[2027-06-01],
          "quantity" => 40,
          "remaining_quantity" => 40,
          "serials" => [],
          "sscc" => batch_a.sscc
        })

      {:ok, batch_b} = Batches.receive_batch(batch_b, user.id)
      unit = link_case_unit(org.id, batch_a, [batch_b])

      assert {:ok, [result_a, result_b]} =
               Batches.break_logistic_unit(
                 unit,
                 [
                   %{batch_id: batch_a.id, groups: [%{quantity: 20}]},
                   %{batch_id: batch_b.id, groups: [%{quantity: 10}]}
                 ],
                 user.id
               )

      assert Enum.all?(result_a.children, &(&1.product_id == batch_a.product_id))
      assert Enum.all?(result_b.children, &(&1.product_id == product_b.id))
      assert length(result_a.children) == 2
      assert length(result_b.children) == 2

      assert ThamaniDawa.Repo.get!(LogisticUnit, unit.id).status == :disaggregated
      assert Batches.get_batch!(org.id, batch_a.id).status == :disaggregated
      assert Batches.get_batch!(org.id, batch_b.id).status == :disaggregated
    end

    test "rejects breaking an already-disaggregated unit" do
      %{organization: org, user: user, batch: batch} = splittable_batch()
      unit = link_case_unit(org.id, batch)

      assert {:ok, _} =
               Batches.break_logistic_unit(
                 unit,
                 [%{batch_id: batch.id, groups: [%{quantity: 10}]}],
                 user.id
               )

      assert {:error, :not_breakable} =
               Batches.break_logistic_unit(
                 unit,
                 [%{batch_id: batch.id, groups: [%{quantity: 5}]}],
                 user.id
               )
    end

    defp link_case_unit(org_id, primary, others \\ []) do
      {:ok, unit} =
        %LogisticUnit{}
        |> LogisticUnit.changeset(%{
          organization_id: org_id,
          sscc: primary.sscc,
          kind: :case,
          source: :inbound,
          site_id: primary.site_id
        })
        |> ThamaniDawa.Repo.insert()

      for b <- [primary | others] do
        b |> Ecto.Changeset.change(logistic_unit_id: unit.id) |> ThamaniDawa.Repo.update!()
      end

      unit
    end
  end
end
