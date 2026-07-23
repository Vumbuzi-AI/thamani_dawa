alias ThamaniDawa.Accounts
alias ThamaniDawa.Accounts.User
alias ThamaniDawa.Batches
alias ThamaniDawa.Batches.Batch
alias ThamaniDawa.Gtin
alias ThamaniDawa.LabOrders
alias ThamaniDawa.LabOrders.{LabConsumableUsage, LabOrder, LabOrderResult}
alias ThamaniDawa.LabTests
alias ThamaniDawa.LabTests.{LabTest, LabTestCategory}
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

password = "password"
pin = "1234"
today = Date.utc_today()

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

# Keep reruns of the original demo seed compatible with the new Gmail-only
# credentials. Fresh databases skip this block.
legacy_emails = [
  {"admin@example.com", "admin@gmail.com"},
  {"pharmacist@example.com", "pharmacist@gmail.com"},
  {"lab@example.com", "lab@gmail.com"},
  {"lab2@example.com", "lab2@gmail.com"},
  {"pharmalab@example.com", "pharmalab@gmail.com"}
]

Enum.each(legacy_emails, fn {old_email, new_email} ->
  if is_nil(Accounts.get_user_by_email(new_email)) do
    case Accounts.get_user_by_email(old_email) do
      nil ->
        :ok

      user ->
        user
        |> Ecto.Changeset.change(email: new_email)
        |> Repo.update!()
    end
  end
end)

org_result =
  case Repo.get_by(Organization, slug: "demo-care") do
    nil ->
      {:ok, result} =
        Organizations.signup(
          %{
            name: "Demo Care Pharmacy and Diagnostics",
            slug: "demo-care",
            license_number: "KMPDB-DEMO-001"
          },
          %{name: "Amina Kamau", email: "admin@gmail.com", password: password}
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
            %{site_type: :pharmacy, lat: -1.2833, long: 36.8167},
            fn attrs -> Sites.create_site(organization.id, attrs) end
          )

      %{
        organization: organization,
        site: site,
        user: Accounts.get_user_by_email("admin@gmail.com")
      }
  end

organization = org_result.organization
organization_id = organization.id
primary_admin = org_result.user

