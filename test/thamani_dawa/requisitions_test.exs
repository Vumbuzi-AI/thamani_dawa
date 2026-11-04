defmodule ThamaniDawa.RequisitionsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.Requisitions.Requisition

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.RequisitionsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_requisition/3" do
    test "requires site_id, product_id, and quantity" do
      organization = organization_fixture()
      user = user_fixture(%{organization_id: organization.id})

      assert {:error, changeset} = Requisitions.create_requisition(organization.id, user.id, %{})

      assert %{
               site_id: ["can't be blank"],
               product_id: ["can't be blank"],
               quantity: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires quantity to be positive" do
      organization = organization_fixture()
      user = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Requisitions.create_requisition(organization.id, user.id, %{
                 site_id: site.id,
                 product_id: product.id,
                 quantity: 0
               })

      assert %{quantity: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "stamps organization_id and requested_by_id from the caller, not attrs" do
      organization = organization_fixture()
      other_organization = organization_fixture()
      user = user_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      assert {:ok, %Requisition{} = requisition} =
               Requisitions.create_requisition(organization.id, user.id, %{
                 site_id: site.id,
                 product_id: product.id,
                 quantity: 10,
                 organization_id: other_organization.id
               })

      assert requisition.organization_id == organization.id
      assert requisition.requested_by_id == user.id
      assert requisition.status == :pending
    end

    test "rejects site, product, and requester records from another organization" do
      organization = organization_fixture()
      other_organization = organization_fixture()
      other_user = user_fixture(%{organization_id: other_organization.id})
      other_site = site_fixture(%{organization_id: other_organization.id})
      other_product = product_fixture(%{organization_id: other_organization.id})

      assert {:error, changeset} =
               Requisitions.create_requisition(organization.id, other_user.id, %{
                 site_id: other_site.id,
                 product_id: other_product.id,
                 quantity: 10
               })

      assert %{
               site_id: ["does not belong to this organization"],
               product_id: ["does not belong to this organization"],
               requested_by_id: ["does not belong to this organization"]
             } = errors_on(changeset)
    end
  end

  describe "approve_requisition/3" do
    test "moves a pending requisition to approved and stamps the reviewer" do
      requisition = requisition_fixture()
      reviewer = user_fixture(%{organization_id: requisition.organization_id})

      assert {:ok, %Requisition{} = approved} =
               Requisitions.approve_requisition(
                 requisition.organization_id,
                 requisition.id,
                 reviewer.id
               )

      assert approved.status == :approved
      assert approved.reviewed_by_id == reviewer.id
      assert approved.reviewed_at
    end

    test "sets needs_reorder when organization stock can't cover the request" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      org_batch_fixture(%{organization_id: organization.id, product_id: product.id, quantity: 5})

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      assert {:ok, %Requisition{needs_reorder: true}} =
               Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)
    end

    test "does not set needs_reorder when organization stock covers the request" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      org_batch_fixture(%{organization_id: organization.id, product_id: product.id, quantity: 20})

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      assert {:ok, %Requisition{needs_reorder: false}} =
               Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)
    end

    test "fails to re-approve a requisition that is not pending" do
      requisition = approved_requisition_fixture()
      reviewer = user_fixture(%{organization_id: requisition.organization_id})

      assert {:error, :not_pending} =
               Requisitions.approve_requisition(
                 requisition.organization_id,
                 requisition.id,
                 reviewer.id
               )
    end
  end

  describe "reject_requisition/4" do
    test "requires a rejection reason" do
      requisition = requisition_fixture()
      reviewer = user_fixture(%{organization_id: requisition.organization_id})

      assert {:error, changeset} =
               Requisitions.reject_requisition(
                 requisition.organization_id,
                 requisition.id,
                 reviewer.id,
                 nil
               )

      assert %{rejection_reason: ["can't be blank"]} = errors_on(changeset)
    end

    test "moves a pending requisition to rejected with the given reason" do
      requisition = requisition_fixture()
      reviewer = user_fixture(%{organization_id: requisition.organization_id})

      assert {:ok, %Requisition{} = rejected} =
               Requisitions.reject_requisition(
                 requisition.organization_id,
                 requisition.id,
                 reviewer.id,
                 "Out of budget this month"
               )

      assert rejected.status == :rejected
      assert rejected.rejection_reason == "Out of budget this month"
    end
  end

  describe "fulfill_requisition/4 and fulfilled_quantity/1" do
    test "dispatches org stock against an approved requisition and marks it fulfilled" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 20
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)

      assert {:ok, %Requisition{} = fulfilled} =
               Requisitions.fulfill_requisition(organization.id, approved.id, org_batch, 10)

      assert fulfilled.status == :fulfilled
      assert Requisitions.fulfilled_quantity(requisition.id) == 10
    end

    test "accumulates across multiple partial fulfillments (from distinct org batches) until fully fulfilled" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      org_batch_a =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 20
        })

      org_batch_b =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 20
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)

      assert {:ok, %Requisition{status: :partially_fulfilled}} =
               Requisitions.fulfill_requisition(organization.id, approved.id, org_batch_a, 4)

      assert Requisitions.fulfilled_quantity(requisition.id) == 4

      assert {:ok, %Requisition{status: :fulfilled}} =
               Requisitions.fulfill_requisition(organization.id, approved.id, org_batch_b, 6)

      assert Requisitions.fulfilled_quantity(requisition.id) == 10
    end

    test "fails when the requisition is not approved" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 20
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      assert {:error, :not_approved} =
               Requisitions.fulfill_requisition(organization.id, requisition.id, org_batch, 10)
    end

    test "propagates insufficient_quantity from Batches.dispatch_to_site/3" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{organization_id: organization.id, product_id: product.id, quantity: 5})

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)

      assert {:error, :insufficient_quantity} =
               Requisitions.fulfill_requisition(organization.id, approved.id, org_batch, 10)
    end

    test "rejects a batch from another organization" do
      organization = organization_fixture()
      other_organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      other_product = product_fixture(%{organization_id: other_organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      other_batch =
        org_batch_fixture(%{
          organization_id: other_organization.id,
          product_id: other_product.id,
          quantity: 10
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)

      assert {:error, :batch_not_found} =
               Requisitions.fulfill_requisition(organization.id, approved.id, other_batch, 10)
    end

    test "rejects a batch for a different product" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      other_product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      other_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: other_product.id,
          quantity: 10
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)

      assert {:error, :product_mismatch} =
               Requisitions.fulfill_requisition(organization.id, approved.id, other_batch, 10)
    end

    test "rejects fulfillment beyond the requisition's remaining quantity" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      reviewer = user_fixture(%{organization_id: organization.id})

      org_batch =
        org_batch_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 20
        })

      requisition =
        requisition_fixture(%{
          organization_id: organization.id,
          product_id: product.id,
          quantity: 10
        })

      {:ok, approved} =
        Requisitions.approve_requisition(organization.id, requisition.id, reviewer.id)

      assert {:error, :exceeds_requested_quantity} =
               Requisitions.fulfill_requisition(organization.id, approved.id, org_batch, 11)

      assert Requisitions.fulfilled_quantity(requisition.id) == 0
    end

    test "returns 0 for a requisition with no fulfillment batches" do
      requisition = requisition_fixture()
      assert Requisitions.fulfilled_quantity(requisition.id) == 0
    end
  end

  describe "needs_reorder?/3" do
    test "is true when available organization stock is exactly short" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      org_batch_fixture(%{organization_id: organization.id, product_id: product.id, quantity: 9})

      assert Requisitions.needs_reorder?(organization.id, product.id, 10)
    end

    test "is false when available organization stock exactly covers the request" do
      organization = organization_fixture()
      product = product_fixture(%{organization_id: organization.id})
      org_batch_fixture(%{organization_id: organization.id, product_id: product.id, quantity: 10})

      refute Requisitions.needs_reorder?(organization.id, product.id, 10)
    end
  end

  describe "multi-tenant isolation" do
    test "get_requisition!/2 raises for a requisition in a different organization" do
      requisition = requisition_fixture()
      other_organization = organization_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Requisitions.get_requisition!(other_organization.id, requisition.id)
      end
    end
  end
end
