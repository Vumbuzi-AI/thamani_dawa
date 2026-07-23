defmodule ThamaniDawa.AssociationsTest do
  @moduledoc """
  Covers the `belongs_to`/`has_many` graph added across every schema:
  representative parent-to-child and child-to-parent traversal across both
  the pharmacy and lab domains, plus proof that the scoped-custom-query
  preloads used throughout the app never resolve another organization's
  record — even for the FKs that have no cross-org write-time validation
  (see `.engineering/erd.md`).
  """
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.PatientVisitsFixtures
  import ThamaniDawa.PrescriptionsFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.SuppliersFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo

  describe "organization -> children traversal" do
    test "preloads every direct child collection off one organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      user = staff_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      supplier = supplier_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      category = lab_test_category_fixture(%{organization_id: organization.id})
      lab_test = lab_test_fixture(%{organization_id: organization.id, category_id: category.id})

      _batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          supplier_id: supplier.id,
          pending: true
        })

      loaded =
        organization.id
        |> Organizations.get_organization!()
        |> Repo.preload([
          :sites,
          :users,
          :products,
          :suppliers,
          :patients,
          :batches,
          :lab_test_categories,
          :lab_tests
        ])

      assert Enum.map(loaded.sites, & &1.id) == [site.id]
      assert Enum.map(loaded.users, & &1.id) == [user.id]
      assert Enum.map(loaded.products, & &1.id) == [product.id]
      assert Enum.map(loaded.suppliers, & &1.id) == [supplier.id]
      assert Enum.map(loaded.patients, & &1.id) == [patient.id]
      assert Enum.map(loaded.batches, & &1.product_id) == [product.id]
      assert Enum.map(loaded.lab_test_categories, & &1.id) == [category.id]
      assert Enum.map(loaded.lab_tests, & &1.id) == [lab_test.id]
    end
  end

  describe "user associations" do
    test "self-referential invited_by/invited_users" do
      admin = user_fixture()
      staff = staff_fixture(%{organization_id: admin.organization_id, invited_by_id: admin.id})

      loaded_staff = staff.id |> then(&Repo.get!(Accounts.User, &1)) |> Repo.preload(:invited_by)
      assert loaded_staff.invited_by.id == admin.id

      loaded_admin =
        admin.id |> then(&Repo.get!(Accounts.User, &1)) |> Repo.preload(:invited_users)

      assert Enum.map(loaded_admin.invited_users, & &1.id) == [staff.id]
    end

    test "role-specific has_many associations resolve to the right rows, not to each other" do
      organization = organization_fixture()
      approver = staff_fixture(%{organization_id: organization.id})
      orderer = staff_fixture(%{organization_id: organization.id})
      performer = staff_fixture(%{organization_id: organization.id})
      collector = staff_fixture(%{organization_id: organization.id})

      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          pending: true
        })

      {:ok, received} = Batches.receive_batch(batch, approver.id)

      lab_order = lab_order_fixture(%{organization_id: organization.id, site_id: site.id})

      result =
        lab_order_result_fixture(%{organization_id: organization.id, lab_order_id: lab_order.id})

      lab_order_update =
        organization.id
        |> LabOrders.get_lab_order!(lab_order.id)
        |> Ecto.Changeset.change(ordered_by_id: orderer.id)
        |> Repo.update!()

      result_update =
        result
        |> Ecto.Changeset.change(
          performed_by_id: performer.id,
          collected_by_id: collector.id
        )
        |> Repo.update!()

      approver =
        approver.id |> then(&Repo.get!(Accounts.User, &1)) |> Repo.preload(:approved_batches)

      orderer =
        orderer.id |> then(&Repo.get!(Accounts.User, &1)) |> Repo.preload(:ordered_lab_orders)

      performer =
        performer.id
        |> then(&Repo.get!(Accounts.User, &1))
        |> Repo.preload(:performed_lab_order_results)

      collector =
        collector.id
        |> then(&Repo.get!(Accounts.User, &1))
        |> Repo.preload(:collected_lab_order_results)

      assert Enum.map(approver.approved_batches, & &1.id) == [received.id]
      assert Enum.map(orderer.ordered_lab_orders, & &1.id) == [lab_order_update.id]
      assert Enum.map(performer.performed_lab_order_results, & &1.id) == [result_update.id]
      assert Enum.map(collector.collected_lab_order_results, & &1.id) == [result_update.id]

      # Cross-check: the performer's own approved_batches (a different role) is empty —
      # associations resolve by role, not by "any FK on this table pointing at users".
      performer_as_approver = Repo.preload(performer, :approved_batches)
      assert performer_as_approver.approved_batches == []
    end
  end

  describe "pharmacy chain traversal" do
    test "patient -> patient_visit -> prescription -> prescription_item -> product, and back" do
      organization = organization_fixture()
      patient = patient_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})

      visit =
        patient_visit_fixture(%{
          organization_id: organization.id,
          patient_id: patient.id,
          site_id: site.id,
          visit_type: :pharmacy
        })

      prescription =
        prescription_fixture(%{organization_id: organization.id, patient_visit_id: visit.id})

      _item =
        prescription_item_fixture(%{
          organization_id: organization.id,
          prescription_id: prescription.id,
          product_id: product.id,
          quantity_prescribed: 2
        })

      loaded_patient =
        patient.id
        |> then(&Repo.get!(ThamaniDawa.Patients.Patient, &1))
        |> Repo.preload(patient_visits: [prescriptions: :items])

      [loaded_visit] = loaded_patient.patient_visits
      assert loaded_visit.id == visit.id
      [loaded_prescription] = loaded_visit.prescriptions
      assert loaded_prescription.id == prescription.id
      [loaded_item] = loaded_prescription.items
      assert loaded_item.product_id == product.id

      # And the reverse direction: item -> prescription -> patient_visit -> patient.
      loaded_item_full =
        loaded_item.id
        |> then(&Repo.get!(ThamaniDawa.Prescriptions.PrescriptionItem, &1))
        |> Repo.preload(prescription: [patient_visit: :patient])

      assert loaded_item_full.prescription.patient_visit.patient.id == patient.id
    end
  end

  describe "lab chain traversal" do
    test "patient -> patient_visit -> lab_order -> lab_order_result -> lab_test -> lab_test_category" do
      organization = organization_fixture()
      patient = patient_fixture(%{organization_id: organization.id})
      site = site_fixture(%{organization_id: organization.id})
      category = lab_test_category_fixture(%{organization_id: organization.id})
      lab_test = lab_test_fixture(%{organization_id: organization.id, category_id: category.id})

      visit =
        patient_visit_fixture(%{
          organization_id: organization.id,
          patient_id: patient.id,
          site_id: site.id,
          visit_type: :lab
        })

      lab_order =
        lab_order_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_visit_id: visit.id
        })

      result =
        lab_order_result_fixture(%{
          organization_id: organization.id,
          lab_order_id: lab_order.id,
          lab_test_id: lab_test.id
        })

      loaded =
        lab_order.id
        |> then(&Repo.get!(LabOrders.LabOrder, &1))
        |> Repo.preload(patient_visit: :patient, lab_order_results: [lab_test: :category])

      assert loaded.patient_visit.patient.id == patient.id
      [loaded_result] = loaded.lab_order_results
      assert loaded_result.id == result.id
      assert loaded_result.lab_test.id == lab_test.id
      assert loaded_result.lab_test.category.id == category.id
    end

    test "batch -> lab_consumable_usages -> lab_order" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          product_id: product.id,
          quantity: 50
        })

      lab_order = lab_order_fixture(%{organization_id: organization.id, site_id: site.id})

      {:ok, usage} =
        LabOrders.record_consumable_usage(
          organization.id,
          batch.id,
          technician.id,
          5,
          lab_order_id: lab_order.id
        )

      loaded_batch =
        batch.id
        |> then(&Repo.get!(Batches.Batch, &1))
        |> Repo.preload(lab_consumable_usages: :lab_order)

      [loaded_usage] = loaded_batch.lab_consumable_usages
      assert loaded_usage.id == usage.id
      assert loaded_usage.lab_order.id == lab_order.id
    end
  end

  describe "tenant isolation via scoped preloads" do
    test "Batches.list_batches_for_product/2 never resolves an approver from another organization" do
      org_a = organization_fixture()
      org_b = organization_fixture()

      site = site_fixture(%{organization_id: org_a.id})
      product = product_fixture(%{organization_id: org_a.id})

      batch =
        batch_fixture(%{organization_id: org_a.id, site_id: site.id, product_id: product.id})

      foreign_user = staff_fixture(%{organization_id: org_b.id})

      # No cross-org validation exists on batches.approver_id today — simulate the gap
      # directly, bypassing the app's changeset, exactly as an unvalidated write could.
      batch
      |> Ecto.Changeset.change(
        approver_id: foreign_user.id,
        received_at: DateTime.utc_now(:second)
      )
      |> Repo.update!()

      [loaded] = Batches.list_batches_for_product(org_a.id, product.id)

      assert loaded.approver_id == foreign_user.id
      assert loaded.approver == nil
    end

    test "LabOrders.list_lab_order_results_for_order/2 never resolves a performer from another organization" do
      org_a = organization_fixture()
      org_b = organization_fixture()

      result = lab_order_result_fixture(%{organization_id: org_a.id})
      foreign_performer = staff_fixture(%{organization_id: org_b.id, role: :lab_technician})

      {:ok, completed} =
        result
        |> Ecto.Changeset.change(status: :completed, performed_by_id: foreign_performer.id)
        |> Repo.update()

      [loaded] = LabOrders.list_lab_order_results_for_order(org_a.id, completed.lab_order_id)

      assert loaded.id == completed.id
      assert loaded.performed_by_id == foreign_performer.id
      assert loaded.performed_by == nil
    end

    test "LabTests.list_lab_tests/1 never resolves a category from another organization" do
      org_a = organization_fixture()
      org_b = organization_fixture()

      category_b = lab_test_category_fixture(%{organization_id: org_b.id})
      lab_test = lab_test_fixture(%{organization_id: org_a.id})

      # No cross-org validation exists on lab_tests.category_id today — same simulated gap.
      lab_test
      |> Ecto.Changeset.change(category_id: category_b.id)
      |> Repo.update!()

      [loaded] = LabTests.list_lab_tests(org_a.id)

      assert loaded.category_id == category_b.id
      assert loaded.category == nil
    end

    test "Accounts.list_users/1 never resolves a home site from another organization" do
      org_a = organization_fixture()
      org_b = organization_fixture()

      user = staff_fixture(%{organization_id: org_a.id})
      site_b = site_fixture(%{organization_id: org_b.id})

      # site_id normally has cross-org validation at invite time — bypass it here too,
      # to prove the read path is defended independently of the write path.
      user
      |> Ecto.Changeset.change(site_id: site_b.id)
      |> Repo.update!()

      [loaded] = Accounts.list_users(org_a.id)

      assert loaded.site_id == site_b.id
      assert loaded.site == nil
    end
  end
end
