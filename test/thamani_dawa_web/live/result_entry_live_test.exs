defmodule ThamaniDawaWeb.ResultEntryLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.LabOrders

  setup do
    admin = user_fixture()

    lab_tech =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :lab_technician
      })

    site = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})
    lab_test = lab_test_fixture(%{organization_id: admin.organization_id})

    %{admin: admin, lab_tech: lab_tech, site: site, lab_test: lab_test}
  end

  describe "result entry" do
    test "renders the test name and a field per definition entry", ctx do
      result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_test_id: ctx.lab_test.id
        })

      {:ok, _view, html} =
        live(
          log_in_user(ctx.conn, ctx.admin),
          ~p"/lab/orders/#{result.lab_order_id}/results/#{result.id}/edit"
        )

      assert html =~ ctx.lab_test.name
      # field key from default fixture field_definitions: %{"haemoglobin" => ...}
      assert html =~ "haemoglobin"
      assert html =~ "g/dL"
    end

    test "saving results marks the result :completed and redirects to the order", ctx do
      result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_test_id: ctx.lab_test.id
        })

      {:ok, view, _html} =
        live(
          log_in_user(ctx.conn, ctx.admin),
          ~p"/lab/orders/#{result.lab_order_id}/results/#{result.id}/edit"
        )

      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> form("#result-entry-form", %{"values" => %{"haemoglobin" => "13.5"}})
               |> render_submit()

      assert redirect_path == ~p"/lab/orders/#{result.lab_order_id}"

      updated = LabOrders.get_lab_order_result!(ctx.admin.organization_id, result.id)
      assert updated.status == :completed
      assert get_in(updated.results, ["haemoglobin", "value"]) == "13.5"
    end

    test "saving results also advances the parent order to :completed when all results are done",
         ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})

      result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: lab_order.id,
          lab_test_id: ctx.lab_test.id
        })

      {:ok, view, _html} =
        live(
          log_in_user(ctx.conn, ctx.admin),
          ~p"/lab/orders/#{lab_order.id}/results/#{result.id}/edit"
        )

      view
      |> form("#result-entry-form", %{"values" => %{"haemoglobin" => "14.0"}})
      |> render_submit()

      assert LabOrders.get_lab_order!(ctx.admin.organization_id, lab_order.id).status ==
               :completed
    end

    test "raises when accessing another organization's result", ctx do
      other_result = lab_order_result_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        live(
          log_in_user(ctx.conn, ctx.admin),
          ~p"/lab/orders/#{other_result.lab_order_id}/results/#{other_result.id}/edit"
        )
      end
    end
  end
end
