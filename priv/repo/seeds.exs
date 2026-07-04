alias ThamaniDawa.Accounts
alias ThamaniDawa.Accounts.User
alias ThamaniDawa.Batches
alias ThamaniDawa.Batches.Batch
alias ThamaniDawa.DangerousDrugRegisters
alias ThamaniDawa.DangerousDrugRegisters.DangerousDrugRegister
alias ThamaniDawa.Gtin
alias ThamaniDawa.LabOrders
alias ThamaniDawa.LabOrders.{LabConsumableUsage, LabOrder, LabOrderTest}
alias ThamaniDawa.LabTestTemplates
alias ThamaniDawa.LabTestTemplates.{LabTestCategory, LabTestTemplate}
alias ThamaniDawa.LabTests
alias ThamaniDawa.LabTests.LabTest
alias ThamaniDawa.Organizations
alias ThamaniDawa.Organizations.Organization
alias ThamaniDawa.Patients
alias ThamaniDawa.Patients.Patient
alias ThamaniDawa.PharmacyLogs
alias ThamaniDawa.PharmacyLogs.PharmacyLog
alias ThamaniDawa.Prescriptions
alias ThamaniDawa.Prescriptions.{DispensedItem, Prescription, PrescriptionItem}
alias ThamaniDawa.Products
alias ThamaniDawa.Products.Product
alias ThamaniDawa.QualityAssuranceCharts
alias ThamaniDawa.QualityAssuranceCharts.QualityAssuranceChart
alias ThamaniDawa.Repo
alias ThamaniDawa.ScanEvents
alias ThamaniDawa.ScanEvents.ScanEvent
alias ThamaniDawa.Sites
alias ThamaniDawa.Sites.Site
alias ThamaniDawa.Suppliers
alias ThamaniDawa.Suppliers.Supplier

import Ecto.Query, warn: false

password = "password1234"
pin = "1234"
today = Date.utc_today()
now = DateTime.utc_now(:second)

gtin = fn base ->
  {:ok, code} = Gtin.generate(base)
  code
end

insert_or_get = fn schema, lookup, attrs, create_fun ->
  case Repo.get_by(schema, lookup) do
    nil ->
      {:ok, record} = create_fun.(Map.merge(lookup, attrs))
      record

    record ->
      record
  end
end

org_result =
  case Repo.get_by(Organization, slug: "demo-care") do
    nil ->
      {:ok, result} =
        Organizations.signup(
          %{
            name: "Demo Care Pharmacy and Lab",
            slug: "demo-care",
            license_number: "KMPDB-DEMO-001"
          },
          %{name: "Admin User", email: "admin@example.com", password: password}
        )

      result

    organization ->
      site =
        Repo.one(
          from s in Site,
            where: s.organization_id == ^organization.id,
            order_by: [asc: s.id],
            limit: 1
        ) ||
          insert_or_get.(
            Site,
            %{organization_id: organization.id, name: organization.name},
            %{site_type: :pharmacy},
            fn attrs ->
              Sites.create_site(organization.id, attrs)
            end
          )

      user = Accounts.get_user_by_email("admin@example.com")
      %{organization: organization, site: site, user: user}
  end

organization = org_result.organization
admin = org_result.user
organization_id = organization.id

pharmacy_site =
  org_result.site
  |> Sites.update_site(%{
    name: "Demo Care Main Pharmacy",
    site_type: :pharmacy,
    gln: "6160001000001",
    address: "Kimathi Street, Nairobi"
  })
  |> case do
    {:ok, site} -> site
    {:error, _changeset} -> org_result.site
  end

