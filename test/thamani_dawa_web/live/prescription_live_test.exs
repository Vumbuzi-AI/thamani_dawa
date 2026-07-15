defmodule ThamaniDawaWeb.PrescriptionLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PatientsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.ProductsFixtures
  import ThamaniDawa.SitesFixtures
  import ThamaniDawa.PatientVisitsFixtures
  import ThamaniDawa.PrescriptionsFixtures

  defp pharmacist_at_site(organization, site) do
    staff_fixture(%{organization_id: organization.id, site_id: site.id})
  end

  describe "Index" do
    test "creates a prescription for an existing patient", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               index_live
               |> form("form",
                 prescription: %{
                   patient_id: patient.id,
                   referring_doctor: "Dr. Smith",
                   payment_type: "Cash",
                   notes: "Some notes",
                   items: %{
                     "0" => %{product_id: product.id, quantity_prescribed: "1"}
                   }
                 }
               )
               |> render_submit()

      assert to =~ "/pharmacy/prescriptions/"
    end

    test "creates a prescription with an inline new patient", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("a", "New Patient") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

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
                   notes: "Some notes",
                   items: %{
                     "0" => %{product_id: product.id, quantity_prescribed: "1"}
                   }
                 }
               )
               |> render_submit()

      assert to =~ "/pharmacy/prescriptions/"
    end

    test "creates a prescription with multiple items", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product1 = product_fixture(%{organization_id: organization.id})
      product2 = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product1.id
      })

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product2.id
      })

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

      index_live
      |> form("form",
        prescription: %{
          patient_id: patient.id,
          referring_doctor: "Dr. Smith",
          payment_type: "Cash",
          items: %{
            "0" => %{
              product_id: product1.id,
              quantity_prescribed: "10",
              dosage_instructions: "Take 1",
              frequency: "1x3"
            }
          }
        }
      )
      |> render_change()

      assert index_live |> element("button", "+ Add Item") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               index_live
               |> form("form",
                 prescription: %{
                   patient_id: patient.id,
                   referring_doctor: "Dr. Smith",
                   payment_type: "Cash",
                   items: %{
                     "0" => %{
                       product_id: product1.id,
                       quantity_prescribed: "10",
                       dosage_instructions: "Take 1"
                     },
                     "1" => %{
                       product_id: product2.id,
                       quantity_prescribed: "5",
                       dosage_instructions: "Take 2"
                     }
                   }
                 }
               )
               |> render_submit()

      assert to =~ "/pharmacy/prescriptions/"

      id = to |> String.split("/") |> List.last()
      prescription = ThamaniDawa.Prescriptions.get_prescription!(organization.id, id)
      items = ThamaniDawa.Prescriptions.list_prescription_items(organization.id, prescription.id)
      assert length(items) == 2
    end

    test "validates item quantities and product presence", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      %{id: product_id} = product_fixture(%{organization_id: organization.id})

      batch_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        product_id: product_id
      })

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

      html =
        index_live
        |> form("form",
          prescription: %{
            patient_id: patient.id,
            referring_doctor: "Dr. Smith",
            payment_type: "Cash",
            items: %{
              "0" => %{
                quantity_prescribed: "0"
              }
            }
          }
        )
        |> render_change()

      assert html =~ "must be greater than 0"
      assert html =~ "can&#39;t be blank"

      assert index_live |> element("button", "+ Add Item") |> render_click()

      assert index_live
             |> has_element?("input[name=\"prescription[items][1][quantity_prescribed]\"]")

      assert index_live |> element("button[phx-value-index='1']", "Remove") |> render_click()

      refute index_live
             |> has_element?("input[name=\"prescription[items][1][quantity_prescribed]\"]")
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

  describe "Show" do
    setup %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id, gtin: "12345678901231"})

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
        patient: patient,
        pharmacist: pharmacist,
        product: product,
        patient_visit: patient_visit,
        prescription: prescription,
        item: item,
        conn: log_in_user(conn, pharmacist)
      }
    end

    test "dispenses an item successfully when stock is available", %{
      conn: conn,
      organization: org,
      site: site,
      product: product,
      prescription: prescription,
      item: item
    } do
      batch =
        batch_fixture(%{
          organization_id: org.id,
          site_id: site.id,
          product_id: product.id,
          quantity: 50,
          remaining_quantity: 50
        })

      {:ok, show_live, html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert html =~ "Prescription for"
      name = product.generic_name || product.brand_name || "(unnamed)"
      assert html =~ name

      assert show_live
             |> form("form", %{"item_id" => item.id, "quantity" => "4"})
             |> render_submit()

      assert render(show_live) =~ "Item dispensed."

      updated_batch = ThamaniDawa.Batches.get_batch!(org.id, batch.id)
      assert updated_batch.remaining_quantity == 46

      # The UI should now reflect Dispensed: 4
      assert render(show_live) =~ "Dispensed:\u003C/strong> 4"
    end

    test "displays error when there is insufficient stock", %{
      conn: conn,
      prescription: prescription,
      item: item
    } do
      # No batches created

      {:ok, show_live, _html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert show_live
             |> form("form", %{"item_id" => item.id, "quantity" => "4"})
             |> render_submit()

      assert render(show_live) =~ "No stock available at this site for this product."
    end

    test "displays error when trying to over-dispense", %{
      conn: conn,
      organization: org,
      site: site,
      product: product,
      prescription: prescription,
      item: item
    } do
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 50,
        remaining_quantity: 50
      })

      {:ok, show_live, _html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert show_live
             # Prescribed is 10
             |> form("form", %{"item_id" => item.id, "quantity" => "11"})
             |> render_submit()

      assert render(show_live) =~ "That would dispense more than was prescribed."
    end

    test "verifies item when scanned GTIN matches the product", %{
      conn: conn,
      organization: org,
      site: site,
      product: product,
      prescription: prescription,
      item: item
    } do
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 50,
        remaining_quantity: 50
      })

      # First dispense the item
      {:ok, show_live, _html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert show_live
             |> form("form", %{"item_id" => item.id, "quantity" => "4"})
             |> render_submit()

      # Now verify it
      assert show_live
             |> form("form[phx-submit='verify_item']", %{
               "item_id" => item.id,
               "gtin" => product.gtin
             })
             |> render_submit()

      assert render(show_live) =~ "Item verified successfully."
      assert render(show_live) =~ "Verified"
    end

    test "fails to verify when scanned GTIN does not match", %{
      conn: conn,
      organization: org,
      site: site,
      product: product,
      prescription: prescription,
      item: item
    } do
      batch_fixture(%{
        organization_id: org.id,
        site_id: site.id,
        product_id: product.id,
        quantity: 50,
        remaining_quantity: 50
      })

      {:ok, show_live, _html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert show_live
             |> form("form", %{"item_id" => item.id, "quantity" => "4"})
             |> render_submit()

      assert show_live
             |> form("form[phx-submit='verify_item']", %{
               "item_id" => item.id,
               "gtin" => "12345678901248"
             })
             |> render_submit()

      assert render(show_live) =~ "GTIN mismatch. This is the wrong product."
    end
  end
end
