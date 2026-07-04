defmodule ThamaniDawa.PrescriptionsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Prescriptions.{DispensedItem, Prescription}

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_prescription/2" do
    test "requires site_id and patient_id" do
      organization = organization_fixture()

      assert {:error, changeset} = Prescriptions.create_prescription(organization.id, %{})
      assert %{site_id: ["can't be blank"], patient_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to pending and scopes to the organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      assert {:ok, %Prescription{} = prescription} =
               Prescriptions.create_prescription(organization.id, %{site_id: site.id, patient_id: patient.id})

      assert prescription.organization_id == organization.id
      assert prescription.status == :pending
    end
  end

  describe "create_prescription_with_items/3" do
    test "creates the header and every item in one transaction" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      assert {:ok, %{prescription: prescription, prescription_items: [item]}} =
               Prescriptions.create_prescription_with_items(
                 organization.id,
                 %{site_id: site.id, patient_id: patient.id},
                 [%{product_id: product.id, quantity_prescribed: 20}]
               )

      assert prescription.site_id == site.id
      assert item.prescription_id == prescription.id
      assert item.quantity_prescribed == 20
    end

    test "rolls back the header when an item is invalid" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Prescriptions.create_prescription_with_items(
                 organization.id,
                 %{site_id: site.id, patient_id: patient.id},
                 [%{}]
               )

      assert %{product_id: ["can't be blank"]} = errors_on(changeset)
      assert Prescriptions.list_prescriptions(organization.id) == []
    end
  end

  describe "dispense_item/5" do
    setup do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      pharmacist = staff_fixture(%{organization_id: organization.id})

      prescription =
        prescription_fixture(%{organization_id: organization.id, site_id: site.id})

      item =
        prescription_item_fixture(%{
          organization_id: organization.id,
          prescription_id: prescription.id,
          product_id: product.id,
          quantity_prescribed: 10
        })

      %{organization: organization, site: site, product: product, pharmacist: pharmacist, prescription: prescription, item: item}
    end

    test "FEFO-picks the soonest-expiring batch at the prescription's own site", ctx do
      soon_batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          site_id: ctx.site.id,
          product_id: ctx.product.id,
          expiry: ~D[2026-08-01],
          quantity: 100
        })

      _later_batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          site_id: ctx.site.id,
          product_id: ctx.product.id,
          expiry: ~D[2027-01-01],
          quantity: 100
        })

      # A batch for the same product sitting at a different site must never
      # be picked (§4.3: "batch must be at the prescription's own site_id").
      _other_site_batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          product_id: ctx.product.id,
          expiry: ~D[2026-01-01],
          quantity: 100
        })

      assert {:ok, %DispensedItem{} = dispensed_item} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 10)

      assert dispensed_item.batch_id == soon_batch.id
      assert dispensed_item.quantity == 10
      assert dispensed_item.pharmacist_id == ctx.pharmacist.id
      assert dispensed_item.is_verified == false
      assert %DateTime{} = dispensed_item.dispensed_at

      updated_batch = Batches.get_batch!(ctx.organization.id, soon_batch.id)
      assert updated_batch.remaining_quantity == 90

      updated_item = Prescriptions.get_prescription_item!(ctx.organization.id, ctx.item.id)
      assert updated_item.quantity_dispensed == 10

      updated_prescription = Prescriptions.get_prescription!(ctx.organization.id, ctx.prescription.id)
      assert updated_prescription.status == :completed
    end

    test "defaults unit_price to the picked batch's own unit_price", ctx do
      batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          site_id: ctx.site.id,
          product_id: ctx.product.id,
          unit_price: Decimal.new("12.50")
        })

      assert {:ok, %DispensedItem{unit_price: unit_price}} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 5)

      assert Decimal.equal?(unit_price, batch.unit_price)
    end

    test "moves the prescription to partially_dispensed on a partial dispense", ctx do
      batch_fixture(%{organization_id: ctx.organization.id, site_id: ctx.site.id, product_id: ctx.product.id})

      assert {:ok, _dispensed_item} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 4)

      updated_prescription = Prescriptions.get_prescription!(ctx.organization.id, ctx.prescription.id)
      assert updated_prescription.status == :partially_dispensed
    end

    test "returns :out_of_stock when no eligible batch exists at that site", ctx do
      assert {:error, :out_of_stock} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 1)
    end

    test "returns :over_dispensed rather than exceeding quantity_prescribed", ctx do
      batch_fixture(%{organization_id: ctx.organization.id, site_id: ctx.site.id, product_id: ctx.product.id})

      assert {:error, :over_dispensed} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 11)

      updated_batch = Batches.list_batches(ctx.organization.id) |> hd()
      assert updated_batch.remaining_quantity == updated_batch.quantity
    end
  end

  describe "verify_dispensed_item/3" do
    setup do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      pharmacist = staff_fixture(%{organization_id: organization.id})

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          gtin: "00614141000012",
          batch_no: "LOT-42"
        })

      prescription = prescription_fixture(%{organization_id: organization.id, site_id: site.id})

      item =
        prescription_item_fixture(%{
          organization_id: organization.id,
          prescription_id: prescription.id,
          product_id: product.id,
          quantity_prescribed: 5
        })

      {:ok, dispensed_item} = Prescriptions.dispense_item(organization.id, item.id, pharmacist.id, 5)

      %{organization: organization, batch: batch, dispensed_item: dispensed_item}
    end

    test "marks is_verified when the scanned code matches the dispensed batch", ctx do
      scanned = "01#{ctx.batch.gtin}10#{ctx.batch.batch_no}"

      assert {:ok, %DispensedItem{is_verified: true}} =
               Prescriptions.verify_dispensed_item(ctx.organization.id, ctx.dispensed_item.id, scanned)
    end

    test "returns :mismatch when the scanned batch/lot doesn't match, leaving is_verified false", ctx do
      scanned = "01#{ctx.batch.gtin}10WRONG-LOT"

      assert {:error, :mismatch} =
               Prescriptions.verify_dispensed_item(ctx.organization.id, ctx.dispensed_item.id, scanned)

      assert %DispensedItem{is_verified: false} =
               ThamaniDawa.Repo.get!(DispensedItem, ctx.dispensed_item.id)
    end
  end
end