lab_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Diagnostic Lab"},
    %{
      site_type: :lab,
      gln: "6160001000018",
      address: "Kimathi Street, 2nd Floor"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

warehouse_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Central Store"},
    %{
      site_type: :warehouse,
      gln: "6160001000025",
      address: "Industrial Area, Nairobi"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

staff_user = fn email, name, role, site ->
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, invited, _token} =
        Accounts.invite_user(organization_id, admin.id, %{
          email: email,
          name: name,
          role: role,
          site_id: site.id
        })

      {:ok, user} = Accounts.accept_invite(invited, %{password: password})
      {:ok, user} = Accounts.set_user_pin(user, %{pin: pin})
      user

    %User{} = user ->
      if is_nil(user.hashed_pin) do
        {:ok, user} = Accounts.set_user_pin(user, %{pin: pin})
        user
      else
        user
      end
  end
end

pharmacist = staff_user.("pharmacist@example.com", "Grace Pharmacist", :pharmacist, pharmacy_site)
lab_technician = staff_user.("lab@example.com", "Laban Technician", :lab_technician, lab_site)

{:ok, admin} =
  if is_nil(admin.hashed_pin), do: Accounts.set_user_pin(admin, %{pin: pin}), else: {:ok, admin}

supplier =
  insert_or_get.(
    Supplier,
    %{organization_id: organization_id, name: "MediSource Kenya Ltd"},
    %{
      contact: "Amina Otieno",
      phone: "+254700100200",
      email: "orders@medisource.example",
      gln: "6160002000000"
    },
    fn attrs -> Suppliers.create_supplier(organization_id, attrs) end
  )

paracetamol_gtin = gtin.("0616000100000")
amoxicillin_gtin = gtin.("0616000100001")
morphine_gtin = gtin.("0616000100002")
reagent_gtin = gtin.("0616000100003")

paracetamol =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: paracetamol_gtin},
    %{
      generic_name: "Paracetamol",
      brand_name: "PainAway",
      product_type: :drug,
      category: "Analgesic",
      uom: "tablet",
      is_otc: true,
      reorder_level: 50
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

amoxicillin =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: amoxicillin_gtin},
    %{
      generic_name: "Amoxicillin",
      brand_name: "AmoxiCare",
      product_type: :drug,
      category: "Antibiotic",
      uom: "capsule",
      reorder_level: 40
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

morphine =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: morphine_gtin},
    %{
      generic_name: "Morphine Sulfate",
      brand_name: "M-Sulf",
      product_type: :drug,
      category: "Controlled analgesic",
      uom: "ampoule",
      is_dangerous_drug: true,
      reorder_level: 10
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

reagent =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: reagent_gtin},
    %{
      name: "CBC Reagent Pack",
      product_type: :lab_consumable,
      category: "Hematology",
      uom: "pack",
      reorder_level: 5
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

batch = fn product, site, batch_no, quantity, unit_price ->
  insert_or_get.(
    Batch,
    %{organization_id: organization_id, product_id: product.id, batch_no: batch_no},
    %{
      site_id: site.id,
      gtin: product.gtin,
      manufacture_date: Date.add(today, -90),
      expiry: Date.add(today, 540),
      quantity: quantity,
      remaining_quantity: quantity,
      cost_per_unit: Decimal.new("20.00"),
      unit_price: Decimal.new(unit_price),
      supplier_id: supplier.id,
      received_by_id: pharmacist.id,
      received_at: now
    },
    fn attrs -> Batches.create_batch(organization_id, attrs) end
  )
end

paracetamol_batch = batch.(paracetamol, pharmacy_site, "PCM-2401", 240, "50.00")
_amoxicillin_batch = batch.(amoxicillin, pharmacy_site, "AMX-2401", 120, "120.00")
morphine_batch = batch.(morphine, pharmacy_site, "MOR-2401", 20, "450.00")
reagent_batch = batch.(reagent, lab_site, "CBC-REAG-01", 25, "1500.00")
_warehouse_batch = batch.(paracetamol, warehouse_site, "PCM-WH-01", 500, "45.00")

patient =
  insert_or_get.(
    Patient,
    %{organization_id: organization_id, national_id: "DEMO-001"},
    %{
      full_name: "Jane Wanjiku",
      age: 34,
      gender: "female",
      phone: "+254711000111"
    },
    fn attrs -> Patients.create_patient(organization_id, attrs) end
  )

_second_patient =
  insert_or_get.(
    Patient,
    %{organization_id: organization_id, national_id: "DEMO-002"},
    %{
      full_name: "Peter Mwangi",
      date_of_birth: ~D[1988-05-12],
      gender: "male",
      phone: "+254722000222"
    },
    fn attrs -> Patients.create_patient(organization_id, attrs) end
  )

prescription =
  insert_or_get.(
    Prescription,
    %{
      organization_id: organization_id,
      patient_id: patient.id,
      prescriber_reg_no: "DOC-DEMO-01"
    },
    %{
      site_id: pharmacy_site.id,
      prescriber_name: "Dr. Demo",
      entered_by_id: pharmacist.id,
      payment_type: "cash",
      has_paid: true,
      total_amount: Decimal.new("250.00"),
      notes: "Seed prescription for the pharmacy workflow"
    },
    fn attrs -> Prescriptions.create_prescription(organization_id, attrs) end
  )

prescription_item =
  insert_or_get.(
    PrescriptionItem,
    %{
      organization_id: organization_id,
      prescription_id: prescription.id,
      product_id: paracetamol.id
    },
    %{
      quantity_prescribed: 10,
      dosage_instructions: "Take two tablets after meals",
      frequency: "twice daily",
      duration_in_days: 5,
      route_of_administration: "oral"
    },
    fn attrs ->
      Prescriptions.create_prescription_item(organization_id, prescription.id, attrs)
    end
  )

dispensed_item =
  case Repo.get_by(DispensedItem,
         organization_id: organization_id,
         prescription_item_id: prescription_item.id
       ) do
    nil ->
      {:ok, dispensed_item} =
        Prescriptions.dispense_item(organization_id, prescription_item.id, pharmacist.id, 4)

      dispensed_item

    dispensed_item ->
      dispensed_item
  end

_category =
  insert_or_get.(
    LabTestCategory,
    %{organization_id: organization_id, name: "Hematology"},
    %{
      description: "Blood count and morphology tests",
      display_order: 1
    },
    fn attrs -> LabTestTemplates.create_lab_test_category(organization_id, attrs) end
  )

cbc_template =
  insert_or_get.(
    LabTestTemplate,
    %{organization_id: organization_id, name: "Complete Blood Count"},
    %{
      short_name: "CBC",
      display_order: 1,
      field_definitions: [
        %{
          key: "hemoglobin",
          label: "Hemoglobin",
          unit: "g/dL",
          data_type: :numeric,
          low: 12.0,
          high: 17.5
        },
        %{
          key: "wbc",
          label: "White blood cells",
          unit: "10^9/L",
          data_type: :numeric,
          low: 4.0,
          high: 11.0
        }
      ]
    },
    fn attrs -> LabTestTemplates.create_lab_test_template(organization_id, attrs) end
  )

cbc_test =
  insert_or_get.(
    LabTest,
    %{organization_id: organization_id, name: "Complete Blood Count"},
    %{
      price: Decimal.new("800.00"),
      subsidized_price: Decimal.new("500.00")
    },
    fn attrs -> LabTests.create_lab_test(organization_id, attrs) end
  )

lab_order =
  insert_or_get.(
    LabOrder,
    %{
      organization_id: organization_id,
      patient_id: patient.id,
      prescriber_name: "Dr. Demo"
    },
    %{
      site_id: lab_site.id,
      ordered_by_id: lab_technician.id,
      urgency: "routine",
      payment_type: "cash",
      has_paid: true,
      total_amount: Decimal.new("800.00"),
      sample_collection_date: today,
      sample_collection_description: "Venous blood sample"
    },
    fn attrs -> LabOrders.create_lab_order(organization_id, attrs) end
  )

lab_order_test =
  insert_or_get.(
    LabOrderTest,
    %{
      organization_id: organization_id,
      lab_order_id: lab_order.id,
      lab_test_id: cbc_test.id
    },
    %{
      template_id: cbc_template.id
    },
    fn attrs -> LabOrders.create_lab_order_test(organization_id, lab_order.id, attrs) end
  )

if lab_order_test.status == :pending do
  {:ok, lab_order_test} =
    LabOrders.mark_sample_collected(organization_id, lab_order_test.id, today)

  {:ok, lab_order_test} =
    LabOrders.record_result(organization_id, lab_order_test.id, lab_technician.id, %{
      "hemoglobin" => "13.4",
      "wbc" => "7.2"
    })

  {:ok, _lab_order_test} =
    LabOrders.verify_lab_order_test(organization_id, lab_order_test.id, admin.id)
end

if Repo.get_by(LabConsumableUsage,
     organization_id: organization_id,
     batch_id: reagent_batch.id,
     lab_order_id: lab_order.id
   ) ==
     nil do
  {:ok, _usage} =
    LabOrders.record_consumable_usage(organization_id, reagent_batch.id, lab_technician.id, 1,
      lab_order_id: lab_order.id,
      purpose: "CBC reagent use"
    )
end

month = today.month
year = today.year

if Repo.get_by(PharmacyLog,
     organization_id: organization_id,
     site_id: pharmacy_site.id,
     log_type: "fridge_temperature",
     month: month,
     year: year
   ) == nil do
  {:ok, _log} =
    PharmacyLogs.record_daily_entry(
      organization_id,
      pharmacy_site.id,
      "fridge_temperature",
      month,
      year,
      today.day,
      %{
        "reading" => "4.2 C",
        "notes" => "Seed opening reading",
        "recorded_by_id" => pharmacist.id
      }
    )
end

if Repo.get_by(DangerousDrugRegister,
     organization_id: organization_id,
     site_id: pharmacy_site.id,
     product_id: morphine.id,
     month: month,
     year: year
   ) == nil do
  {:ok, _register} =
    DangerousDrugRegisters.record_entry(
      organization_id,
      pharmacy_site.id,
      morphine.id,
      month,
      year,
      %{
        "quantity" => "2",
        "balance" => Integer.to_string(morphine_batch.remaining_quantity),
        "dispensed_to" => "Demo ward stock",
        "recorded_by_id" => pharmacist.id,
        "recorded_at" => DateTime.to_iso8601(now)
      }
    )
end

if Repo.get_by(QualityAssuranceChart,
     organization_id: organization_id,
     site_id: lab_site.id,
     chart_type: "control_chart",
     month: month,
     year: year
   ) == nil do
  {:ok, _chart} =
    QualityAssuranceCharts.record_daily_entry(
      organization_id,
      lab_site.id,
      "control_chart",
      month,
      year,
      today.day,
      %{
        "reading" => "within range",
        "notes" => "Seed QC control",
        "recorded_by_id" => lab_technician.id
      }
    )
end

scan_payload =
  "01#{paracetamol_batch.gtin}10#{paracetamol_batch.batch_no}#{<<29>>}414#{pharmacy_site.gln}"

if Repo.get_by(ScanEvent,
     organization_id: organization_id,
     event_type: :dispense,
     reference_id: dispensed_item.id,
     user_id: pharmacist.id
   ) == nil do
  {:ok, _scan_event} =
    ScanEvents.log_scan_event(
      organization_id,
      :dispense,
      dispensed_item.id,
      pharmacist.id,
      scan_payload
    )
end

IO.puts("""

Seed complete.

Organization: #{organization.name}
Sites: #{pharmacy_site.name}, #{lab_site.name}, #{warehouse_site.name}

Seeded logins:
  admin@example.com / #{password}       role=admin          pin=#{pin}
  pharmacist@example.com / #{password}  role=pharmacist     pin=#{pin}
  lab@example.com / #{password}         role=lab_technician pin=#{pin}
""")
