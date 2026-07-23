defmodule ThamaniDawa.LabOrdersTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabOrders.{LabOrder, LabOrderResult}
  alias ThamaniDawa.PatientVisits

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.SitesFixtures

  @valid_header_extra %{
    lab_request: "CBC panel",
    referring_facility: "General Hospital",
    referring_doctor: "Dr. Jane Doe",
    referred_date: ~D[2026-01-15]
  }

  describe "create_lab_order/2" do
    test "requires site_id and patient_visit_id" do
      organization = organization_fixture()

      assert {:error, changeset} = LabOrders.create_lab_order(organization.id, %{})

      assert %{
               site_id: ["can't be blank"],
               patient_visit_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "defaults status to pending and scopes to the organization" do
      lab_order = lab_order_fixture()

      assert %LabOrder{} = lab_order
      assert lab_order.status == :pending
    end
  end

  describe "referral validation" do
    setup do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})

      {:ok, visit} =
        ThamaniDawa.PatientVisits.create_patient_visit(organization.id, %{
          patient_id: patient.id,
          site_id: site.id,
          user_id: technician.id,
          visit_type: :lab
        })

      base = %{site_id: site.id, patient_visit_id: visit.id, payment_type: "Cash"}
      %{organization: organization, base: base}
    end

    test "a non-referred order saves without referral details", ctx do
      assert {:ok, %LabOrder{is_referral: false}} =
               LabOrders.create_lab_order(ctx.organization.id, ctx.base)
    end

    test "a referred order requires the referring facility and doctor", ctx do
      attrs = Map.put(ctx.base, :is_referral, true)

      assert {:error, changeset} = LabOrders.create_lab_order(ctx.organization.id, attrs)

      assert %{
               referring_facility: ["is required for a referral"],
               referring_doctor: ["is required for a referral"]
             } = errors_on(changeset)
    end

    test "a referred order saves once facility and doctor are given", ctx do
      attrs =
        Map.merge(ctx.base, %{
          is_referral: true,
          referring_facility: "General Hospital",
          referring_doctor: "Dr. Jane Doe"
        })

      assert {:ok, %LabOrder{is_referral: true, referring_facility: "General Hospital"}} =
               LabOrders.create_lab_order(ctx.organization.id, attrs)
    end
  end

  describe "payment method validation" do
    setup do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})

      {:ok, visit} =
        ThamaniDawa.PatientVisits.create_patient_visit(organization.id, %{
          patient_id: patient.id,
          site_id: site.id,
          user_id: technician.id,
          visit_type: :lab
        })

      base = %{site_id: site.id, patient_visit_id: visit.id}
      %{organization: organization, base: base}
    end

    test "accepts every approved payment method", ctx do
      for method <- ThamaniDawa.PaymentMethods.all() do
        attrs = Map.put(ctx.base, :payment_type, method)

        assert {:ok, %LabOrder{payment_type: ^method}} =
                 LabOrders.create_lab_order(ctx.organization.id, attrs)
      end
    end

    test "rejects an unsupported payment method", ctx do
      attrs = Map.put(ctx.base, :payment_type, "Bitcoin")

      assert {:error, changeset} = LabOrders.create_lab_order(ctx.organization.id, attrs)

      assert %{payment_type: ["must be one of the approved payment methods"]} =
               errors_on(changeset)
    end

    test "allows an omitted payment method", ctx do
      assert {:ok, %LabOrder{payment_type: nil}} =
               LabOrders.create_lab_order(ctx.organization.id, ctx.base)
    end
  end

  describe "create_lab_order_with_results/4 (with auto-created visit)" do
    test "sets patient_visit_id on the resulting order, linking to the patient via the visit" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      lab_test = lab_test_fixture(%{organization_id: organization.id})
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})

      visit_attrs = %{
        patient_id: patient.id,
        site_id: site.id,
        user_id: technician.id,
        visit_type: :lab
      }

      assert {:ok, %{lab_order: header}} =
               LabOrders.create_lab_order_with_results(
                 organization.id,
                 %{"site_id" => site.id},
                 [%{lab_test_id: lab_test.id, sample_type: :blood}],
                 visit_attrs
               )

      assert header.patient_visit_id != nil

      visit = PatientVisits.get_patient_visit!(organization.id, header.patient_visit_id)
      assert visit.patient_id == patient.id
    end
  end

  describe "create_lab_order_with_results/3" do
    test "creates the header and every result in one transaction" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      lab_test = lab_test_fixture(%{organization_id: organization.id})

      lab_order =
        lab_order_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      assert {:ok, %{lab_order: header, lab_order_results: [result]}} =
               LabOrders.create_lab_order_with_results(
                 organization.id,
                 Map.merge(@valid_header_extra, %{
                   site_id: site.id,
                   patient_visit_id: lab_order.patient_visit_id
                 }),
                 [%{lab_test_id: lab_test.id, sample_type: :blood}]
               )

      assert result.status == :pending
      assert header.referred_date == ~D[2026-01-15]
    end

    test "rolls back the header when a result is invalid" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})

      lab_order =
        lab_order_fixture(%{
          organization_id: organization.id,
          site_id: site.id,
          patient_id: patient.id
        })

      before_count = length(LabOrders.list_lab_orders(organization.id))

      assert {:error, changeset} =
               LabOrders.create_lab_order_with_results(
                 organization.id,
                 Map.merge(@valid_header_extra, %{
                   site_id: site.id,
                   patient_visit_id: lab_order.patient_visit_id
                 }),
                 [%{}]
               )

      assert %{lab_test_id: ["can't be blank"]} = errors_on(changeset)
      assert length(LabOrders.list_lab_orders(organization.id)) == before_count
    end
  end

  describe "mark_sample_collected/4" do
    setup do
      organization = organization_fixture()
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})
      %{organization: organization, technician: technician}
    end

    test "records the date, collector, notes, and sets result status to collected", ctx do
      lab_order_result = lab_order_result_fixture(%{organization_id: ctx.organization.id})

      assert {:ok, updated} =
               LabOrders.mark_sample_collected(
                 ctx.organization.id,
                 lab_order_result.id,
                 ctx.technician.id,
                 %{"collection_date" => "2026-01-15", "collection_notes" => "Left arm vein"}
               )

      assert updated.status == :collected
      assert updated.sample_collected_on == ~D[2026-01-15]
      assert updated.collected_by_id == ctx.technician.id
      assert updated.collection_notes == "Left arm vein"
    end

    test "defaults to today's date when none is given", ctx do
      lab_order_result = lab_order_result_fixture(%{organization_id: ctx.organization.id})

      assert {:ok, updated} =
               LabOrders.mark_sample_collected(
                 ctx.organization.id,
                 lab_order_result.id,
                 ctx.technician.id
               )

      assert updated.sample_collected_on == Date.utc_today()
    end

    test "advances the parent order to in_progress", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.organization.id})

      result =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, _} =
               LabOrders.mark_sample_collected(ctx.organization.id, result.id, ctx.technician.id)

      assert %LabOrder{status: :in_progress} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)
    end

    test "moves a multi-test order to in_progress while sibling results are still pending", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.organization.id})

      result_1 =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      result_2 =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, _} =
               LabOrders.mark_sample_collected(
                 ctx.organization.id,
                 result_1.id,
                 ctx.technician.id
               )

      assert %LabOrder{status: :in_progress} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)

      assert LabOrders.get_lab_order_result!(ctx.organization.id, result_2.id).status == :pending
    end

    test "never resurrects a cancelled order", ctx do
      lab_order =
        lab_order_fixture(%{organization_id: ctx.organization.id, status: :cancelled})

      result =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, updated} =
               LabOrders.mark_sample_collected(ctx.organization.id, result.id, ctx.technician.id)

      assert updated.status == :collected

      assert %LabOrder{status: :cancelled} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)
    end
  end

  describe "record_result/4" do
    setup do
      organization = organization_fixture()
      technician = staff_fixture(%{organization_id: organization.id, role: :lab_technician})
      %{organization: organization, technician: technician}
    end

    test "stores raw values with no flag", ctx do
      lab_order_result = lab_order_result_fixture(%{organization_id: ctx.organization.id})

      assert {:ok, %LabOrderResult{results: results}} =
               LabOrders.record_result(
                 ctx.organization.id,
                 lab_order_result.id,
                 ctx.technician.id,
                 %{"note" => "clear"}
               )

      assert %{"note" => %{"value" => "clear"}} = results
    end

    test "marks the result completed and attributes it to the performer", ctx do
      lab_order_result = lab_order_result_fixture(%{organization_id: ctx.organization.id})

      assert {:ok, %LabOrderResult{} = updated} =
               LabOrders.record_result(
                 ctx.organization.id,
                 lab_order_result.id,
                 ctx.technician.id,
                 %{"note" => "ok"}
               )

      assert updated.status == :completed
      assert updated.performed_by_id == ctx.technician.id
      assert updated.test_performed_on == Date.utc_today()
    end

    test "moves the parent lab order to in_progress once one of several results is completed",
         ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.organization.id})

      result_1 =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      _result_2 =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, _updated} =
               LabOrders.record_result(ctx.organization.id, result_1.id, ctx.technician.id, %{
                 "note" => "ok"
               })

      assert %LabOrder{status: :in_progress} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)
    end

    test "moves the parent lab order to completed once every result is completed", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.organization.id})

      result_1 =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, _updated} =
               LabOrders.record_result(ctx.organization.id, result_1.id, ctx.technician.id, %{
                 "note" => "ok"
               })

      assert %LabOrder{status: :completed} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)
    end

    test "never resurrects a cancelled order", ctx do
      lab_order =
        lab_order_fixture(%{organization_id: ctx.organization.id, status: :cancelled})

      result =
        lab_order_result_fixture(%{
          organization_id: ctx.organization.id,
          lab_order_id: lab_order.id
        })

      assert {:ok, updated} =
               LabOrders.record_result(ctx.organization.id, result.id, ctx.technician.id, %{
                 "note" => "ok"
               })

      assert updated.status == :completed

      assert %LabOrder{status: :cancelled} =
               LabOrders.get_lab_order!(ctx.organization.id, lab_order.id)
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
