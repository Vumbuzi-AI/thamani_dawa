defmodule ThamaniDawaWeb.LabOrderLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.LabTestsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Patients

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

  describe "index filters" do
    test "searches by patient name", ctx do
      alice =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Alice Wanjiru"})

      bob =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Bob Otieno"})

      lab_order_fixture(%{organization_id: ctx.admin.organization_id, patient_id: alice.id})
      lab_order_fixture(%{organization_id: ctx.admin.organization_id, patient_id: bob.id})

      {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders")

      lv |> form("form[phx-change='search']", search: "alice") |> render_change()

      html = render(lv)
      assert html =~ "Alice Wanjiru"
      refute html =~ "Bob Otieno"
    end

    test "filters by status", ctx do
      pending_patient =
        patient_fixture(%{
          organization_id: ctx.admin.organization_id,
          full_name: "Pending Patient"
        })

      completed_patient =
        patient_fixture(%{
          organization_id: ctx.admin.organization_id,
          full_name: "Completed Patient"
        })

      lab_order_fixture(%{
        organization_id: ctx.admin.organization_id,
        patient_id: pending_patient.id
      })

      lab_order_fixture(%{
        organization_id: ctx.admin.organization_id,
        patient_id: completed_patient.id,
        status: :completed
      })

      {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders")

      lv
      |> form("#lab-orders-filters-form", filters: %{status: "completed"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Completed Patient"
      refute html =~ "Pending Patient"
      assert html =~ "Status: Completed"
    end

    test "filters by urgency", ctx do
      routine_patient =
        patient_fixture(%{
          organization_id: ctx.admin.organization_id,
          full_name: "Routine Patient"
        })

      stat_patient =
        patient_fixture(%{organization_id: ctx.admin.organization_id, full_name: "Stat Patient"})

      lab_order_fixture(%{
        organization_id: ctx.admin.organization_id,
        patient_id: routine_patient.id,
        urgency: "routine"
      })

      lab_order_fixture(%{
        organization_id: ctx.admin.organization_id,
        patient_id: stat_patient.id,
        urgency: "stat"
      })

      {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders")

      lv
      |> form("#lab-orders-filters-form", filters: %{urgency: "stat"})
      |> render_submit()

      html = render(lv)
      assert html =~ "Stat Patient"
      refute html =~ "Routine Patient"
      assert html =~ "Urgency: Stat"
    end
  end

  describe "show lab order" do
    test "renders the order details and test results", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})

      result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: lab_order.id,
          lab_test_id: ctx.lab_test.id
        })

      {:ok, _view, html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/#{lab_order.id}")

      assert html =~ ctx.lab_test.name
      assert html =~ Phoenix.Naming.humanize(result.status)
    end

    test "recording a sample collection advances the result to :collected and order to :in_progress",
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
          ~p"/lab/orders/#{lab_order.id}/results/#{result.id}/collect"
        )

      view
      |> form("#collect-sample-form", %{
        "collection_date" => "2026-01-15",
        "collection_notes" => "Right antecubital fossa"
      })
      |> render_submit(%{"result_id" => to_string(result.id)})

      updated = LabOrders.get_lab_order_result!(ctx.admin.organization_id, result.id)
      assert updated.status == :collected
      assert updated.sample_collected_on == ~D[2026-01-15]
      assert updated.collection_notes == "Right antecubital fossa"

      assert LabOrders.get_lab_order!(ctx.admin.organization_id, lab_order.id).status ==
               :in_progress
    end

    test "recording a result advances it to :completed and the order to :completed", ctx do
      organization_id = ctx.admin.organization_id
      lab_order = lab_order_fixture(%{organization_id: organization_id})

      result =
        lab_order_result_fixture(%{
          organization_id: organization_id,
          lab_order_id: lab_order.id,
          lab_test_id: ctx.lab_test.id
        })

      {:ok, _} =
        LabOrders.record_result(organization_id, result.id, ctx.lab_tech.id, %{"hb" => "13"})

      assert LabOrders.get_lab_order_result!(organization_id, result.id).status == :completed
      assert LabOrders.get_lab_order!(organization_id, lab_order.id).status == :completed
    end
  end

  describe "removed verification queue" do
    test "the standalone /lab/verification-queue route no longer exists", ctx do
      conn = get(log_in_user(ctx.conn, ctx.lab_tech), "/lab/verification-queue")

      assert conn.status == 404
    end
  end

  describe "new lab order" do
    test "renders patient list and active tests, hides inactive tests", ctx do
      inactive =
        lab_test_fixture(%{organization_id: ctx.admin.organization_id, name: "Inactive Test Z"})

      ThamaniDawa.LabTests.update_lab_test(ctx.admin.organization_id, inactive, %{
        is_active: false
      })

      patient = patient_fixture(%{organization_id: ctx.admin.organization_id})

      {:ok, _view, html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      assert html =~ patient.full_name
      assert html =~ ctx.lab_test.name
      refute html =~ inactive.name
    end

    test "creates order and result row with existing patient", ctx do
      patient = patient_fixture(%{organization_id: ctx.admin.organization_id})

      {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      view
      |> form("#new-lab-order-form", %{
        "lab_order" => %{
          "patient_id" => to_string(patient.id),
          "site_id" => to_string(ctx.site.id),
          "urgency" => "routine",
          "payment_type" => "Cash"
        },
        "tests" => %{
          "0" => %{
            "lab_test_id" => to_string(ctx.lab_test.id),
            "sample_type" => "blood"
          }
        }
      })
      |> render_submit()

      orders = LabOrders.list_lab_orders(ctx.admin.organization_id)
      assert length(orders) == 1
      assert hd(orders).patient_visit_id != nil

      assert length(LabOrders.list_lab_order_results(ctx.admin.organization_id)) == 1
    end

    test "creates patient scoped to org when using inline new patient", ctx do
      {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      view |> element("#new-patient-mode") |> render_click()

      gsrn = System.unique_integer([:positive])

      view
      |> form("#new-lab-order-form", %{
        "lab_order" => %{
          "site_id" => to_string(ctx.site.id),
          "urgency" => "routine",
          "payment_type" => "Cash"
        },
        "patient" => %{
          "full_name" => "Inline Patient",
          "gender" => "Female",
          "phone" => "0712345678",
          "national_id" => "12345678",
          "gsrn" => to_string(gsrn)
        },
        "tests" => %{
          "0" => %{
            "lab_test_id" => to_string(ctx.lab_test.id),
            "sample_type" => "blood"
          }
        }
      })
      # The date-of-birth picker sets its hidden input via JS, so supply the
      # value through the submit payload rather than the rendered form.
      |> render_submit(%{"patient" => %{"date_of_birth" => "1998-01-01"}})

      patients = Patients.list_patients(ctx.admin.organization_id)
      new_patient = Enum.find(patients, &(&1.full_name == "Inline Patient"))
      assert new_patient != nil
      assert new_patient.organization_id == ctx.admin.organization_id

      assert length(LabOrders.list_lab_orders(ctx.admin.organization_id)) == 1
    end

    test "shows flash error and writes nothing when no tests submitted", ctx do
      patient = patient_fixture(%{organization_id: ctx.admin.organization_id})

      {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      html =
        view
        |> form("#new-lab-order-form", %{
          "lab_order" => %{
            "patient_id" => to_string(patient.id),
            "site_id" => to_string(ctx.site.id)
          }
        })
        |> render_submit()

      assert html =~ "Add at least one test to the order."
      assert LabOrders.list_lab_orders(ctx.admin.organization_id) == []
    end

    test "hides referral fields by default and reveals them when referral is checked", ctx do
      {:ok, view, html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      refute html =~ "Referring facility"

      html =
        view
        |> form("#new-lab-order-form", %{"lab_order" => %{"is_referral" => "true"}})
        |> render_change()

      assert html =~ "Referring facility"
      assert html =~ "Referring doctor"
    end

    test "referred order without facility and doctor shows validation feedback", ctx do
      patient = patient_fixture(%{organization_id: ctx.admin.organization_id})

      {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      # Reveal the referral fields so they are part of the submitted form.
      view
      |> form("#new-lab-order-form", %{"lab_order" => %{"is_referral" => "true"}})
      |> render_change()

      html =
        view
        |> form("#new-lab-order-form", %{
          "lab_order" => %{
            "patient_id" => to_string(patient.id),
            "site_id" => to_string(ctx.site.id),
            "payment_type" => "Cash",
            "is_referral" => "true",
            "referring_facility" => "",
            "referring_doctor" => ""
          },
          "tests" => %{
            "0" => %{
              "lab_test_id" => to_string(ctx.lab_test.id),
              "sample_type" => "blood"
            }
          }
        })
        |> render_submit()

      assert html =~ "is required for a referral"
      assert LabOrders.list_lab_orders(ctx.admin.organization_id) == []
    end

    test "referred order saves once facility and doctor are provided", ctx do
      patient = patient_fixture(%{organization_id: ctx.admin.organization_id})

      {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      # Reveal the referral fields before filling them in.
      view
      |> form("#new-lab-order-form", %{"lab_order" => %{"is_referral" => "true"}})
      |> render_change()

      view
      |> form("#new-lab-order-form", %{
        "lab_order" => %{
          "patient_id" => to_string(patient.id),
          "site_id" => to_string(ctx.site.id),
          "payment_type" => "Cash",
          "is_referral" => "true",
          "referring_facility" => "General Hospital",
          "referring_doctor" => "Dr. Jane Doe"
        },
        "tests" => %{
          "0" => %{
            "lab_test_id" => to_string(ctx.lab_test.id),
            "sample_type" => "blood"
          }
        }
      })
      |> render_submit()

      assert [order] = LabOrders.list_lab_orders(ctx.admin.organization_id)
      assert order.is_referral == true
      assert order.referring_facility == "General Hospital"
    end

    test "presents payment methods as an approved dropdown", ctx do
      {:ok, _view, html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      # Rendered as a select of approved options, not a free-text field.
      assert html =~ ~s(<select id="lab_order_payment_type-input")

      for method <- ThamaniDawa.PaymentMethods.all() do
        assert html =~ ~s(<option value="#{method}">)
      end
    end

    test "total amount reflects the sum of selected test prices", ctx do
      second_test =
        lab_test_fixture(%{
          organization_id: ctx.admin.organization_id,
          price: Decimal.new("250.00")
        })

      {:ok, view, _html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      # Add a second test row so tests[1] exists in the rendered form
      view |> element("button[phx-click=add_test]") |> render_click()

      html =
        view
        |> form("#new-lab-order-form", %{
          "tests" => %{
            "0" => %{
              "lab_test_id" => to_string(ctx.lab_test.id),
              "sample_type" => ""
            },
            "1" => %{
              "lab_test_id" => to_string(second_test.id),
              "sample_type" => ""
            }
          }
        })
        |> render_change()

      expected = ctx.lab_test.price |> Decimal.add(second_test.price) |> Decimal.to_string()
      assert html =~ expected
    end

    test "renders test item inputs inline without Done or Edit buttons", ctx do
      {:ok, view, html} = live(log_in_user(ctx.conn, ctx.admin), ~p"/lab/orders/new")

      assert html =~ "2. Tests"
      refute html =~ "button[phx-click=collapse_test]"
      refute html =~ "button[phx-click=edit_test]"
      assert has_element?(view, "select[name='tests[0][lab_test_id]']")
      assert has_element?(view, "select[name='tests[0][sample_type]']")
    end
  end

  describe "checkbox lab results" do
    test "renders checkbox options in edit result modal and visual preview badges on show page",
         ctx do
      checkbox_lab_test =
        lab_test_fixture(%{
          organization_id: ctx.admin.organization_id,
          name: "Parasite Screening",
          field_definitions: %{
            "species" => %{"type" => "checkbox", "options" => ["P. falciparum", "P. vivax"]}
          }
        })

      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})

      result =
        lab_order_result_fixture(%{
          organization_id: ctx.admin.organization_id,
          lab_order_id: lab_order.id,
          lab_test_id: checkbox_lab_test.id
        })

      conn = log_in_user(build_conn(), ctx.admin)
      {:ok, lv, _html} = live(conn, ~p"/lab/orders/#{lab_order.id}/results/#{result.id}/edit")

      assert render(lv) =~ "P. falciparum"
      assert render(lv) =~ "P. vivax"

      # Save results with selected checkbox option
      {:ok, _show_lv, html} =
        lv
        |> form("#result-entry-form", %{"values" => %{"species" => ["P. falciparum"]}})
        |> render_submit()
        |> follow_redirect(conn, ~p"/lab/orders/#{lab_order.id}")

      # Visual preview badge with check icon is rendered instead of raw CSV entry
      assert html =~ "P. falciparum"
      assert html =~ "hero-check"
    end
  end

  describe "payment modal" do
    test "Record payment button opens the payment modal on the order show page", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})

      conn = log_in_user(build_conn(), ctx.admin)

      {:ok, lv, _html} = live(conn, ~p"/lab/orders/#{lab_order.id}/payments/new")

      assert has_element?(lv, "#payment-modal")
      assert render(lv) =~ "Record payment"
    end

    test "cancelling the modal patches back to the lab order", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})
      conn = log_in_user(build_conn(), ctx.admin)

      {:ok, lv, _html} = live(conn, ~p"/lab/orders/#{lab_order.id}/payments/new")

      lv |> element("#payment-modal button[aria-label='Cancel']") |> render_click()

      assert_patch(lv, ~p"/lab/orders/#{lab_order.id}")
      refute has_element?(lv, "#payment-modal")
    end

    test "validation error stays in the modal", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})
      conn = log_in_user(build_conn(), ctx.admin)

      {:ok, lv, _html} = live(conn, ~p"/lab/orders/#{lab_order.id}/payments/new")

      html =
        lv
        |> form("#payment-form", payment: %{payment_type: "", amount: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert has_element?(lv, "#payment-modal")
    end

    test "successfully recording a payment closes the modal and shows a flash", ctx do
      lab_order = lab_order_fixture(%{organization_id: ctx.admin.organization_id})
      conn = log_in_user(build_conn(), ctx.admin)

      {:ok, lv, _html} = live(conn, ~p"/lab/orders/#{lab_order.id}/payments/new")

      lv
      |> form("#payment-form",
        payment: %{payment_type: "Cash", amount: "1200.00"}
      )
      |> render_submit()

      assert_patch(lv, ~p"/lab/orders/#{lab_order.id}")
      assert render(lv) =~ "Payment recorded and completed."
    end
  end
end
