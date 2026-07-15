alias ThamaniDawa.Accounts
alias ThamaniDawa.Accounts.User
alias ThamaniDawa.Batches
alias ThamaniDawa.Batches.Batch
alias ThamaniDawa.Gtin
alias ThamaniDawa.LabOrders
alias ThamaniDawa.LabOrders.{LabConsumableUsage, LabOrder, LabOrderResult}
alias ThamaniDawa.LabTests
alias ThamaniDawa.LabTests.LabTest
alias ThamaniDawa.Organizations
alias ThamaniDawa.Organizations.Organization
alias ThamaniDawa.Patients
alias ThamaniDawa.Patients.Patient
alias ThamaniDawa.PatientVisits
alias ThamaniDawa.PatientVisits.PatientVisit
alias ThamaniDawa.Prescriptions
alias ThamaniDawa.Prescriptions.{Prescription, PrescriptionItem}
alias ThamaniDawa.Products
alias ThamaniDawa.Products.Product
alias ThamaniDawa.Repo
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
            %{site_type: :pharmacy, lat: 0, long: 0},
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
      address: "Kimathi Street, 2nd Floor",
      lat: 0,
      long: 0
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
      address: "Industrial Area, Nairobi",
      lat: 0,
      long: 0
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
      site_id: pharmacy_site.id,
      generic_name: "Paracetamol",
      brand_name: "PainAway",
      product_type: :drug,
      category: "Analgesic",
      uom: "tablet",
      gtin: paracetamol_gtin,
      is_otc: true,
      reorder_level: 50,
      price: 200
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

amoxicillin =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: amoxicillin_gtin},
    %{
      site_id: pharmacy_site.id,
      generic_name: "Amoxicillin",
      brand_name: "AmoxiCare",
      product_type: :drug,
      category: "Antibiotic",
      uom: "capsule",
      gtin: amoxicillin_gtin,
      reorder_level: 40,
      price: 250
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

morphine =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: morphine_gtin},
    %{
      site_id: pharmacy_site.id,
      generic_name: "Morphine Sulfate",
      brand_name: "M-Sulf",
      product_type: :drug,
      category: "Controlled analgesic",
      uom: "ampoule",
      gtin: morphine_gtin,
      is_dangerous_drug: true,
      reorder_level: 10,
      price: 450
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

reagent =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: reagent_gtin},
    %{
      site_id: lab_site.id,
      name: "CBC Reagent Pack",
      product_type: :lab_consumable,
      category: "Hematology",
      uom: "pack",
      gtin: reagent_gtin,
      reorder_level: 5,
      price: 1200
    },
    fn attrs -> Products.create_product(organization_id, attrs) end
  )

ample_gtin = gtin.("0616000100004")

ample_product =
  insert_or_get.(
    Product,
    %{organization_id: organization_id, gtin: ample_gtin},
    %{
      site_id: pharmacy_site.id,
      generic_name: "Ample Product",
      brand_name: "AmpleSupply",
      product_type: :drug,
      category: "Pharmacy Test",
      uom: "tablet",
      gtin: ample_gtin,
      is_otc: true,
      reorder_level: 20,
      price: 180
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
      expiry_date: Date.add(today, 540),
      quantity: quantity,
      remaining_quantity: quantity,
      cost_per_unit: Decimal.new("20.00"),
      unit_price: Decimal.new(unit_price),
      supplier_id: supplier.id,
      received_by_id: pharmacist.id,
      received_at: now,
      approver_id: pharmacist.id
    },
    fn attrs -> Batches.create_batch(organization_id, attrs) end
  )
end

pending_batch = fn product, site, batch_no, quantity, unit_price ->
  insert_or_get.(
    Batch,
    %{organization_id: organization_id, product_id: product.id, batch_no: batch_no},
    %{
      site_id: site.id,
      gtin: product.gtin,
      manufacture_date: Date.add(today, -30),
      expiry_date: Date.add(today, 365),
      quantity: quantity,
      supplier_id: supplier.id,
      unit_price: Decimal.new(unit_price)
    },
    fn attrs -> Batches.create_batch(organization_id, attrs) end
  )
