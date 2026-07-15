defmodule ThamaniDawaWeb.PrescriptionLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.SitesFixtures

  defp pharmacist_at_site(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "Index" do
    test "creates a prescription for an existing patient", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               index_live
               |> form("form",
                 prescription: %{
                   patient_id: patient.id,
                   referring_doctor: "Dr. Smith",
                   payment_type: "Cash",
                   notes: "Some notes"
                 }
               )
               |> render_submit()

      assert to =~ "/pharmacy/prescriptions/"
    end

    test "creates a prescription with an inline new patient", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      assert index_live |> element("a", "New Patient") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               index_live
               |> form("form",
                 patient: %{
                   full_name: "Jane Doe",
                   age: "30",
                   phone: "0712345678",
                   national_id: "12345678",
                   gsrn: "123456789"
                 },
                 prescription: %{
                   referring_doctor: "Dr. Smith",
                   payment_type: "Cash",
                   notes: "Some notes"
                 }
               )
               |> render_submit()

      assert to =~ "/pharmacy/prescriptions/"
    end

    test "shows error on patient_id when submitting without selecting an existing patient", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      html =
        index_live
        |> form("form",
          prescription: %{
            patient_id: "",
            referring_doctor: "Dr. Smith",
            payment_type: "Cash"
          }
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end
end
