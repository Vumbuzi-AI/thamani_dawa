defmodule ThamaniDawaWeb.PatientLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.PatientsFixtures

  setup do
    admin = user_fixture()
    {:ok, admin: admin}
  end

  describe "Pharmacy PatientLive.Index search" do
    test "searches across entries and filters correctly", %{conn: conn, admin: admin} do
      _p1 =
        patient_fixture(%{
          organization_id: admin.organization_id,
          full_name: "Alpha Patient",
          phone: "0711111111"
        })

      _p2 =
        patient_fixture(%{
          organization_id: admin.organization_id,
          full_name: "Beta Patient",
          phone: "0722222222"
        })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/pharmacy/patients")
      assert html =~ "Alpha Patient"
      assert html =~ "Beta Patient"

      html = lv |> form("#search-form", search: "Alpha") |> render_change()

      assert html =~ "Alpha Patient"
      refute html =~ "Beta Patient"
    end
  end

  describe "Lab LabPatientLive.Index search" do
    test "searches across entries and filters correctly", %{conn: conn, admin: admin} do
      _p1 =
        patient_fixture(%{
          organization_id: admin.organization_id,
          full_name: "Lab Alpha Patient",
          phone: "0711111111"
        })

      _p2 =
        patient_fixture(%{
          organization_id: admin.organization_id,
          full_name: "Lab Beta Patient",
          phone: "0722222222"
        })

      {:ok, lv, html} = live(log_in_user(conn, admin), ~p"/lab/patients")
      assert html =~ "Lab Alpha Patient"
      assert html =~ "Lab Beta Patient"

      html = lv |> form("#search-form", search: "Lab Alpha") |> render_change()

      assert html =~ "Lab Alpha Patient"
      refute html =~ "Lab Beta Patient"
    end

    test "search resets page to 1 and finds items across all pages", %{conn: conn, admin: admin} do
      # Create 12 patients so pagination kicks in if page_size is 10
      for i <- 1..12 do
        num = String.pad_leading(Integer.to_string(i), 2, "0")

        patient_fixture(%{
          organization_id: admin.organization_id,
          full_name: "Patient Number #{i}",
          phone: "07123456#{num}"
        })
      end

      _target =
        patient_fixture(%{
          organization_id: admin.organization_id,
          full_name: "Unique SearchTarget",
          phone: "0799999999"
        })

      # Access page 2 directly
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/pharmacy/patients?page=2")

      # Search for item that might not be on page 2 originally
      html = lv |> form("#search-form", search: "SearchTarget") |> render_change()

      assert html =~ "Unique SearchTarget"
    end
  end
end