pharmacy_site =
  org_result.site
  |> Sites.update_site(%{
    name: "Demo Care CBD Pharmacy",
    site_type: :pharmacy,
    gln: "6160001000001",
    address: "Kimathi Street, Nairobi CBD",
    lat: -1.2833,
    long: 36.8167
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
      address: "Kimathi Street, 2nd Floor, Nairobi",
      lat: -1.2831,
      long: 36.8169
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

combined_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Westlands Medical Centre"},
    %{
      site_type: :pharmacy_lab,
      gln: "6160001000025",
      address: "Woodvale Grove, Westlands, Nairobi",
      lat: -1.2676,
      long: 36.8108
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

warehouse_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Central Store"},
    %{
      site_type: :warehouse,
      gln: "6160001000032",
      address: "Enterprise Road, Industrial Area, Nairobi",
      lat: -1.3106,
      long: 36.8554
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

ensure_account = fn email, name, role, site ->
  site_id = if site, do: site.id, else: nil

  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, invited, _token} =
          Accounts.invite_user(organization_id, primary_admin.id, %{
            email: email,
            name: name,
            role: role,
            site_id: site_id
          })

        {:ok, accepted} = Accounts.accept_invite(invited, %{password: password})
        accepted

      %User{} = existing ->
        existing
        |> Ecto.Changeset.change(name: name, role: role, site_id: site_id, is_active: true)
        |> Repo.update!()
    end

  if is_nil(user.hashed_pin) do
    {:ok, user} = Accounts.set_user_pin(user, %{pin: pin})
    user
  else
    user
  end
end

account_specs = [
  {"admin@gmail.com", "Amina Kamau", :admin, nil},
  {"admin2@gmail.com", "Brian Otieno", :admin, nil},
  {"admin3@gmail.com", "Carol Wanjiru", :admin, nil},
  {"admin4@gmail.com", "David Mwangi", :admin, nil},
  {"pharmacist@gmail.com", "Grace Njeri", :pharmacist, pharmacy_site},
  {"pharmacist2@gmail.com", "Kevin Kiptoo", :pharmacist, pharmacy_site},
  {"pharmacist3@gmail.com", "Linda Achieng", :pharmacist, combined_site},
  {"pharmacist4@gmail.com", "Moses Mutua", :pharmacist, combined_site},
  {"lab@gmail.com", "Laban Omondi", :lab_technician, lab_site},
  {"lab2@gmail.com", "Amara Hassan", :lab_technician, lab_site},
  {"lab3@gmail.com", "Faith Chebet", :lab_technician, combined_site},
  {"lab4@gmail.com", "George Maina", :lab_technician, combined_site},
  {"pharmalab@gmail.com", "Zawadi Muthoni", :pharma_lab, combined_site},
  {"pharmalab2@gmail.com", "Ian Kariuki", :pharma_lab, combined_site},
  {"pharmalab3@gmail.com", "Joy Atieno", :pharma_lab, combined_site},
  {"pharmalab4@gmail.com", "Noah Wafula", :pharma_lab, combined_site}
]

accounts =
  Map.new(account_specs, fn {email, name, role, site} ->
    {email, ensure_account.(email, name, role, site)}
  end)

primary_admin = Map.fetch!(accounts, "admin@gmail.com")
primary_pharmacist = Map.fetch!(accounts, "pharmacist@gmail.com")
branch_pharmacist = Map.fetch!(accounts, "pharmacist3@gmail.com")
primary_lab_technician = Map.fetch!(accounts, "lab@gmail.com")
branch_lab_technician = Map.fetch!(accounts, "lab3@gmail.com")

supplier_specs = [
  {"MediSource Kenya Ltd", "Amina Otieno", "+254700100200", "medisource@gmail.com",
   "6160002000000", "Mombasa Road, Nairobi"},
  {"PharmaLink Distributors", "John Kibet", "+254711200300", "pharmalink@gmail.com",
   "6160002000017", "Baba Dogo Road, Nairobi"},
  {"Afya Medical Supplies", "Lucy Wambui", "+254722300400", "afyasupplies@gmail.com",
   "6160002000024", "Nakuru Industrial Park"},
  {"BioLab East Africa", "Peter Ouma", "+254733400500", "biolab@gmail.com", "6160002000031",
   "Athi River EPZ"}
]

suppliers =
  Enum.map(supplier_specs, fn {name, contact, phone, email, gln_code, location} ->
    insert_or_get.(
      Supplier,
      %{organization_id: organization_id, name: name},
      %{
        contact: contact,
        phone: phone,
        email: email,
        gln: gln_code,
        location: location,
        is_active: true
      },
      fn attrs -> Suppliers.create_supplier(organization_id, attrs) end
    )
  end)

product_specs = [
  {"Paracetamol", "Panadol", "Analgesic", "tablet", true, false, 80, 10, :drug},
  {"Amoxicillin", "Amoxil", "Antibiotic", "capsule", false, false, 50, 25, :drug},
  {"Metformin", "Glucophage", "Antidiabetic", "tablet", false, false, 60, 15, :drug},
  {"Amlodipine", "Norvasc", "Antihypertensive", "tablet", false, false, 40, 20, :drug},
  {"Omeprazole", "Losec", "Gastrointestinal", "capsule", true, false, 35, 18, :drug},
  {"Cetirizine", "Zyrtec", "Antihistamine", "tablet", true, false, 30, 12, :drug},
  {"Salbutamol", "Ventolin", "Respiratory", "inhaler", false, false, 15, 650, :drug},
  {"Azithromycin", "Zithromax", "Antibiotic", "tablet", false, false, 25, 80, :drug},
  {"Diclofenac", "Voltaren", "Anti-inflammatory", "tablet", false, false, 35, 22, :drug},
  {"ORS Sachets", "Hydralyte", "Rehydration", "sachet", true, false, 40, 30, :drug},
  {"Morphine Sulfate", "M-Sulf", "Controlled analgesic", "ampoule", false, true, 12, 450, :drug},
  {"CBC Reagent Pack", nil, "Hematology", "pack", false, false, 8, 1500, :lab_consumable},
  {"Clinical Chemistry Reagent", nil, "Clinical Chemistry", "kit", false, false, 6, 3200,
   :lab_consumable},
  {"Urinalysis Strips", "UroCheck", "Urinalysis", "vial", false, false, 10, 900, :lab_consumable},
  {"HIV Rapid Test Kit", "Determine", "Serology", "kit", false, false, 12, 250, :lab_consumable},
  {"Vacutainer EDTA Tubes", "VacuSafe", "Sample collection", "box", false, false, 10, 1100,
   :lab_consumable}
]

products =
  product_specs
  |> Enum.with_index()
  |> Enum.map(fn {{generic, brand, category, uom, otc, dangerous, reorder, price, type}, index} ->
    code =
      index
      |> then(&:io_lib.format("061600010~4..0B", [&1]))
      |> IO.iodata_to_binary()
      |> gtin.()

    product =
      insert_or_get.(
        Product,
        %{organization_id: organization_id, gtin: code},
        %{
          generic_name: generic,
          brand_name: brand,
          category: category,
          uom: uom,
          is_otc: otc,
          is_dangerous_drug: dangerous,
          reorder_level: reorder,
          price: price
        },
        fn attrs -> Products.create_product(organization_id, attrs) end
      )

    {type, product}
  end)

drug_products = for {:drug, product} <- products, do: product
lab_products = for {:lab_consumable, product} <- products, do: product

create_batch = fn product, site, batch_no, quantity, remaining, expiry_days, supplier, approver ->
  insert_or_get.(
    Batch,
    %{
      organization_id: organization_id,
      product_id: product.id,
      site_id: site.id,
      batch_no: batch_no
    },
    %{
      gtin: product.gtin,
      manufacturer: supplier.name,
      manufacture_date: Date.add(today, -120),
      expiry_date: Date.add(today, expiry_days),
      quantity: quantity,
      remaining_quantity: remaining,
      cost_per_unit: Decimal.new("20.00"),
      supplier_id: supplier.id
    },
    fn attrs ->
      with {:ok, batch} <- Batches.create_batch(organization_id, attrs) do
        if approver, do: Batches.receive_batch(batch, approver.id), else: {:ok, batch}
      end
    end
  )
end

pharmacy_batches =
  for {site, site_code, approver} <- [
        {pharmacy_site, "CBD", primary_pharmacist},
        {combined_site, "WST", branch_pharmacist}
      ],
      {product, index} <- Enum.with_index(drug_products) do
    supplier = Enum.at(suppliers, rem(index, length(suppliers)))
    expiry_days = Enum.at([18, 75, 180, 365], rem(index, 4))
    quantity = 160 + index * 10
    remaining = if rem(index, 5) == 0, do: max(product.reorder_level - 5, 1), else: quantity

    create_batch.(
      product,
      site,
      "#{site_code}-#{index + 1}-A",
      quantity,
      remaining,
      expiry_days,
      supplier,
      approver
    )
  end

lab_batches =
  for {site, site_code, approver} <- [
        {lab_site, "LAB", primary_lab_technician},
        {combined_site, "WLB", branch_lab_technician}
      ],
      {product, index} <- Enum.with_index(lab_products) do
    supplier = Enum.at(suppliers, rem(index + 1, length(suppliers)))

    create_batch.(
      product,
      site,
      "#{site_code}-REAG-#{index + 1}",
      80 + index * 10,
      70 + index * 8,
      Enum.at([25, 120, 240, 400], rem(index, 4)),
      supplier,
      approver
    )
  end

drug_products
|> Enum.take(6)
|> Enum.with_index()
|> Enum.each(fn {product, index} ->
  create_batch.(
    product,
    warehouse_site,
    "WH-#{index + 1}-A",
    500 + index * 50,
    500 + index * 50,
    540,
    Enum.at(suppliers, rem(index, length(suppliers))),
    primary_admin
  )
end)

# Pending receipts ensure both pharmacy-capable sites have actionable stock work.
Enum.each(
  [
    {pharmacy_site, Enum.at(drug_products, 2), "CBD-PENDING-01"},
    {combined_site, Enum.at(drug_products, 3), "WST-PENDING-01"},
    {lab_site, Enum.at(lab_products, 1), "LAB-PENDING-01"},
    {combined_site, Enum.at(lab_products, 2), "WLB-PENDING-01"}
  ],
  fn {site, product, batch_no} ->
    create_batch.(
      product,
      site,
      batch_no,
      100,
      100,
      300,
      Enum.at(suppliers, 1),
      nil
    )
  end
)

patient_specs = [
  {"Jane Wanjiku", ~D[1992-04-18], "female", "+254711000111"},
  {"Peter Mwangi", ~D[1988-05-12], "male", "+254722000222"},
  {"Mary Akinyi", ~D[1979-11-03], "female", "+254733000333"},
  {"Samuel Kiprotich", ~D[2001-01-25], "male", "+254744000444"},
  {"Esther Nyambura", ~D[1996-08-09], "female", "+254755000555"},
  {"Joseph Mutiso", ~D[1968-03-16], "male", "+254766000666"},
  {"Ruth Chepngeno", ~D[1985-07-30], "female", "+254777000777"},
  {"Daniel Odhiambo", ~D[1990-12-14], "male", "+254788000888"},
  {"Mercy Naliaka", ~D[2005-06-20], "female", "+254799000999"},
  {"Paul Kamau", ~D[1974-09-11], "male", "+254710101010"},
  {"Irene Muthoni", ~D[1999-02-28], "female", "+254721111111"},
  {"Brian Ochieng", ~D[1982-10-06], "male", "+254732121212"},
  {"Lucy Wairimu", ~D[1994-01-17], "female", "+254743131313"},
  {"Dennis Wafula", ~D[1987-04-04], "male", "+254754141414"},
  {"Beatrice Jepkoech", ~D[1971-07-22], "female", "+254765151515"},
  {"Eric Musyoka", ~D[2000-05-15], "male", "+254776161616"},
  {"Ann Njeri", ~D[1993-09-19], "female", "+254787171717"},
  {"Collins Onyango", ~D[1980-12-01], "male", "+254798181818"},
  {"Diana Atieno", ~D[2003-03-08], "female", "+254709191919"},
  {"Felix Kariuki", ~D[1977-06-27], "male", "+254720202020"}
]

patients =
  patient_specs
  |> Enum.with_index(1)
  |> Enum.map(fn {{name, dob, gender, phone}, index} ->
    national_id = Integer.to_string(10_000_000 + index)

    insert_or_get.(
      Patient,
      %{organization_id: organization_id, national_id: national_id},
      %{
        full_name: name,
        date_of_birth: dob,
        gender: gender,
        phone: phone,
        gsrn: 616_000_100_000_000_000 + index
      },
      fn attrs -> Patients.create_patient(organization_id, attrs) end
    )
  end)

ensure_visit = fn patient, site, user, type ->
  insert_or_get.(
    PatientVisit,
    %{
      organization_id: organization_id,
      patient_id: patient.id,
      site_id: site.id,
      visit_type: type
    },
    %{user_id: user.id},
    fn attrs -> PatientVisits.create_patient_visit(organization_id, attrs) end
  )
end

prescription_statuses = [
  :pending,
  :partially_dispensed,
  :completed,
  :cancelled,
  :pending,
  :completed,
  :partially_dispensed,
  :completed,
  :pending,
  :cancelled,
  :completed,
  :partially_dispensed
]

patients
|> Enum.take(12)
|> Enum.with_index()
|> Enum.each(fn {patient, index} ->
  {site, pharmacist} =
    if index < 6,
      do: {pharmacy_site, primary_pharmacist},
      else: {combined_site, branch_pharmacist}

  visit = ensure_visit.(patient, site, pharmacist, :pharmacy)
  target_status = Enum.at(prescription_statuses, index)

  prescription =
    insert_or_get.(
      Prescription,
      %{organization_id: organization_id, patient_visit_id: visit.id},
      %{
        user_id: pharmacist.id,
        referring_doctor: Enum.at(["Dr. Kariuki", "Dr. Achieng", "Dr. Hassan"], rem(index, 3)),
        payment_type: Enum.at(["Cash", "Mobile Money", "Insurance"], rem(index, 3)),
        has_paid: target_status in [:completed, :partially_dispensed],
        total_amount: Decimal.new(Integer.to_string(450 + index * 125)),
        status: if(target_status == :cancelled, do: :cancelled, else: :pending),
        notes: "Demo prescription #{index + 1}: review allergies and counsel the patient.",
        doctors_note: "Follow up if symptoms persist after the prescribed course.",
        is_external: rem(index, 4) == 0,
        source_facility: if(rem(index, 4) == 0, do: "Nairobi Community Clinic"),
        referral_date: if(rem(index, 4) == 0, do: Date.add(today, -(index + 1)))
      },
      fn attrs -> Prescriptions.create_prescription(organization_id, attrs) end
    )

  items =
    for offset <- 0..1 do
      product = Enum.at(drug_products, rem(index + offset, length(drug_products)))
      quantity = 6 + offset * 4

      insert_or_get.(
        PrescriptionItem,
        %{
          organization_id: organization_id,
          prescription_id: prescription.id,
          product_id: product.id
        },
        %{
          quantity_prescribed: quantity,
          dosage_instructions:
            if(offset == 0, do: "Take one dose after meals", else: "Take with plenty of water"),
          frequency: if(offset == 0, do: "twice daily", else: "once daily"),
          duration_in_days: 5 + offset * 2,
          route_of_administration: "oral"
        },
        fn attrs ->
          Prescriptions.create_prescription_item(organization_id, prescription.id, attrs)
        end
      )
    end

  if target_status in [:partially_dispensed, :completed] do
    Enum.each(items, fn item ->
      target_quantity =
        if target_status == :completed,
          do: item.quantity_prescribed,
          else: max(div(item.quantity_prescribed, 2), 1)

      quantity_to_dispense = target_quantity - item.quantity_dispensed

      if quantity_to_dispense > 0 do
        {:ok, _item} =
          Prescriptions.dispense_item(
            organization_id,
            item.id,
            pharmacist.id,
            quantity_to_dispense
          )
      end
    end)
  end
end)

category_specs = [
  {"Hematology", "Blood cell counts and morphology", 1},
  {"Clinical Chemistry", "Metabolic, renal, and liver function testing", 2},
  {"Serology", "Antibody and antigen testing", 3},
  {"Microbiology", "Infectious disease microscopy and culture", 4},
  {"Urinalysis", "Physical, chemical, and microscopic urine analysis", 5}
]

categories =
  Map.new(category_specs, fn {name, description, order} ->
    category =
      insert_or_get.(
        LabTestCategory,
        %{organization_id: organization_id, name: name},
        %{description: description, display_order: order},
        fn attrs -> LabTests.create_lab_test_category(organization_id, attrs) end
      )

    {name, category}
  end)

test_specs = [
  {"Complete Blood Count", "Hematology", "800.00",
   %{
     "haemoglobin" => %{"type" => "number", "unit" => "g/dL"},
     "wbc" => %{"type" => "number", "unit" => "×10³/µL"},
     "platelets" => %{"type" => "number", "unit" => "×10³/µL"}
   }},
  {"Malaria Parasite", "Hematology", "450.00",
   %{"parasites" => %{"type" => "select", "options" => ["Not seen", "Seen"]}}},
  {"Blood Group and Rhesus", "Hematology", "500.00",
   %{"blood_group" => %{"type" => "text", "unit" => ""}}},
  {"Liver Function Test", "Clinical Chemistry", "1800.00",
   %{
     "alt" => %{"type" => "number", "unit" => "U/L"},
     "ast" => %{"type" => "number", "unit" => "U/L"}
   }},
  {"Renal Function Test", "Clinical Chemistry", "1600.00",
   %{
     "creatinine" => %{"type" => "number", "unit" => "µmol/L"},
     "urea" => %{"type" => "number", "unit" => "mmol/L"}
   }},
  {"Random Blood Sugar", "Clinical Chemistry", "350.00",
   %{"glucose" => %{"type" => "number", "unit" => "mmol/L"}}},
  {"HIV Rapid Test", "Serology", "500.00",
   %{"result" => %{"type" => "select", "options" => ["Non-reactive", "Reactive"]}}},
  {"Hepatitis B Surface Antigen", "Serology", "900.00",
   %{"result" => %{"type" => "select", "options" => ["Negative", "Positive"]}}},
  {"Urinalysis", "Urinalysis", "600.00",
   %{
     "ph" => %{"type" => "number", "unit" => ""},
     "protein" => %{"type" => "text", "unit" => ""}
   }},
  {"Stool Microscopy", "Microbiology", "700.00",
   %{"ova_cysts" => %{"type" => "text", "unit" => ""}}}
]

lab_tests =
  Enum.map(test_specs, fn {name, category_name, price, fields} ->
    insert_or_get.(
      LabTest,
      %{organization_id: organization_id, name: name},
      %{
        price: Decimal.new(price),
        field_definitions: fields,
        category_id: Map.fetch!(categories, category_name).id,
        is_active: true
      },
      fn attrs -> LabTests.create_lab_test(organization_id, attrs) end
    )
  end)

lab_order_states = [
  :pending,
  :in_progress,
  :completed,
  :completed,
  :cancelled,
  :in_progress,
  :pending,
  :completed,
  :in_progress,
  :completed,
  :cancelled,
  :pending
]

patients
|> Enum.drop(8)
|> Enum.take(12)
|> Enum.with_index()
|> Enum.each(fn {patient, index} ->
  {site, technician} =
    if index < 6,
      do: {lab_site, primary_lab_technician},
      else: {combined_site, branch_lab_technician}

  visit = ensure_visit.(patient, site, technician, :lab)
  target_state = Enum.at(lab_order_states, index)

  lab_order =
    insert_or_get.(
      LabOrder,
      %{
        organization_id: organization_id,
        patient_visit_id: visit.id,
        prescriber_name: Enum.at(["Dr. Wanjala", "Dr. Noor", "Dr. Kilonzo"], rem(index, 3))
      },
      %{
        site_id: site.id,
        ordered_by_id: technician.id,
        urgency: Enum.at(["routine", "urgent", "stat"], rem(index, 3)),
        payment_type: Enum.at(["Cash", "Mobile Money", "Insurance"], rem(index, 3)),
        has_paid: target_state in [:in_progress, :completed],
        total_amount: Decimal.new(Integer.to_string(1200 + index * 250)),
        status: if(target_state == :cancelled, do: :cancelled, else: :pending),
        lab_request: "Run the selected investigations and correlate with the clinical history.",
        lab_report: if(target_state == :completed, do: "Results reviewed and released."),
        test_findings: if(target_state == :completed, do: "Findings documented per test."),
        is_referral: rem(index, 4) == 0,
        referring_facility: if(rem(index, 4) == 0, do: "County Referral Clinic"),
        referring_doctor: if(rem(index, 4) == 0, do: "Dr. Wanjala"),
        referred_date: if(rem(index, 4) == 0, do: Date.add(today, -(index + 2)))
      },
      fn attrs -> LabOrders.create_lab_order(organization_id, attrs) end
    )

  results =
    for offset <- 0..1 do
      lab_test = Enum.at(lab_tests, rem(index + offset, length(lab_tests)))

      insert_or_get.(
        LabOrderResult,
        %{
          organization_id: organization_id,
          lab_order_id: lab_order.id,
          lab_test_id: lab_test.id
        },
        %{sample_type: if(rem(index, 3) == 0, do: :urine, else: :blood)},
        fn attrs -> LabOrders.create_lab_order_result(organization_id, lab_order.id, attrs) end
      )
    end

  case target_state do
    :pending ->
      :ok

    :cancelled ->
      :ok

    :in_progress ->
      result = List.first(results)

      if result.status == :pending do
        {:ok, _result} =
          LabOrders.mark_sample_collected(
            organization_id,
            result.id,
            technician.id,
            %{
              "collection_date" => Date.to_iso8601(today),
              "collection_notes" => "Sample identity confirmed at collection."
            }
          )
      end

    :completed ->
      Enum.each(results, fn result ->
        result =
          if result.status == :pending do
            {:ok, collected} =
              LabOrders.mark_sample_collected(
                organization_id,
                result.id,
                technician.id,
                %{
                  "collection_date" => Date.to_iso8601(today),
                  "collection_notes" => "Good-quality sample received."
                }
              )

            collected
          else
            result
          end

        if result.status != :completed do
          {:ok, _result} =
            LabOrders.record_result(organization_id, result.id, technician.id, %{
              "result" => "Within reference range",
              "value" => Integer.to_string(7 + rem(index, 6)),
              "comment" => "Verified by the seeded laboratory workflow"
            })
        end
      end)
  end

  reagent_batch =
    lab_batches
    |> Enum.filter(&(&1.site_id == site.id))
    |> Enum.at(rem(index, length(lab_products)))

  if target_state in [:in_progress, :completed] and
       is_nil(
         Repo.get_by(LabConsumableUsage,
           organization_id: organization_id,
           batch_id: reagent_batch.id,
           lab_order_id: lab_order.id
         )
       ) do
    {:ok, _usage} =
      LabOrders.record_consumable_usage(organization_id, reagent_batch.id, technician.id, 1,
        lab_order_id: lab_order.id,
        purpose: "Reagent and collection materials for #{lab_order.lab_request}"
      )
  end
end)

role_counts =
  User
  |> where([u], u.organization_id == ^organization_id)
  |> group_by([u], u.role)
  |> select([u], {u.role, count(u.id)})
  |> Repo.all()
  |> Map.new()

expected_role_counts = %{admin: 4, pharmacist: 4, lab_technician: 4, pharma_lab: 4}

if role_counts != expected_role_counts do
  raise """
  Demo account count is not balanced.
  Expected exactly four accounts per role: #{inspect(expected_role_counts)}
  Found: #{inspect(role_counts)}
  """
end

IO.puts("""

Seed complete.

Organization: #{organization.name}
Sites: #{pharmacy_site.name}, #{lab_site.name}, #{combined_site.name}, #{warehouse_site.name}
Data: #{length(products)} products, #{length(pharmacy_batches) + length(lab_batches)} active site batches,
      #{length(suppliers)} suppliers, #{length(patients)} patients,
      12 prescriptions, #{length(lab_tests)} lab tests, and 12 lab orders.

All accounts use password #{password} and PIN #{pin}.

Admin accounts:
  admin@gmail.com, admin2@gmail.com, admin3@gmail.com, admin4@gmail.com

Pharmacist accounts:
  pharmacist@gmail.com, pharmacist2@gmail.com, pharmacist3@gmail.com, pharmacist4@gmail.com

Lab technician accounts:
  lab@gmail.com, lab2@gmail.com, lab3@gmail.com, lab4@gmail.com

Pharmacy + lab accounts:
  pharmalab@gmail.com, pharmalab2@gmail.com, pharmalab3@gmail.com, pharmalab4@gmail.com
""")
