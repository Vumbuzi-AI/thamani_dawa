defmodule ThamaniDawaWeb.VerificationQueueLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.LabOrders

  setup do
    admin = user_fixture()

    performer =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :lab_technician
      })

    verifier =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :lab_technician
      })

    site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
    lab_test = lab_test_fixture(%{organization_id: admin.organization_id})

    %{admin: admin, performer: performer, verifier: verifier, site: site, lab_test: lab_test}
  end

  # `lab_order_fixture/1` only threads a given `patient_id` through to the
  # patient_visit it creates — it never sets `LabOrder.patient_id` itself
  # (the real create flow does, via the header form's `patient_id` field).
  # Patch it directly so `patient_name/3` (which reads `lab_order.patient_id`)
  # can resolve it in tests, same as it would from a real save.
  defp lab_order_with_patient(organization_id, patient_id) do
    order = lab_order_fixture(%{organization_id: organization_id, patient_id: patient_id})

    {:ok, updated} =
      order |> Ecto.Changeset.change(patient_id: patient_id) |> ThamaniDawa.Repo.update()

    updated
  end

  defp make_completed_result(ctx) do
    result =
      lab_order_result_fixture(%{
        organization_id: ctx.admin.organization_id,
        lab_test_id: ctx.lab_test.id
      })

    {:ok, completed} =
      LabOrders.record_result(
        ctx.admin.organization_id,
        result.id,
        ctx.performer.id,
        %{"haemoglobin" => "13.5"}
      )

    completed
  end

  describe "verification queue" do
    test "shows only :completed results, not pending or already verified", ctx do
      completed = make_completed_result(ctx)
      _pending = lab_order_result_fixture(%{organization_id: ctx.admin.organization_id})

      {:ok, _view, html} =
        live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/verification-queue")

      # The completed result's performer name should appear
      performer = ThamaniDawa.Accounts.get_user!(ctx.admin.organization_id, ctx.performer.id)
      assert html =~ performer.name

      # After verifying, the row disappears from the queue
      {:ok, _} =
        LabOrders.verify_result(ctx.admin.organization_id, completed.id, ctx.verifier.id)

      {:ok, _view2, html2} =
        live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/verification-queue")

      refute html2 =~ performer.name
    end

    test "a different user can verify a result and it disappears from the queue", ctx do
      result = make_completed_result(ctx)

      {:ok, view, _html} =
        live(log_in_user(ctx.conn, ctx.verifier), ~p"/lab/verification-queue")

      view
      |> element(~s(button[phx-click="verify"][phx-value-id="#{result.id}"]))
      |> render_click()

      assert LabOrders.get_lab_order_result!(ctx.admin.organization_id, result.id).status ==
               :verified
    end

    test "hides the verify button for the user who performed the test", ctx do
      result = make_completed_result(ctx)

      {:ok, _view, html} =
        live(log_in_user(ctx.conn, ctx.performer), ~p"/lab/verification-queue")

      refute html =~ "phx-value-id=\"#{result.id}\""

      assert LabOrders.get_lab_order_result!(ctx.admin.organization_id, result.id).status ==
               :completed
    end

    test "searches by patient name", ctx do
      alice =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Alice Wanjiru"})

      bob =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Bob Otieno"})

      alice_order = lab_order_with_patient(ctx.admin.organization_id, alice.id)
      bob_order = lab_order_with_patient(ctx.admin.organization_id, bob.id)

      alice_result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: alice_order.id,
          lab_test_id: ctx.lab_test.id
        })

      bob_result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: bob_order.id,
          lab_test_id: ctx.lab_test.id
        })

      LabOrders.record_result(ctx.admin.organization_id, alice_result.id, ctx.performer.id, %{
        "haemoglobin" => "13.5"
      })

      LabOrders.record_result(ctx.admin.organization_id, bob_result.id, ctx.performer.id, %{
        "haemoglobin" => "13.5"
      })

      {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/verification-queue")

      lv |> form("form[phx-change='search']", search: "alice") |> render_change()

      html = render(lv)
      assert html =~ "Alice Wanjiru"
      refute html =~ "Bob Otieno"
    end

    test "filters by test", ctx do
      other_test = lab_test_fixture(%{organization_id: ctx.admin.organization_id, name: "Widal"})

      patient_a =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Patient A"})

      patient_b =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Patient B"})

      order_a = lab_order_with_patient(ctx.admin.organization_id, patient_a.id)
      order_b = lab_order_with_patient(ctx.admin.organization_id, patient_b.id)

      result_a =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: order_a.id,
          lab_test_id: ctx.lab_test.id
        })

      result_b =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: order_b.id,
          lab_test_id: other_test.id
        })

      LabOrders.record_result(ctx.admin.organization_id, result_a.id, ctx.performer.id, %{
        "haemoglobin" => "13.5"
      })

      LabOrders.record_result(ctx.admin.organization_id, result_b.id, ctx.performer.id, %{
        "haemoglobin" => "13.5"
      })

      {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/verification-queue")

      lv
      |> form("#verification-queue-filters-form",
        filters: %{lab_test_id: to_string(other_test.id)}
      )
      |> render_submit()

      html = render(lv)
      assert html =~ "Patient B"
      refute html =~ "Patient A"
      assert html =~ "Test: Widal"
    end

    test "does not show results from another organization", ctx do
      other_result = lab_order_result_fixture()

      LabOrders.record_result(
        other_result.organization_id,
        other_result.id,
        ctx.performer.id,
        %{"x" => "1"}
      )

      {:ok, _view, html} =
        live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/verification-queue")

      pending = LabOrders.list_results_pending_verification(ctx.admin.organization_id)
      assert Enum.all?(pending, &(&1.organization_id == ctx.admin.organization_id))

      # The other org's result ID should not appear anywhere in the queue HTML
      refute html =~ "phx-value-id=\"#{other_result.id}\""
    end
  end
end
