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

    test "referring doctor is hidden and not required unless marked as a referral", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      refute has_element?(index_live, "input[name='prescription[referring_doctor]']")

      html =
        index_live
        |> form("form", prescription: %{is_external: "true"})
        |> render_change()

      assert html =~ "Referring doctor"
      assert has_element?(index_live, "input[name='prescription[referring_doctor]']")

      assert index_live |> element("button", "+ Add Item") |> render_click()

      html =
        index_live
        |> form("form",
          prescription: %{
            patient_id: patient.id,
            is_external: "true",
            payment_type: "Cash",
            items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
          }
        )
        |> render_submit()

      assert html =~ "is required for a referral"
    end

    test "unchecking the referral checkbox hides the referring doctor field again", %{
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
        |> form("form", prescription: %{is_external: "true"})
        |> render_change()

      assert html =~ "Referring doctor"

      html =
        index_live
        |> form("form", prescription: %{is_external: "false"})
        |> render_change()

      refute html =~ "Referring doctor"
      refute has_element?(index_live, "input[name='prescription[referring_doctor]']")
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

    test "adding an item after filling in new-patient fields does not crash", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("a", "New Patient") |> render_click()

      index_live
      |> form("form", patient: %{full_name: "Jane Doe", phone: "0712345678"})
      |> render_change()

      assert index_live |> element("button", "+ Add Item") |> render_click() =~ "Item 1"
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
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

      html =
        index_live
        |> form("form",
          prescription: %{
            patient_id: "",
            payment_type: "Cash",
            items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
          }
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "rejects submitting the form without ever adding an item", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      html =
        index_live
        |> form("form", prescription: %{patient_id: patient.id, payment_type: "Cash"})
        |> render_submit()

      assert html =~ "must have at least one item"
      assert ThamaniDawa.Prescriptions.list_prescriptions(organization.id) == []
    end

    test "shows patient errors instead of creating a prescription when the inline new patient is invalid",
         %{conn: conn} do
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

      html =
        index_live
        |> form("form",
          patient: %{full_name: "", gsrn: ""},
          prescription: %{
            payment_type: "Cash",
            items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
          }
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "a pharmacist with no home site sees a site picker and can create a prescription", %{
      conn: conn
    } do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = staff_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert has_element?(index_live, "select[name='prescription[site_id]']")

      index_live
      |> form("form", prescription: %{site_id: "", notes: "no site chosen yet"})
      |> render_change()

      index_live
      |> form("form", prescription: %{site_id: site.id})
      |> render_change()

      assert index_live |> element("button", "+ Add Item") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               index_live
               |> form("form",
                 prescription: %{
                   site_id: site.id,
                   patient_id: patient.id,
                   payment_type: "Cash",
                   items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
                 }
               )
               |> render_submit()

      assert to =~ "/pharmacy/prescriptions/"
    end

    test "a pharmacist with no home site sees a flash if they submit without choosing a site", %{
      conn: conn
    } do
      organization = organization_fixture()
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = staff_fixture(%{organization_id: organization.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      html =
        index_live
        |> form("form", prescription: %{patient_id: patient.id, payment_type: "Cash"})
        |> render_submit()

      assert html =~ "Site is required."
      assert ThamaniDawa.Prescriptions.list_prescriptions(organization.id) == []
    end

    test "resetting the site back to blank after picking one still shows the site-required flash instead of crashing",
         %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = staff_fixture(%{organization_id: organization.id})
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()

      index_live
      |> form("form", prescription: %{site_id: site.id})
      |> render_change()

      assert index_live |> element("button", "+ Add Item") |> render_click()

      index_live
      |> form("form",
        prescription: %{
          site_id: site.id,
          items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
        }
      )
      |> render_change()

      html =
        index_live
        |> form("form",
          prescription: %{
            site_id: "",
            patient_id: patient.id,
            payment_type: "Cash",
            items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
          }
        )
        |> render_submit()

      assert html =~ "Site is required."
      assert ThamaniDawa.Prescriptions.list_prescriptions(organization.id) == []
    end

    test "collapses and re-expands a prescription item", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id})
      pharmacist = pharmacist_at_site(organization, site)

      product =
        product_fixture(%{organization_id: organization.id, brand_name: "Panadol"})

      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

      index_live
      |> form("form",
        prescription: %{
          patient_id: patient.id,
          payment_type: "Cash",
          items: %{
            "0" => %{
              product_id: product.id,
              quantity_prescribed: "3",
              duration_in_days: "5"
            }
          }
        }
      )
      |> render_change()

      html = index_live |> element("button[phx-value-index='0']", "Done") |> render_click()
      assert html =~ "Qty: 3"
      assert html =~ "Panadol"
      assert html =~ "5 days"

      refute has_element?(
               index_live,
               "input[name=\"prescription[items][0][quantity_prescribed]\"][type=\"number\"]"
             )

      index_live |> element("button[phx-value-index='0']", "Edit") |> render_click()

      assert has_element?(
               index_live,
               "input[name=\"prescription[items][0][quantity_prescribed]\"][type=\"number\"]"
             )
    end

    test "lists a created prescription with its patient, status, and item count", %{conn: conn} do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})
      patient = patient_fixture(%{organization_id: organization.id, full_name: "Jane Listed"})
      pharmacist = pharmacist_at_site(organization, site)
      product = product_fixture(%{organization_id: organization.id})
      batch_fixture(%{organization_id: organization.id, site_id: site.id, product_id: product.id})

      conn = log_in_user(conn, pharmacist)
      {:ok, index_live, _html} = live(conn, ~p"/pharmacy/prescriptions")

      assert index_live |> element("a", "+ New prescription") |> render_click()
      assert index_live |> element("button", "+ Add Item") |> render_click()

      index_live
      |> form("form",
        prescription: %{
          patient_id: patient.id,
          payment_type: "Cash",
          items: %{"0" => %{product_id: product.id, quantity_prescribed: "1"}}
        }
      )
      |> render_submit()

      {:ok, index_live, html} = live(conn, ~p"/pharmacy/prescriptions")

      assert html =~ "Jane Listed"
      assert html =~ "Pending"
      assert has_element?(index_live, "#prescriptions")
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
      assert has_element?(show_live, "button[phx-disable-with='Dispensing...']")

      assert show_live
             |> form("form", %{"item_id" => item.id, "quantity" => "4"})
             |> render_submit()

      assert render(show_live) =~ "Item dispensed."

      updated_batch = ThamaniDawa.Batches.get_batch!(org.id, batch.id)
      assert updated_batch.remaining_quantity == 46

      # The UI should now reflect Dispensed: 4
      assert render(show_live) =~ "Dispensed:\u003C/strong> 4"
    end

    test "colors the status badge green once the prescription is completed", %{
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

      {:ok, show_live, html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")
      refute html =~ "text-green-600"

      show_live
      |> form("form", %{"item_id" => item.id, "quantity" => "10"})
      |> render_submit()

      html = render(show_live)
      assert html =~ "Completed"
      assert html =~ "text-green-600"

      updated_prescription = ThamaniDawa.Prescriptions.get_prescription!(org.id, prescription.id)
      assert updated_prescription.status == :completed
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

    test "a non-numeric dispense quantity shows an error instead of crashing", %{
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
             |> form("form", %{"item_id" => item.id, "quantity" => "abc"})
             |> render_submit()

      assert render(show_live) =~ "Enter a valid quantity."
    end

    test "a zero or negative dispense quantity shows an error instead of crashing", %{
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
             |> form("form", %{"item_id" => item.id, "quantity" => "-5"})
             |> render_submit()

      assert render(show_live) =~ "Enter a valid quantity."
    end

    test "a non-numeric item_id on dispense shows an error instead of crashing", %{
      conn: conn,
      prescription: prescription
    } do
      {:ok, show_live, _html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert show_live
             |> element("form")
             |> render_submit(%{"item_id" => "not-an-id", "quantity" => "4"})

      assert render(show_live) =~ "Enter a valid quantity."
    end

    test "a non-numeric item_id on verify shows an error instead of crashing", %{
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
             |> element("form[phx-submit='verify_item']")
             |> render_submit(%{"item_id" => "not-an-id", "gtin" => product.gtin})

      assert render(show_live) =~ "Couldn&#39;t verify that item."
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

    test "fails to verify when the scanned code is not a valid GTIN", %{
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
               "gtin" => "not-a-gtin"
             })
             |> render_submit()

      assert render(show_live) =~ "Invalid GTIN barcode scanned."
    end

    test "fails to verify when the scanned code is all-digits but not a valid GTIN checksum/length",
         %{
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
               "gtin" => "123"
             })
             |> render_submit()

      assert render(show_live) =~ "Invalid GTIN barcode scanned."
    end

    test "shows the patient's gender when set", %{conn: conn, organization: org, site: site} do
      patient =
        patient_fixture(%{
          organization_id: org.id,
          full_name: "Gendered Patient",
          gender: "Female"
        })

      patient_visit =
        patient_visit_fixture(%{
          organization_id: org.id,
          site_id: site.id,
          patient_id: patient.id
        })

      prescription =
        prescription_fixture(%{organization_id: org.id, patient_visit_id: patient_visit.id})

      {:ok, _show_live, html} = live(conn, ~p"/pharmacy/prescriptions/#{prescription.id}")

      assert html =~ "Female"
    end
  end
end
