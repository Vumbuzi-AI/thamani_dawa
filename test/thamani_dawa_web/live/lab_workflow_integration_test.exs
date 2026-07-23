defmodule ThamaniDawaWeb.LabWorkflowIntegrationTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.LabOrders

  test "lab technician completes the full order → collect → results flow", ctx do
    admin = user_fixture()
    organization_id = admin.organization_id

    performer =
      staff_fixture(%{
        organization_id: organization_id,
        invited_by_id: admin.id,
        role: :lab_technician
      })

    site = site_fixture(%{organization_id: organization_id, site_type: :lab})
    lab_test = lab_test_fixture(%{organization_id: organization_id})

    # Step 1: Create an order with one test result (creation UI is covered in lab_order_live_test)
    lab_order = lab_order_fixture(%{organization_id: organization_id, site_id: site.id})

    result =
      lab_order_result_fixture(%{
        organization_id: organization_id,
        lab_order_id: lab_order.id,
        lab_test_id: lab_test.id
      })

    assert lab_order.status == :pending
    assert result.status == :pending

    # Step 2: Performer collects the sample via the order show page
    performer_conn = log_in_user(ctx.conn, performer)
    {:ok, view, _html} = live(performer_conn, ~p"/lab/orders/#{lab_order.id}")

    view
    |> element(~s(button[phx-click="start_collect"][phx-value-id="#{result.id}"]))
    |> render_click()

    view
    |> form("#collect-sample-form", %{
      "collection_date" => "2026-01-15",
      "collection_notes" => "Left antecubital fossa"
    })
    |> render_submit(%{"result_id" => to_string(result.id)})

    result = LabOrders.get_lab_order_result!(organization_id, result.id)
    assert result.status == :collected
    assert LabOrders.get_lab_order!(organization_id, lab_order.id).status == :in_progress

    # Step 3: Performer enters results via ResultEntryLive
    {:ok, result_view, _html} =
      live(performer_conn, ~p"/lab/orders/#{lab_order.id}/results/#{result.id}/edit")

    result_view
    |> form("#result-entry-form", %{"values" => %{"haemoglobin" => "13.5"}})
    |> render_submit()

    result = LabOrders.get_lab_order_result!(organization_id, result.id)
    assert result.status == :completed
    assert result.performed_by_id == performer.id
    assert LabOrders.get_lab_order!(organization_id, lab_order.id).status == :completed
  end
end
