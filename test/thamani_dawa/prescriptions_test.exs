defmodule ThamaniDawa.PrescriptionsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Prescriptions.{Prescription, PrescriptionItem}

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.PatientVisitsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_prescription/2" do
    test "defaults status to pending and scopes to the organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      patient_visit =
        patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      assert {:ok, %Prescription{} = prescription} =
               Prescriptions.create_prescription(organization.id, %{
                 patient_visit_id: patient_visit.id,
                 doctors_note: "Take after meals",
                 source_facility: "General Hospital",
                 referring_doctor: "Dr. Jane Doe",
                 referral_date: ~T[09:00:00],
                 payment_type: "Cash"
               })

      assert prescription.organization_id == organization.id
      assert prescription.patient_visit_id == patient_visit.id
      assert prescription.status == :pending
    end
  end

  describe "create_prescription_for_patient/5" do
    test "creates a PatientVisit and a Prescription in one transaction" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      user = staff_fixture(%{organization_id: organization.id})

      assert {:ok, %Prescription{} = prescription} =
               Prescriptions.create_prescription_for_patient(
                 organization.id,
                 patient.id,
                 site.id,
                 user.id,
                 %{
                   doctors_note: "Take after meals",
                   referring_doctor: "Dr. Jane Doe",
                   payment_type: "Cash"
                 }
               )

      assert prescription.organization_id == organization.id
      assert prescription.status == :pending

      assert not is_nil(prescription.patient_visit_id)

      visit =
        ThamaniDawa.PatientVisits.get_patient_visit!(
          organization.id,
          prescription.patient_visit_id
        )

      assert visit.patient_id == patient.id
      assert visit.site_id == site.id
      assert visit.user_id == user.id
      assert visit.visit_type == :pharmacy
    end
  end

  describe "create_prescription_with_new_patient/5" do
    test "creates a Patient, PatientVisit, and Prescription in one transaction" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = staff_fixture(%{organization_id: organization.id})

      patient_attrs = %{
        full_name: "New Patient Demo",
        age: 25,
        gsrn: 999_999,
        national_id: "12345678",
        phone: "0711223344"
      }

      prescription_attrs = %{
        doctors_note: "Take after meals",
        referring_doctor: "Dr. Jane Doe",
        payment_type: "Cash"
      }

      assert {:ok, %Prescription{} = prescription} =
               Prescriptions.create_prescription_with_new_patient(
                 organization.id,
                 patient_attrs,
                 site.id,
                 user.id,
                 prescription_attrs
               )

      assert prescription.organization_id == organization.id
      assert prescription.status == :pending
      assert not is_nil(prescription.patient_visit_id)

      visit =
        ThamaniDawa.PatientVisits.get_patient_visit!(
          organization.id,
          prescription.patient_visit_id
        )

      assert visit.site_id == site.id
      assert visit.user_id == user.id

      patient = ThamaniDawa.Patients.get_patient!(organization.id, visit.patient_id)
      assert patient.full_name == "New Patient Demo"
    end

    test "rolls back if patient creation fails" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = staff_fixture(%{organization_id: organization.id})

      patient_attrs = %{age: 25, phone: "invalid", gsrn: 999_998}
      prescription_attrs = %{referring_doctor: "Dr. Jane Doe", payment_type: "Cash"}

      patient_count_before = ThamaniDawa.Repo.aggregate(ThamaniDawa.Patients.Patient, :count)

      assert {:error, changeset} =
               Prescriptions.create_prescription_with_new_patient(
                 organization.id,
                 patient_attrs,
                 site.id,
                 user.id,
                 prescription_attrs
               )

      assert changeset.data.__struct__ == ThamaniDawa.Patients.Patient

      assert %{
               full_name: ["can't be blank"],
               phone: ["must be a valid Kenyan phone number (e.g. 0712345678 or +254712345678)"]
             } = errors_on(changeset)

      assert ThamaniDawa.Repo.aggregate(ThamaniDawa.Patients.Patient, :count) ==
               patient_count_before
    end

    test "rolls back patient creation if prescription creation fails" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = staff_fixture(%{organization_id: organization.id})

      patient_attrs = %{full_name: "Rollback Test", age: 25, gsrn: 999_997}
      prescription_attrs = %{}

      patient_count_before = ThamaniDawa.Repo.aggregate(ThamaniDawa.Patients.Patient, :count)

      assert {:error, changeset} =
               Prescriptions.create_prescription_with_new_patient(
                 organization.id,
                 patient_attrs,
                 site.id,
                 user.id,
                 prescription_attrs
               )

      assert changeset.data.__struct__ == ThamaniDawa.Prescriptions.Prescription

      assert %{referring_doctor: ["can't be blank"], payment_type: ["can't be blank"]} =
               errors_on(changeset)

      assert ThamaniDawa.Repo.aggregate(ThamaniDawa.Patients.Patient, :count) ==
               patient_count_before
    end
  end

  describe "list_prescriptions/1" do
    test "returns prescriptions with a patient visit" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      patient_visit1 =
        patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      patient_visit2 =
        patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      prescription1 =
        prescription_fixture(%{
          organization_id: organization.id,
          patient_visit_id: patient_visit1.id
        })

      prescription2 =
        prescription_fixture(%{
          organization_id: organization.id,
          patient_visit_id: patient_visit2.id
        })

      results = Prescriptions.list_prescriptions(organization.id)
      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == prescription1.id && &1.site_id == site.id))
      assert Enum.any?(results, &(&1.id == prescription2.id && &1.site_id == site.id))
    end
  end

  describe "create_prescription_with_items/3" do
    test "creates the header and every item in one transaction" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      patient_visit =
        patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      product = product_fixture(%{organization_id: organization.id})

      assert {:ok, %{prescription: prescription, prescription_items: [item]}} =
               Prescriptions.create_prescription_with_items(
                 organization.id,
                 %{
                   patient_visit_id: patient_visit.id,
                   doctors_note: "Take after meals",
                   source_facility: "General Hospital",
                   referring_doctor: "Dr. Jane Doe",
                   referral_date: ~T[09:00:00],
                   payment_type: "Cash"
                 },
                 [%{product_id: product.id, quantity_prescribed: 20}]
               )

      assert prescription.patient_visit_id == patient_visit.id
      assert item.prescription_id == prescription.id
      assert item.quantity_prescribed == 20
    end

    test "rolls back the header when an item is invalid" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      patient_visit =
        patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      assert {:error, changeset} =
               Prescriptions.create_prescription_with_items(
                 organization.id,
                 %{
                   patient_visit_id: patient_visit.id,
                   doctors_note: "Take after meals",
                   source_facility: "General Hospital",
                   referring_doctor: "Dr. Jane Doe",
                   referral_date: ~T[09:00:00],
                   payment_type: "Cash"
                 },
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
      patient = patient_fixture(%{organization_id: organization.id})

      patient_visit =
        patient_visit_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      prescription =
        prescription_fixture(%{
          organization_id: organization.id,
          patient_visit_id: patient_visit.id
        })

      item =
        prescription_item_fixture(%{
          organization_id: organization.id,
          prescription_id: prescription.id,
          product_id: product.id,
          quantity_prescribed: 10
        })

      %{
        organization: organization,
        site: site,
        product: product,
        pharmacist: pharmacist,
        prescription: prescription,
        item: item
      }
    end

    test "FEFO-picks the soonest-expiring batch at the prescription's own site", ctx do
      soon_batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          site_id: ctx.site.id,
          product_id: ctx.product.id,
          expiry_date: ~D[2026-08-01],
          quantity: 100
        })

      _later_batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          site_id: ctx.site.id,
          product_id: ctx.product.id,
          expiry_date: ~D[2027-01-01],
          quantity: 100
        })

      _other_site_batch =
        batch_fixture(%{
          organization_id: ctx.organization.id,
          product_id: ctx.product.id,
          expiry_date: ~D[2026-08-15],
          quantity: 100
        })

      assert {:ok, %PrescriptionItem{} = updated_item} =
               Prescriptions.dispense_item(
                 ctx.organization.id,
                 ctx.item.id,
                 ctx.pharmacist.id,
                 10
               )

      assert updated_item.quantity_dispensed == 10

      updated_batch = Batches.get_batch!(ctx.organization.id, soon_batch.id)
      assert updated_batch.remaining_quantity == 90

      updated_prescription =
        Prescriptions.get_prescription!(ctx.organization.id, ctx.prescription.id)

      assert updated_prescription.status == :completed
    end

    test "moves the prescription to partially_dispensed on a partial dispense", ctx do
      batch_fixture(%{
        organization_id: ctx.organization.id,
        site_id: ctx.site.id,
        product_id: ctx.product.id
      })

      assert {:ok, _updated_item} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 4)

      updated_prescription =
        Prescriptions.get_prescription!(ctx.organization.id, ctx.prescription.id)

      assert updated_prescription.status == :partially_dispensed
    end

    test "returns :out_of_stock when no eligible batch exists at that site", ctx do
      assert {:error, :out_of_stock} =
               Prescriptions.dispense_item(ctx.organization.id, ctx.item.id, ctx.pharmacist.id, 1)
    end

    test "returns :over_dispensed rather than exceeding quantity_prescribed", ctx do
      batch_fixture(%{
        organization_id: ctx.organization.id,
        site_id: ctx.site.id,
        product_id: ctx.product.id
      })

      assert {:error, :over_dispensed} =
               Prescriptions.dispense_item(
                 ctx.organization.id,
                 ctx.item.id,
                 ctx.pharmacist.id,
                 11
               )

      updated_batch =
        ctx.organization.id
        |> Batches.list_batches()
        |> hd()

      assert updated_batch.remaining_quantity == updated_batch.quantity
    end
  end
end