end

paracetamol_batch = batch.(paracetamol, pharmacy_site, "PCM-2401", 240, "50.00")
_amoxicillin_batch = batch.(amoxicillin, pharmacy_site, "AMX-2401", 120, "120.00")
morphine_batch = batch.(morphine, pharmacy_site, "MOR-2401", 20, "450.00")
reagent_batch = batch.(reagent, lab_site, "CBC-REAG-01", 25, "1500.00")
pending_ample_batch = pending_batch.(ample_product, pharmacy_site, "AMPLE-2401", 100, "55.00")

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

pharmacy_visit =
  insert_or_get.(
    PatientVisit,
    %{organization_id: organization_id, patient_id: patient.id, site_id: pharmacy_site.id},
    %{
      user_id: pharmacist.id,
      visit_type: :pharmacy
    },
    fn attrs -> ThamaniDawa.PatientVisits.create_patient_visit(organization_id, attrs) end
  )

prescription =
  insert_or_get.(
    Prescription,
    %{
      organization_id: organization_id,
      patient_visit_id: pharmacy_visit.id
    },
    %{
      user_id: pharmacist.id,
      referring_doctor: "Dr. Demo",
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

_dispensed_item =
  if prescription_item.quantity_dispensed < prescription_item.quantity_prescribed do
    {:ok, dispensed_item} =
      Prescriptions.dispense_item(organization_id, prescription_item.id, pharmacist.id, 4)

    dispensed_item
  else
    prescription_item
  end

cbc_test =
  insert_or_get.(
    LabTest,
    %{organization_id: organization_id, name: "Complete Blood Count"},
    %{
      price: Decimal.new("800.00"),
      field_definitions: %{},
      category: "Hematology"
    },
    fn attrs -> LabTests.create_lab_test(organization_id, attrs) end
  )

patient_visit =
  insert_or_get.(
    PatientVisit,
    %{organization_id: organization_id, patient_id: patient.id, site_id: lab_site.id},
    %{
      user_id: lab_technician.id,
      visit_type: :lab
    },
    fn attrs -> PatientVisits.create_patient_visit(organization_id, attrs) end
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
      patient_visit_id: patient_visit.id,
      ordered_by_id: lab_technician.id,
      urgency: "routine",
      payment_type: "cash",
      has_paid: true,
      total_amount: Decimal.new("800.00"),
      lab_request: "Complete blood count",
      referring_facility: "Demo Care Diagnostic Lab",
      referring_doctor: "Dr. Demo",
      referred_date: ~T[09:00:00]
    },
    fn attrs -> LabOrders.create_lab_order(organization_id, attrs) end
  )

lab_order_result =
  insert_or_get.(
    LabOrderResult,
    %{
      organization_id: organization_id,
      lab_order_id: lab_order.id,
      lab_test_id: cbc_test.id
    },
    %{
      sample_collection_description: 1
    },
    fn attrs -> LabOrders.create_lab_order_result(organization_id, lab_order.id, attrs) end
  )

if lab_order_result.status == :pending do
  {:ok, lab_order_result} =
    LabOrders.mark_sample_collected(organization_id, lab_order_result.id, today)

  {:ok, _lab_order_result} =
    LabOrders.record_result(organization_id, lab_order_result.id, lab_technician.id, %{
      "hemoglobin" => "13.4",
      "wbc" => "7.2"
    })
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

IO.puts("""

Seed complete.

Organization: #{organization.name}
Sites: #{pharmacy_site.name}, #{lab_site.name}, #{warehouse_site.name}

Seeded logins:
  admin@example.com / #{password}       role=admin          pin=#{pin}
  pharmacist@example.com / #{password}  role=pharmacist     pin=#{pin}
  lab@example.com / #{password}         role=lab_technician pin=#{pin}
""")
