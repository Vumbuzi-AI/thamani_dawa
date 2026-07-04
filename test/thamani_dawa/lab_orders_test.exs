defmodule ThamaniDawa.LabOrdersTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabOrders.{LabOrder, LabOrderTest}

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.LabTestTemplatesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_lab_order/2" do
    test "requires site_id and patient_id" do
      organization = organization_fixture()

      assert {:error, changeset} = LabOrders.create_lab_order(organization.id, %{})
      assert %{site_id: ["can't be blank"], patient_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to pending and scopes to the organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      assert {:ok, %LabOrder{} = lab_order} =
               LabOrders.create_lab_order(organization.id, %{
                 site_id: site.id,
                 patient_id: patient.id
               })

      assert lab_order.organization_id == organization.id
      assert lab_order.status == :pending
    end
  end

  describe "create_lab_order_with_tests/3" do
    test "creates the header and every test in one transaction" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      lab_test = lab_test_fixture(%{organization_id: organization.id})

      assert {:ok, %{lab_order: lab_order, lab_order_tests: [test]}} =
               LabOrders.create_lab_order_with_tests(
                 organization.id,
                 %{site_id: site.id, patient_id: patient.id},
                 [%{lab_test_id: lab_test.id}]
               )

      assert lab_order.site_id == site.id
      assert test.lab_order_id == lab_order.id
      assert test.status == :pending
    end

    test "rolls back the header when a test is invalid" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               LabOrders.create_lab_order_with_tests(
                 organization.id,
                 %{site_id: site.id, patient_id: patient.id},
                 [%{}]
               )

      assert %{lab_test_id: ["can't be blank"]} = errors_on(changeset)
      assert LabOrders.list_lab_orders(organization.id) == []
    end
  end

  describe "record_result/4" do
    setup do
      organization = organization_fixture()
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})
      %{organization: organization, technician: technician}
    end

    test "auto-computes flags from the test's template and marks it completed", ctx do
      template = lab_test_template_fixture(%{organization_id: ctx.organization.id})

      lab_order_test =
        lab_order_test_fixture(%{organization_id: ctx.organization.id, template_id: template.id})

      assert {:ok, %LabOrderTest{} = updated} =
               LabOrders.record_result(
                 ctx.organization.id,
                 lab_order_test.id,
                 ctx.technician.id,
                 %{"wbc" => 20.0}
               )

      assert %{"wbc" => %{"value" => 20.0, "flag" => "high"}} = updated.results
      assert updated.status == :completed
      assert updated.performed_by_id == ctx.technician.id
      assert updated.test_performed_on == Date.utc_today()
    end

    test "stores raw values with no flag when the test has no template", ctx do
      lab_order_test = lab_order_test_fixture(%{organization_id: ctx.organization.id})

      assert {:ok, %LabOrderTest{results: results}} =
               LabOrders.record_result(
                 ctx.organization.id,
                 lab_order_test.id,
                 ctx.technician.id,
                 %{"note" => "clear"}
               )

      assert %{"note" => %{"value" => "clear"}} = results
    end

    test "moves the parent lab order to in_progress once one of several tests is completed",
         ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.organization.id})

      test_1 =
        lab_order_test_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      _test_2 =
        lab_order_test_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, _updated} =
               LabOrders.record_result(ctx.organization.id, test_1.id, ctx.technician.id, %{
                 "note" => "ok"
               })

      assert %LabOrder{status: :in_progress} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)
    end
  end

  describe "verify_lab_order_test/3" do
    setup do
      organization = organization_fixture()
      performer = staff_fixture(%{organization_id: organization.id, role: :lab_technician})
      verifier = staff_fixture(%{organization_id: organization.id, role: :lab_technician})
      lab_order_test = lab_order_test_fixture(%{organization_id: organization.id})

      %{
        organization: organization,
        performer: performer,
        verifier: verifier,
        lab_order_test: lab_order_test
      }
    end

    test "returns :not_completed when results haven't been entered yet", ctx do
      assert {:error, :not_completed} =
               LabOrders.verify_lab_order_test(
                 ctx.organization.id,
                 ctx.lab_order_test.id,
                 ctx.verifier.id
               )
    end

    test "returns :same_technician when the verifier performed the test", ctx do
      {:ok, performed} =
        LabOrders.record_result(ctx.organization.id, ctx.lab_order_test.id, ctx.performer.id, %{
          "note" => "ok"
        })

      assert {:error, :same_technician} =
               LabOrders.verify_lab_order_test(
                 ctx.organization.id,
                 performed.id,
                 ctx.performer.id
               )
    end

    test "marks the test verified and rolls the lab order status to verified", ctx do
      {:ok, performed} =
        LabOrders.record_result(ctx.organization.id, ctx.lab_order_test.id, ctx.performer.id, %{
          "note" => "ok"
        })

      assert {:ok, %LabOrderTest{status: :verified} = verified} =
               LabOrders.verify_lab_order_test(ctx.organization.id, performed.id, ctx.verifier.id)

      assert verified.verified_by_id == ctx.verifier.id
      assert %DateTime{} = verified.verified_at

      lab_order = LabOrders.get_lab_order!(ctx.organization.id, performed.lab_order_id)
      assert lab_order.status == :verified
    end
  end

  describe "record_consumable_usage/5" do
    setup do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})
      batch = batch_fixture(%{organization_id: organization.id, site_id: site.id, quantity: 50})

      %{organization: organization, technician: technician, batch: batch}
    end

    test "decrements the batch and records usage", ctx do
      assert {:ok, usage} =
               LabOrders.record_consumable_usage(
                 ctx.organization.id,
                 ctx.batch.id,
                 ctx.technician.id,
                 10,
                 purpose: "reagent draw"
               )

      assert usage.batch_id == ctx.batch.id
      assert usage.quantity == 10
      assert usage.purpose == "reagent draw"
      assert %DateTime{} = usage.used_at

      updated_batch = Batches.get_batch!(ctx.organization.id, ctx.batch.id)
      assert updated_batch.remaining_quantity == 40
    end

    test "rolls back when quantity would take the batch below zero", ctx do
      assert {:error, _changeset} =
               LabOrders.record_consumable_usage(
                 ctx.organization.id,
                 ctx.batch.id,
                 ctx.technician.id,
                 999
               )

      updated_batch = Batches.get_batch!(ctx.organization.id, ctx.batch.id)
      assert updated_batch.remaining_quantity == ctx.batch.remaining_quantity
    end
  end
end
