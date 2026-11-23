alias ThamaniDawa.Accounts
alias ThamaniDawa.Accounts.User
alias ThamaniDawa.Batches
alias ThamaniDawa.Batches.Batch
alias ThamaniDawa.Distributor
alias ThamaniDawa.Distributor.{Billing, MobileUser, Shipment}
alias ThamaniDawa.CustomerReturns
alias ThamaniDawa.GoodsReceipts
alias ThamaniDawa.Gtin
alias ThamaniDawa.InventoryDisposals
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
alias ThamaniDawa.Payments
alias ThamaniDawa.Payments.Payment
alias ThamaniDawa.Prescriptions
alias ThamaniDawa.Prescriptions.{Prescription, PrescriptionItem}
alias ThamaniDawa.Products
alias ThamaniDawa.Products.Product
alias ThamaniDawa.Repo
alias ThamaniDawa.Requisitions
alias ThamaniDawa.Requisitions.Requisition
alias ThamaniDawa.Sites
alias ThamaniDawa.Sites.Site
alias ThamaniDawa.StockTakes
alias ThamaniDawa.Suppliers
alias ThamaniDawa.Suppliers.Supplier

import Ecto.Query, warn: false

password = "password"
superadmin_password = "password123"
pin = "1234"
today = Date.utc_today()
verified_at = DateTime.utc_now(:second)

gtin = fn base ->
  {:ok, code} = Gtin.generate(base)
  code
end

gln = fn twelve_digit_payload ->
  twelve_digit_payload <>
    Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(twelve_digit_payload))
end

insert_or_get = fn schema, lookup, attrs, create_fun ->
  case Repo.get_by(schema, lookup) do
    nil ->
      case create_fun.(Map.merge(lookup, attrs)) do
        {:ok, record} ->
          record

        {:error, changeset} ->
          raise "Failed to create #{inspect(schema)}: #{inspect(changeset.errors)}"
      end

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

superadmin =
  case Accounts.get_user_by_email("superadmin@gmail.com") do
    nil ->
      {:ok, user} =
        Accounts.create_platform_superadmin(%{
          name: "Platform Superadmin",
          email: "superadmin@gmail.com",
          password: superadmin_password,
          accepted_legal_terms: true
        })

      user

    %User{roles: [:superadmin]} = user ->
      user
      |> Ecto.Changeset.change(hashed_password: Bcrypt.hash_pwd_salt(superadmin_password))
      |> Repo.update!()

    %User{} ->
      raise "superadmin@gmail.com is already assigned to a non-superadmin account"
  end

org_result =
  case Repo.get_by(Organization, slug: "demo-care") do
    nil ->
      {:ok, result} =
        Organizations.signup(
          %{
            name: "Demo Care Pharmacy and Diagnostics",
            slug: "demo-care",
            operating_models: [:pharmacy, :laboratory, :distributor],
            gs1_company_prefix: "6160001"
          },
          %{
            name: "Demo Care Pharmacy and Diagnostics",
            activities: [:pharmacy],
            ppb_facility_name: "Demo Care Pharmacy",
            license_number: "PPB/PH/DEMO/001"
          },
          %{
            name: "Amina Kamau",
            email: "admin@gmail.com",
            password: password,
            accepted_legal_terms: true
          }
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
            %{
              activities: [:pharmacy],
              lat: -1.2833,
              long: 36.8167,
              ppb_facility_name: "Demo Care Pharmacy",
              license_number: "PPB/PH/DEMO/001"
            },
            fn attrs -> Sites.create_site(organization.id, attrs) end
          )

      %{
        organization: organization,
        site: site,
        user: Accounts.get_user_by_email("admin@gmail.com")
      }
  end

organization =
  org_result.organization
  |> Ecto.Changeset.change(
    operating_models:
      Enum.uniq(
        (org_result.organization.operating_models || []) ++
          [:pharmacy, :laboratory, :distributor, :manufacturer]
      )
  )
  |> Repo.update!()

organization_id = organization.id
primary_admin = org_result.user

seed_api_key = fn present_key, setter ->
  case present_key do
    value when is_binary(value) and value != "" -> setter.(value)
    _blank -> :ok
  end
end

seed_api_key.(System.get_env("GS1_MEMBER_API_TOKEN"), fn key ->
  {:ok, _organization} = Organizations.set_gs1_api_key(organization, key)
end)

seed_api_key.(System.get_env("PPB_TNT_API_KEY"), fn key ->
  {:ok, _organization} = Organizations.set_epcis_api_key(organization, "facility", key)
end)

seed_api_key.(System.get_env("PPB_TNT_DISTRIBUTOR_API_KEY"), fn key ->
  {:ok, _organization} = Organizations.set_epcis_api_key(organization, "distributor", key)
end)

seed_api_key.(System.get_env("PPB_TNT_MANUFACTURER_API_KEY"), fn key ->
  {:ok, _organization} = Organizations.set_epcis_api_key(organization, "manufacturer", key)
end)

pharmacy_site =
  org_result.site
  |> Sites.update_site(%{
    name: "Demo Care CBD Pharmacy",
    activities: [:pharmacy],
    gln: gln.("616000100000"),
    address: "Kimathi Street, Nairobi CBD",
    lat: -1.2833,
    long: 36.8167,
    ppb_facility_name: "Demo Care CBD Pharmacy",
    license_number: "PPB/PH/DEMO/001"
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
      activities: [:laboratory],
      gln: gln.("616000100001"),
      address: "Kimathi Street, 2nd Floor, Nairobi",
      lat: -1.2831,
      long: 36.8169,
      kmlttb_facility_name: "Demo Care Diagnostic Lab",
      kmlttb_license_number: "KMLTTB/LAB/DEMO/001"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

{:ok, lab_site} =
  Sites.update_site(lab_site, %{
    activities: [:laboratory],
    gln: gln.("616000100001"),
    address: "Kimathi Street, 2nd Floor, Nairobi",
    lat: -1.2831,
    long: 36.8169,
    is_active: true,
    kmlttb_facility_name: "Demo Care Diagnostic Lab",
    kmlttb_license_number: "KMLTTB/LAB/DEMO/001"
  })

combined_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Westlands Medical Centre"},
    %{
      activities: [:pharmacy, :laboratory],
      gln: gln.("616000100002"),
      address: "Woodvale Grove, Westlands, Nairobi",
      lat: -1.2676,
      long: 36.8108,
      ppb_facility_name: "Demo Care Westlands Medical Centre",
      license_number: "PPB/PH/DEMO/002",
      kmlttb_facility_name: "Demo Care Westlands Medical Centre Lab",
      kmlttb_license_number: "KMLTTB/LAB/DEMO/002"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

{:ok, combined_site} =
  Sites.update_site(combined_site, %{
    activities: [:pharmacy, :laboratory],
    gln: gln.("616000100002"),
    address: "Woodvale Grove, Westlands, Nairobi",
    lat: -1.2676,
    long: 36.8108,
    is_active: true,
    ppb_facility_name: "Demo Care Westlands Medical Centre",
    license_number: "PPB/PH/DEMO/002",
    kmlttb_facility_name: "Demo Care Westlands Medical Centre Lab",
    kmlttb_license_number: "KMLTTB/LAB/DEMO/002"
  })

warehouse_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Central Warehouse"},
    %{
      activities: [:distribution],
      gln: gln.("616000100003"),
      address: "Mombasa Road Logistics Park, Nairobi",
      lat: -1.3197,
      long: 36.8276,
      ppb_facility_name: "Demo Care Central Warehouse",
      license_number: "PPB/WH/DEMO/001"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

{:ok, warehouse_site} =
  Sites.update_site(warehouse_site, %{
    activities: [:distribution],
    gln: gln.("616000100003"),
    address: "Mombasa Road Logistics Park, Nairobi",
    lat: -1.3197,
    long: 36.8276,
    is_active: true,
    ppb_facility_name: "Demo Care Central Warehouse",
    license_number: "PPB/WH/DEMO/001"
  })

mombasa_warehouse_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Mombasa Depot"},
    %{
      activities: [:distribution],
      gln: gln.("616000100004"),
      address: "Moi Avenue Logistics Park, Mombasa",
      lat: -4.0435,
      long: 39.6682,
      ppb_facility_name: "Demo Care Mombasa Depot",
      license_number: "PPB/WH/DEMO/002"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

{:ok, mombasa_warehouse_site} =
  Sites.update_site(mombasa_warehouse_site, %{
    activities: [:distribution],
    gln: gln.("616000100004"),
    address: "Moi Avenue Logistics Park, Mombasa",
    lat: -4.0435,
    long: 39.6682,
    is_active: true,
    ppb_facility_name: "Demo Care Mombasa Depot",
    license_number: "PPB/WH/DEMO/002"
  })

manufacturing_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Manufacturing Plant"},
    %{
      activities: [:manufacturing],
      gln: gln.("616000100005"),
      address: "Athi River EPZ, Nairobi",
      lat: -1.4567,
      long: 36.9777,
      ppb_facility_name: "Demo Care Manufacturing Plant",
      license_number: "PPB/MF/DEMO/001"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

{:ok, manufacturing_site} =
  Sites.update_site(manufacturing_site, %{
    activities: [:manufacturing],
    gln: gln.("616000100005"),
    address: "Athi River EPZ, Nairobi",
    lat: -1.4567,
    long: 36.9777,
    is_active: true,
    ppb_facility_name: "Demo Care Manufacturing Plant",
    license_number: "PPB/MF/DEMO/001"
  })

manufacturing_distribution_site =
  insert_or_get.(
    Site,
    %{organization_id: organization_id, name: "Demo Care Manufacturing & Distribution Hub"},
    %{
      activities: [:manufacturing, :distribution],
      gln: gln.("616000100006"),
      address: "Nakuru Industrial Park",
      lat: -0.2827,
      long: 36.0667,
      ppb_facility_name: "Demo Care Manufacturing & Distribution Hub",
      license_number: "PPB/MF/DEMO/002"
    },
    fn attrs -> Sites.create_site(organization_id, attrs) end
  )

{:ok, manufacturing_distribution_site} =
  Sites.update_site(manufacturing_distribution_site, %{
    activities: [:manufacturing, :distribution],
    gln: gln.("616000100006"),
    address: "Nakuru Industrial Park",
    lat: -0.2827,
    long: 36.0667,
    is_active: true,
    ppb_facility_name: "Demo Care Manufacturing & Distribution Hub",
    license_number: "PPB/MF/DEMO/002"
  })

organization =
  organization
  |> Ecto.Changeset.change(
    gln: pharmacy_site.gln,
    gln_verified_at: verified_at,
    gs1_prefix_verification_status: :verified,
    is_active: true,
    is_subscription_active: true
  )
  |> Repo.update!()

for site <- [
      pharmacy_site,
      lab_site,
      combined_site,
      warehouse_site,
      mombasa_warehouse_site,
      manufacturing_site,
      manufacturing_distribution_site
    ] do
  site
  |> Ecto.Changeset.change(
    gln_verified_at: verified_at,
    gln_verification_source: "Demo seed",
    is_active: true
  )
  |> Repo.update!()
end

ensure_account = fn email, name, roles, sites ->
  site_ids = Enum.map(sites, & &1.id)

  user =
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, invited, _token} =
          Accounts.invite_user(organization_id, primary_admin.id, %{
            email: email,
            name: name,
            roles: roles,
            site_ids: site_ids
          })

        {:ok, accepted} =
          Accounts.accept_invite(invited, %{
            password: password,
            accepted_legal_terms: true
          })

        accepted

      %User{} = existing ->
        {:ok, updated} =
          Accounts.update_user(organization_id, existing.id, %{roles: roles, site_ids: site_ids})

        updated
        |> Ecto.Changeset.cast(%{name: name, is_active: true}, [:name, :is_active])
        |> Repo.update!()
    end

  user =
    user
    |> Ecto.Changeset.change(hashed_password: Bcrypt.hash_pwd_salt(password))
    |> Repo.update!()

  if is_nil(user.hashed_pin) do
    {:ok, user} = Accounts.set_user_pin(user, %{pin: pin})
    user
  else
    user
  end
end

account_specs = [
  {"admin@gmail.com", "Amina Kamau", [:admin, :pharmacist, :lab_technician, :distributor],
   [pharmacy_site, lab_site, combined_site, warehouse_site, mombasa_warehouse_site]},
  {"pharmacist@gmail.com", "Grace Njeri", [:pharmacist], [pharmacy_site]},
  {"lab@gmail.com", "Laban Omondi", [:lab_technician], [lab_site]},
  {"pharmalab@gmail.com", "Zawadi Muthoni", [:pharmacist, :lab_technician], [combined_site]},
  {"distributor@gmail.com", "David Mwangi", [:distributor],
   [warehouse_site, mombasa_warehouse_site]},
  {"manufacturer@gmail.com", "Esther Wanjiru", [:manufacturer], [manufacturing_site]},
  {"manufacturer-distributor@gmail.com", "Samuel Kiptoo", [:manufacturer, :distributor],
   [manufacturing_distribution_site]}
]

accounts =
  Map.new(account_specs, fn {email, name, roles, sites} ->
    {email, ensure_account.(email, name, roles, sites)}
  end)

primary_admin = Map.fetch!(accounts, "admin@gmail.com")
primary_pharmacist = Map.fetch!(accounts, "pharmacist@gmail.com")
primary_lab_technician = Map.fetch!(accounts, "lab@gmail.com")
primary_pharma_lab = Map.fetch!(accounts, "pharmalab@gmail.com")
primary_distributor = Map.fetch!(accounts, "distributor@gmail.com")

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
  Enum.map(supplier_specs, fn {name, contact, phone, email, gln_payload, location} ->
    supplier =
      insert_or_get.(
        Supplier,
        %{organization_id: organization_id, name: name},
        %{
          contact: contact,
          phone: phone,
          email: email,
          location: location,
          is_active: true
        },
        fn attrs -> Suppliers.create_supplier(organization_id, attrs) end
      )

    supplier
    |> Ecto.Changeset.change(
      gln: gln.(String.slice(gln_payload, 0, 12)),
      gln_verified_at: verified_at,
      gln_verification_source: "Demo seed",
      is_active: true
    )
    |> Repo.update!()
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
          price: price,
          inventory_type: if(type == :lab_consumable, do: :lab_consumable, else: :medicine)
        },
        fn attrs -> Products.create_product(organization_id, attrs) end
      )

    {type, product}
  end)

drug_products = for {:drug, product} <- products, do: product
lab_products = for {:lab_consumable, product} <- products, do: product

create_batch = fn product, site, batch_no, quantity, remaining, expiry_days, supplier, approver ->
  batch =
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

  # Rerunning seeds restores generous demo stock without reducing stock that is
  # already above the baseline after manual receiving/requisition testing.
  batch
  |> Ecto.Changeset.change(
    quantity: max(batch.quantity, quantity),
    remaining_quantity: max(batch.remaining_quantity, remaining),
    expiry_date: Date.add(today, expiry_days)
  )
  |> Repo.update!()
end

pharmacy_batches =
  for {site, site_code, approver} <- [
        {pharmacy_site, "CBD", primary_pharmacist},
        {combined_site, "WST", primary_pharma_lab}
      ],
      {product, index} <- Enum.with_index(drug_products) do
    supplier = Enum.at(suppliers, rem(index, length(suppliers)))
    expiry_days = Enum.at([18, 75, 180, 365], rem(index, 4))
    quantity = 1_000 + index * 25
    remaining = quantity

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
        {combined_site, "WLB", primary_pharma_lab}
      ],
      {product, index} <- Enum.with_index(lab_products) do
    supplier = Enum.at(suppliers, rem(index + 1, length(suppliers)))

    create_batch.(
      product,
      site,
      "#{site_code}-REAG-#{index + 1}",
      500 + index * 25,
      500 + index * 25,
      Enum.at([25, 120, 240, 400], rem(index, 4)),
      supplier,
      approver
    )
  end

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

ensure_org_batch = fn product, batch_no, quantity, expiry_days, supplier ->
  existing =
    Repo.one(
      from b in Batch,
        where: b.organization_id == ^organization_id,
        where: b.product_id == ^product.id,
        where: b.batch_no == ^batch_no,
        where: b.site_id == ^warehouse_site.id
    )

  batch =
    existing ||
      (
        {:ok, created} =
          Batches.receive_into_org_stock(organization_id, %{
            product_id: product.id,
            site_id: warehouse_site.id,
            batch_no: batch_no,
            gtin: product.gtin,
            manufacturer: supplier.name,
            manufacture_date: Date.add(today, -60),
            expiry_date: Date.add(today, expiry_days),
            quantity: quantity,
            cost_per_unit: Decimal.new("20.00"),
            supplier_id: supplier.id
          })

        created
      )

  batch
  |> Ecto.Changeset.change(
    quantity: max(batch.quantity, quantity),
    remaining_quantity: max(batch.remaining_quantity, quantity),
    expiry_date: Date.add(today, expiry_days)
  )
  |> Repo.update!()
end

warehouse_batches =
  for {product, index} <- Enum.with_index(drug_products ++ lab_products) do
    supplier = Enum.at(suppliers, rem(index, length(suppliers)))

    ensure_org_batch.(
      product,
      "WH-#{index + 1}-A",
      5_000 + index * 100,
      Enum.at([90, 150, 270, 400], rem(index, 4)),
      supplier
    )
  end

# Requisition lifecycle: one pending, one approved-and-fully-fulfilled, one
# approved-and-partially-fulfilled, one rejected — exercises every branch of
# the review/fulfillment queue.
requisition_specs = [
  {pharmacy_site, primary_pharmacist, Enum.at(drug_products, 0), 40, :pending},
  {combined_site, primary_pharma_lab, Enum.at(drug_products, 1), 30, :fulfilled},
  {lab_site, primary_lab_technician, Enum.at(lab_products, 0), 25, :partially_fulfilled},
  {pharmacy_site, primary_pharmacist, Enum.at(drug_products, 2), 20, :rejected}
]

Enum.each(requisition_specs, fn {site, requester, product, quantity, target} ->
  requisition =
    case Repo.get_by(Requisition,
           organization_id: organization_id,
           site_id: site.id,
           product_id: product.id,
           quantity: quantity
         ) do
      nil ->
        {:ok, created} =
          Requisitions.create_requisition(organization_id, requester.id, %{
            site_id: site.id,
            product_id: product.id,
            quantity: quantity,
            notes: "Seeded demo requisition for #{product.generic_name}"
          })

        created

      existing ->
        existing
    end

  if requisition.status == :pending and target in [:fulfilled, :partially_fulfilled] do
    {:ok, requisition} =
      Requisitions.approve_requisition(organization_id, requisition.id, primary_admin.id)

    org_batch =
      Enum.find(
        warehouse_batches,
        &(&1.product_id == product.id and &1.site_id == warehouse_site.id)
      )

    case target do
      :fulfilled ->
        {:ok, _dispatched} =
          Requisitions.fulfill_requisition(organization_id, requisition.id, org_batch, quantity)

      :partially_fulfilled ->
        {:ok, _dispatched} =
          Requisitions.fulfill_requisition(
            organization_id,
            requisition.id,
            org_batch,
            div(quantity, 2)
          )
    end
  end

  if requisition.status == :pending and target == :rejected do
    Requisitions.reject_requisition(
      organization_id,
      requisition.id,
      primary_admin.id,
      "Stock already sufficient at site after last delivery."
    )
  end
end)

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
  Repo.one(
    from v in PatientVisit,
      where: v.organization_id == ^organization_id,
      where: v.patient_id == ^patient.id and v.site_id == ^site.id,
      where: v.visit_type == ^type,
      order_by: [asc: v.id],
      limit: 1
  ) ||
    (
      {:ok, visit} =
        PatientVisits.create_patient_visit(organization_id, %{
          organization_id: organization_id,
          patient_id: patient.id,
          site_id: site.id,
          visit_type: type,
          user_id: user.id
        })

      visit
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
      else: {combined_site, primary_pharma_lab}

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

quick_sale_specs = [
  {pharmacy_site, Enum.at(patients, 12), "Cash"},
  {pharmacy_site, nil, "Mobile Money"},
  {combined_site, Enum.at(patients, 13), "Insurance"},
  {combined_site, nil, "Cash"}
]

Enum.each(quick_sale_specs, fn {site, patient, payment_type} ->
  patient_id = patient && patient.id

  already_sold? =
    patient_id in Repo.all(
      from p in Prescription,
        join: v in PatientVisit,
        on: v.id == p.patient_visit_id,
        where:
          p.organization_id == ^organization_id and v.site_id == ^site.id and
            is_nil(p.user_id) and p.payment_type == ^payment_type,
        select: v.patient_id
    )

  # Quick sales feature removed or not yet implemented
  # if not already_sold? do
  #   product =
  #     Enum.at(drug_products, rem(site.id + String.length(payment_type), length(drug_products)))
  #
  #   {:ok, _prescription} =
  #     Prescriptions.create_quick_sale(organization_id, site.id, primary_admin.id, %{
  #       "patient_id" => patient && patient.id,
  #       "payment_type" => payment_type,
  #       "items" => [%{"product_id" => product.id, "quantity_prescribed" => 2}]
  #     })
  # end
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

lab_test_by_id = Map.new(lab_tests, &{&1.id, &1})

sample_result_values = fn lab_test, index ->
  Map.new(lab_test.field_definitions, fn {field, field_def} ->
    value =
      case field_def["type"] do
        "number" ->
          Integer.to_string(7 + rem(index, 6))

        "select" ->
          options = field_def["options"] || ["Normal"]
          Enum.at(options, rem(index, length(options)))

        _ ->
          "Within normal limits"
      end

    {field, value}
  end)
end

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
      else: {combined_site, primary_pharma_lab}

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
          lab_test = Map.fetch!(lab_test_by_id, result.lab_test_id)
          raw_values = sample_result_values.(lab_test, index)

          {:ok, _result} =
            LabOrders.record_result(organization_id, result.id, technician.id, raw_values)
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
        site_id: reagent_batch.site_id,
        purpose: "Reagent and collection materials for #{lab_order.lab_request}"
      )
  end
end)

ensure_payment = fn order_key, order_id, amount, payment_type, outcome ->
  # Skip if amount is zero or less
  if Decimal.compare(amount, Decimal.new(0)) != :gt do
    nil
  else
    existing =
      Repo.get_by(Payment, [{:organization_id, organization_id}, {order_key, order_id}])

    payment =
      existing ||
        case Payments.create_payment(organization_id, %{
               order_key => order_id,
               amount: amount,
               payment_type: payment_type
             }) do
          {:ok, created} ->
            created

          {:error, %{errors: [amount: {msg, _}]}}
          when msg == "order does not have a payable total" ->
            nil

          {:error, changeset} ->
            raise "Failed to create payment: #{inspect(changeset.errors)}"
        end

    case {payment && payment.status, outcome} do
      {nil, _} ->
        nil

      {:pending, :completed} ->
        {:ok, completed} = Payments.complete_payment(payment)
        completed

      {:pending, :failed} ->
        {:ok, failed} = Payments.fail_payment(payment, "Mobile money timeout")
        failed

      _ ->
        payment
    end
  end
end

prescriptions_for_payment =
  Repo.all(
    from p in Prescription,
      where: p.organization_id == ^organization_id,
      order_by: [asc: p.id]
  )

prescriptions_for_payment
|> Enum.with_index()
|> Enum.each(fn {prescription, index} ->
  payment_type = Enum.at(["Cash", "Mobile Money", "Insurance"], rem(index, 3))

  # Calculate actual amount from dispensed items
  actual_amount = Payments.prescription_amount_due(organization_id, prescription.id)

  cond do
    prescription.status == :cancelled ->
      ensure_payment.(:prescription_id, prescription.id, actual_amount, payment_type, :failed)

    prescription.has_paid ->
      ensure_payment.(:prescription_id, prescription.id, actual_amount, payment_type, :completed)

    rem(index, 3) == 0 ->
      ensure_payment.(:prescription_id, prescription.id, actual_amount, payment_type, :pending)

    true ->
      :ok
  end
end)

lab_orders_for_payment =
  Repo.all(
    from l in LabOrder,
      where: l.organization_id == ^organization_id,
      order_by: [asc: l.id]
  )

lab_orders_for_payment
|> Enum.with_index()
|> Enum.each(fn {lab_order, index} ->
  payment_type = Enum.at(["Cash", "Mobile Money", "Insurance"], rem(index, 3))

  cond do
    lab_order.status == :cancelled ->
      ensure_payment.(:lab_order_id, lab_order.id, lab_order.total_amount, payment_type, :failed)

    lab_order.has_paid ->
      ensure_payment.(
        :lab_order_id,
        lab_order.id,
        lab_order.total_amount,
        payment_type,
        :completed
      )

    rem(index, 3) == 0 ->
      ensure_payment.(:lab_order_id, lab_order.id, lab_order.total_amount, payment_type, :pending)

    true ->
      :ok
  end
end)

# Distributor shipment workflow: GS1 prefix, a second (counterpart)
# organization whose own sites act as real destination GLNs, a mobile app
# user, a prepay serialisation bundle, serialised units received at the
# warehouse, and shipments at each stage so the review flow can be
# exercised without the mobile app. Shipments resolve destinations live
# (local sites first, then the GS1 registry) — there is no stored
# "customer" entity — so the destinations here are real `Site` rows on
# another organization, exactly like a real cross-pharmacy shipment.
{:ok, organization} =
  Organizations.update_organization_gs1_settings(organization, %{
    gs1_company_prefix: organization.gs1_company_prefix || "6160001"
  })

counterpart_org =
  case Repo.get_by(Organization, slug: "riverside-health-network") do
    nil ->
      {:ok, result} =
        Organizations.signup(
          %{
            name: "Riverside Health Network",
            slug: "riverside-health-network",
            operating_models: [:pharmacy, :laboratory],
            gs1_company_prefix: "6160003",
            ppb_facility_name: "Riverside Health Network",
            license_number: "RIVERSIDE-PPB-001",
            kmlttb_facility_name: "Riverside Health Network",
            kmlttb_license_number: "RIVERSIDE-KMLTTB-001"
          },
          %{
            name: "Riverside Admin",
            email: "riverside.admin@gmail.com",
            password: password,
            accepted_legal_terms: true
          }
        )

      result.organization

    existing ->
      existing
  end

destination_sites =
  [
    {"Kisumu County Referral Hospital", "Jomo Kenyatta Highway, Kisumu", [:pharmacy]},
    {"Eldoret Family Pharmacy", "Uganda Road, Eldoret", [:pharmacy, :laboratory]}
  ]
  |> Enum.with_index()
  |> Enum.map(fn {{name, address, activities}, index} ->
    site_gln = gln.("6160003" <> String.pad_leading(Integer.to_string(index), 5, "0"))

    site =
      insert_or_get.(
        Site,
        %{organization_id: counterpart_org.id, name: name},
        %{activities: activities, address: address, gln: site_gln},
        fn attrs -> Sites.create_site(counterpart_org.id, attrs) end
      )

    site
    |> Ecto.Changeset.change(
      gln: site_gln,
      gln_verified_at: verified_at,
      gln_verification_source: "Demo seed",
      activities: activities,
      address: address,
      is_active: true
    )
    |> Repo.update!()
  end)

[destination_a, destination_b] = destination_sites

mobile_pin = "4321"

mobile_user =
  case Repo.get_by(MobileUser, username: "packer.demo") do
    nil ->
      {:ok, created} =
        Distributor.create_mobile_user(organization_id, %{
          "name" => "Peter Packer",
          "username" => "packer.demo",
          "email" => "packer@gmail.com",
          "phone" => "0712000111",
          "site_id" => warehouse_site.id
        })

      created

    existing ->
      existing
  end

mobile_user = mobile_user |> MobileUser.pin_changeset(mobile_pin) |> Repo.update!()

if is_nil(organization.serialisation_type) do
  {:ok, organization} = Billing.choose_prepay(organization)

  {:ok, _payment} =
    Billing.start_prepay_payment(organization, primary_distributor, %{
      "quantity" => "1000",
      "method" => "manual",
      "manual_reference" => "SEED-BUNDLE-001"
    })
end

# Each serialised unit is received as its own single-unit batch, since the
# batches table enforces one batch number per product and site.
receive_serialised_unit = fn product, batch_no, serial ->
  {:ok, batch} =
    Batches.create_batch(organization_id, %{
      "product_id" => product.id,
      "site_id" => warehouse_site.id,
      "gtin" => product.gtin,
      "batch_no" => batch_no,
      "serial" => serial,
      "serials" => [serial],
      "manufacturer" => product.manufacturer,
      "manufacture_date" => Date.add(today, -60),
      "expiry_date" => Date.add(today, 540),
      "quantity" => 1,
      "remaining_quantity" => 1,
      "cost_per_unit" => "50.00"
    })

  {:ok, batch} = Batches.receive_batch(batch, primary_distributor.id)
  batch
end

serialised_units =
  for {product, index} <- Enum.with_index(Enum.take(drug_products, 2)),
      serial_index <- 1..3 do
    suffix = "#{index + 1}#{String.pad_leading(Integer.to_string(serial_index), 4, "0")}"
    serial = "SN" <> suffix

    case Repo.get_by(Batch, organization_id: organization_id, gtin: product.gtin, serial: serial) do
      nil -> receive_serialised_unit.(product, "LOT-" <> suffix, serial)
      batch -> batch
    end
  end

data_matrix = fn batch ->
  "01" <>
    batch.gtin <>
    "11" <>
    Calendar.strftime(batch.manufacture_date, "%y%m%d") <>
    "17" <>
    Calendar.strftime(batch.expiry_date, "%y%m%d") <>
    "10" <> batch.batch_no <> <<29>> <> "21" <> batch.serial
end

if not Repo.exists?(
     from s in Shipment,
       where: s.organization_id == ^organization_id and s.order_number == "PO-2026-0100"
   ) do
  {:ok, submitted} =
    Distributor.create_shipment(organization_id, primary_distributor, %{
      "order_number" => "PO-2026-0100",
      "origin_gln" => warehouse_site.gln,
      "destination_gln" => destination_a.gln
    })

  {:ok, _} = Distributor.select_shipment(mobile_user, submitted.id)

  serialised_units
  |> Enum.chunk_every(3)
  |> Enum.each(fn units ->
    {:ok, shipper} = Distributor.create_shipper(mobile_user, submitted.id, %{})

    Enum.each(units, fn batch ->
      {:ok, _item} =
        Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => data_matrix.(batch)})
    end)
  end)

  {:ok, _} = Distributor.submit_shipment(mobile_user, submitted.id)
end

unless Repo.exists?(
         from s in Shipment,
           where:
             s.organization_id == ^organization_id and
               (s.status == "submitted" or s.order_number == "PO-2026-APPROVAL-TEST")
       ) do
  product = Enum.at(drug_products, 0)

  approval_test_units =
    for serial_index <- 1..2 do
      serial = "SN-APPROVAL-TEST-#{serial_index}"
      batch_no = "LOT-APPROVAL-TEST-#{serial_index}"

      case Repo.get_by(Batch,
             organization_id: organization_id,
             gtin: product.gtin,
             serial: serial
           ) do
        nil -> receive_serialised_unit.(product, batch_no, serial)
        batch -> batch
      end
    end

  {:ok, approval_test} =
    Distributor.create_shipment(organization_id, primary_distributor, %{
      "order_number" => "PO-2026-APPROVAL-TEST",
      "origin_gln" => warehouse_site.gln,
      "destination_gln" => destination_a.gln
    })

  {:ok, _} = Distributor.select_shipment(mobile_user, approval_test.id)
  {:ok, shipper} = Distributor.create_shipper(mobile_user, approval_test.id, %{})

  Enum.each(approval_test_units, fn batch ->
    {:ok, _item} =
      Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => data_matrix.(batch)})
  end)

  {:ok, _} = Distributor.submit_shipment(mobile_user, approval_test.id)
  {:ok, _} = Distributor.approve_shipment(organization_id, primary_distributor, approval_test.id)
end

unless Repo.exists?(
         from s in Shipment,
           where: s.organization_id == ^organization_id and s.order_number == "PO-2026-REJECTED"
       ) do
  product = Enum.at(drug_products, 1) || Enum.at(drug_products, 0)

  rejected_units =
    for serial_index <- 1..2 do
      serial = "SN-REJECTED-#{serial_index}"
      batch_no = "LOT-REJECTED-#{serial_index}"

      case Repo.get_by(Batch,
             organization_id: organization_id,
             gtin: product.gtin,
             serial: serial
           ) do
        nil -> receive_serialised_unit.(product, batch_no, serial)
        batch -> batch
      end
    end

  {:ok, rejected} =
    Distributor.create_shipment(organization_id, primary_distributor, %{
      "order_number" => "PO-2026-REJECTED",
      "origin_gln" => warehouse_site.gln,
      "destination_gln" => destination_b.gln
    })

  {:ok, _} = Distributor.select_shipment(mobile_user, rejected.id)
  {:ok, shipper} = Distributor.create_shipper(mobile_user, rejected.id, %{})

  Enum.each(rejected_units, fn batch ->
    {:ok, _item} =
      Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => data_matrix.(batch)})
  end)

  {:ok, _} = Distributor.submit_shipment(mobile_user, rejected.id)

  {:ok, _} =
    Distributor.reject_shipment(
      organization_id,
      primary_distributor,
      rejected.id,
      "Destination GLN mismatch on manifest"
    )
end

# Warehouse management: a bulk batch put away into storage with a bin (for
# the Stock view), a damaged batch and an expired batch (status lifecycle),
# and one return receipt — so every Part F feature has something to look at
# without manual setup first.
pickable_product = Enum.at(drug_products, 2) || Enum.at(drug_products, 0)
secondary_product = Enum.at(drug_products, 1) || pickable_product

ensure_warehouse_batch = fn batch_no, product, quantity, expiry_offset ->
  case Repo.get_by(Batch,
         organization_id: organization_id,
         site_id: warehouse_site.id,
         batch_no: batch_no
       ) do
    nil ->
      {:ok, batch} =
        Batches.create_batch(organization_id, %{
          "product_id" => product.id,
          "site_id" => warehouse_site.id,
          "gtin" => product.gtin,
          "batch_no" => batch_no,
          "manufacturer" => product.manufacturer,
          "manufacture_date" => Date.add(today, -90),
          "expiry_date" => Date.add(today, expiry_offset),
          "quantity" => quantity,
          "remaining_quantity" => quantity,
          "cost_per_unit" => "20.00"
        })

      {:ok, batch} = Batches.receive_batch(batch, primary_distributor.id)
      batch

    batch ->
      batch
  end
end

bulk_storage_batch =
  ensure_warehouse_batch.("BULK-STORAGE-001", pickable_product, 1000, 365)

if bulk_storage_batch.zone == :receiving do
  {:ok, _} = Batches.putaway(bulk_storage_batch, %{"zone" => "storage", "bin" => "A-01-1"})
end

damaged_batch = ensure_warehouse_batch.("DAMAGED-DEMO-001", pickable_product, 40, 200)

if damaged_batch.status == :active do
  {:ok, _} = Batches.mark_damaged(damaged_batch, "DEMO-INCIDENT-001", primary_distributor)
end

expired_demo_batch = ensure_warehouse_batch.("EXPIRED-DEMO-001", secondary_product, 25, 300)

if expired_demo_batch.status == :active do
  {:ok, _} = Batches.mark_expired(expired_demo_batch, primary_distributor)
end

unless Repo.exists?(
         from r in GoodsReceipts.GoodsReceipt,
           where: r.organization_id == ^organization_id and r.is_return == true
       ) do
  return_item = %{
    attrs: %{
      "site_id" => warehouse_site.id,
      "product_id" => pickable_product.id,
      "gtin" => pickable_product.gtin,
      "batch_no" => "RETURN-DEMO-001",
      "quantity" => 15,
      "remaining_quantity" => 15,
      "expiry_date" => Date.add(today, 180),
      "cost_per_unit" => "20.00",
      "sscc" => "006141411234567890"
    }
  }

  origin = %{
    gln: destination_a.gln,
    company: destination_a.name,
    address: destination_a.address,
    po_box: nil,
    site_id: destination_a.id
  }

  {:ok, _return_receipt} =
    GoodsReceipts.receive_delivery(
      organization_id,
      primary_distributor.id,
      [return_item],
      Ecto.UUID.generate(),
      origin,
      %{is_return: true, status: "returned"}
    )
end

# Receiving realism: the SSCC-prefill step at receiving behaves
# differently depending on what's inside the case, and real deliveries
# rarely arrive exactly as manifested. All three scenarios below are
# intra-Demo-Care (warehouse_site -> mombasa_warehouse_site) so they're
# exercisable without a second organization.
#
# Each lot is backed by exactly one `Batch` row — `quantity`/`serials` for
# however many units share it — exactly how a real multi-unit delivery is
# received (see `quantity_only_batch_item/5` in
# DistributorReceivingLive). Scanning encodes that same row's own
# `batch_no`/dates, so every unit resolves `known_unit_status/2` as `"ok"`
# instead of a spurious `data_mismatch` — there's only one real batch_no
# per lot, not a divergent one invented per physical unit.
demo_sscc_product_a = Enum.at(drug_products, 0)
demo_sscc_product_b = Enum.at(drug_products, 1) || demo_sscc_product_a

build_data_matrix = fn gtin, manufacture_date, expiry_date, batch_no, serial ->
  "01" <>
    gtin <>
    "11" <>
    Calendar.strftime(manufacture_date, "%y%m%d") <>
    "17" <>
    Calendar.strftime(expiry_date, "%y%m%d") <>
    "10" <> batch_no <> <<29>> <> "21" <> serial
end

ensure_lot_batch = fn product, batch_no, serials ->
  case Repo.get_by(Batch,
         organization_id: organization_id,
         site_id: warehouse_site.id,
         batch_no: batch_no
       ) do
    nil ->
      {:ok, batch} =
        Batches.create_batch(organization_id, %{
          "product_id" => product.id,
          "site_id" => warehouse_site.id,
          "gtin" => product.gtin,
          "batch_no" => batch_no,
          "manufacturer" => product.manufacturer,
          "manufacture_date" => Date.add(today, -60),
          "expiry_date" => Date.add(today, 540),
          "quantity" => length(serials),
          "remaining_quantity" => length(serials),
          "serials" => serials,
          "cost_per_unit" => "50.00"
        })

      {:ok, batch} = Batches.receive_batch(batch, primary_distributor.id)
      batch

    batch ->
      batch
  end
end

# lots :: [{product, batch_no, serials}]
ensure_demo_shipper_sscc = fn order_number, lots ->
  shipment =
    case Repo.get_by(Shipment, organization_id: organization_id, order_number: order_number) do
      nil ->
        {:ok, shipment} =
          Distributor.create_shipment(organization_id, primary_distributor, %{
            "order_number" => order_number,
            "origin_gln" => warehouse_site.gln,
            "destination_gln" => mombasa_warehouse_site.gln
          })

        {:ok, _} = Distributor.select_shipment(mobile_user, shipment.id)
        {:ok, shipper} = Distributor.create_shipper(mobile_user, shipment.id, %{})

        Enum.each(lots, fn {product, batch_no, serials} ->
          batch = ensure_lot_batch.(product, batch_no, serials)

          Enum.each(serials, fn serial ->
            data_matrix =
              build_data_matrix.(
                product.gtin,
                batch.manufacture_date,
                batch.expiry_date,
                batch.batch_no,
                serial
              )

            {:ok, _item} =
              Distributor.scan_item(mobile_user, shipper.id, %{"raw_data_matrix" => data_matrix})
          end)
        end)

        {:ok, _} = Distributor.submit_shipment(mobile_user, shipment.id)

        {:ok, approved} =
          Distributor.approve_shipment(organization_id, primary_distributor, shipment.id)

        approved

      existing ->
        existing
    end

  shipment |> Repo.preload([shippers: :items], force: true) |> Map.fetch!(:shippers) |> hd()
end

# 1. A mixed-content case: two different lots scanned into the same
#    shipper, so `shipper_contents/1` can't collapse it to one
#    gtin/batch/expiry and reports `unit_count` only — the receiving clerk
#    sees "mixed contents, confirm each line" rather than one prefilled lot.
mixed_shipper =
  ensure_demo_shipper_sscc.("PO-2026-SSCC-MIXED", [
    {demo_sscc_product_a, "LOT-MIX-A", ["SN-MIX-A1", "SN-MIX-A2"]},
    {demo_sscc_product_b, "LOT-MIX-B", ["SN-MIX-B1"]}
  ])

# 2. A uniform-content case: every unit is the same product/lot, so
#    `shipper_contents/1` collapses cleanly and the SSCC prefill can offer
#    one line with a quantity, not six separate ones.
uniform_shipper =
  ensure_demo_shipper_sscc.(
    "PO-2026-SSCC-UNIFORM",
    [{demo_sscc_product_a, "LOT-UNIFORM-A", for(n <- 1..6, do: "SN-UNI-#{n}")}]
  )

# 3. The expected manifest for scenario 4 below: ten units of one lot, so
#    there's something substantial to under-deliver against.
discrepancy_source_shipper =
  ensure_demo_shipper_sscc.(
    "PO-2026-SSCC-DISCREPANCY",
    [{demo_sscc_product_a, "LOT-DISC-SRC", for(n <- 1..10, do: "SN-DISC-#{n}")}]
  )

# 4. An already-posted receipt for that manifest, modelling what actually
#    happens on a real delivery: most units check out, one arrives
#    damaged (posted as its own `:quarantined` batch, same lot, same
#    site), and two never show up at all (never a `Batch` — only a
#    `ReceivingDiscrepancy`, since the org was never confirmed to be in
#    possession of them). Posted at mombasa_warehouse_site so it reads as
#    "received at the depot, shipped from the central warehouse".
unless Repo.exists?(
         from d in GoodsReceipts.ReceivingDiscrepancy,
           where:
             d.organization_id == ^organization_id and d.sscc == ^discrepancy_source_shipper.sscc
       ) do
  good_serials = for n <- 1..7, do: "SN-DISC-#{n}"
  damaged_serials = ["SN-DISC-8"]
  missing_serials = ["SN-DISC-9", "SN-DISC-10"]

  condition_item = fn status, serials ->
    %{
      attrs: %{
        "product_id" => demo_sscc_product_a.id,
        "site_id" => mombasa_warehouse_site.id,
        "gtin" => demo_sscc_product_a.gtin,
        "batch_no" => "LOT-DISC-SRC",
        "manufacture_date" => Date.add(today, -60),
        "expiry_date" => Date.add(today, 540),
        "quantity" => length(serials),
        "serials" => serials,
        "sscc" => discrepancy_source_shipper.sscc,
        "status" => status,
        "cost_per_unit" => "50.00"
      }
    }
  end

  origin = %{
    gln: warehouse_site.gln,
    company: warehouse_site.name,
    address: warehouse_site.address,
    po_box: nil,
    site_id: warehouse_site.id
  }

  {:ok, discrepancy_receipt} =
    GoodsReceipts.receive_delivery(
      organization_id,
      primary_distributor.id,
      [condition_item.("active", good_serials), condition_item.("quarantined", damaged_serials)],
      Ecto.UUID.generate(),
      origin
    )

  Enum.each(missing_serials, fn serial ->
    GoodsReceipts.create_discrepancy!(organization_id, discrepancy_receipt.id, %{
      "sscc" => discrepancy_source_shipper.sscc,
      "gtin" => demo_sscc_product_a.gtin,
      "batch_no" => "LOT-DISC-SRC",
      "serial" => serial,
      "quantity" => 1,
      "product_id" => demo_sscc_product_a.id,
      "site_id" => mombasa_warehouse_site.id,
      "expiry_date" => Date.add(today, 540)
    })
  end)
end

# Disposals: a pending expiry write-off (submitted by a requester, awaiting
# admin review) and an approved one of each kind, so every tab in the
# Disposals queue has something real to show — distinct from
# `damaged_batch`/`expired_demo_batch` above, which flip status directly
# via `Batches.mark_damaged`/`mark_expired` and never go through this
# workflow at all.
disposal_demo_product = Enum.at(drug_products, 2) || Enum.at(drug_products, 0)

ensure_disposal_batch = fn batch_no, product, quantity, opts ->
  case Repo.get_by(Batch,
         organization_id: organization_id,
         site_id: warehouse_site.id,
         batch_no: batch_no
       ) do
    nil ->
      {:ok, batch} =
        Batches.create_batch(
          organization_id,
          Map.merge(
            %{
              "product_id" => product.id,
              "site_id" => warehouse_site.id,
              "gtin" => product.gtin,
              "batch_no" => batch_no,
              "manufacturer" => product.manufacturer,
              "manufacture_date" => Date.add(today, -90),
              "expiry_date" => Date.add(today, 200),
              "quantity" => quantity,
              "remaining_quantity" => quantity,
              "cost_per_unit" => "20.00"
            },
            opts
          )
        )

      {:ok, batch} = Batches.receive_batch(batch, primary_distributor.id)
      batch

    batch ->
      batch
  end
end

unless Repo.exists?(
         from d in InventoryDisposals.InventoryDisposal,
           where: d.organization_id == ^organization_id and d.notes == "SEED-DISPOSAL-PENDING"
       ) do
  pending_disposal_batch =
    ensure_disposal_batch.("DISPOSAL-PENDING-001", disposal_demo_product, 50, %{
      "expiry_date" => Date.add(today, -1)
    })

  {:ok, pending_disposal} =
    InventoryDisposals.create_disposal(organization_id, %{
      "site_id" => warehouse_site.id,
      "kind" => "expiry",
      "inventory_type" => "medicine",
      "requested_by_id" => primary_distributor.id,
      "notes" => "SEED-DISPOSAL-PENDING"
    })

  {:ok, _item} = InventoryDisposals.add_item(pending_disposal, pending_disposal_batch, 50)

  {:ok, _pending_disposal} =
    InventoryDisposals.submit_disposal(
      organization_id,
      pending_disposal.id,
      primary_distributor.id
    )
end

unless Repo.exists?(
         from d in InventoryDisposals.InventoryDisposal,
           where:
             d.organization_id == ^organization_id and d.notes == "SEED-DISPOSAL-APPROVED-EXPIRY"
       ) do
  approved_expiry_batch =
    ensure_disposal_batch.("DISPOSAL-APPROVED-EXPIRY-001", disposal_demo_product, 12, %{
      "expiry_date" => Date.add(today, -1)
    })

  {:ok, approved_expiry_disposal} =
    InventoryDisposals.create_disposal(organization_id, %{
      "site_id" => warehouse_site.id,
      "kind" => "expiry",
      "inventory_type" => "medicine",
      "admin_id" => primary_distributor.id,
      "notes" => "SEED-DISPOSAL-APPROVED-EXPIRY"
    })

  {:ok, _item} = InventoryDisposals.add_item(approved_expiry_disposal, approved_expiry_batch, 12)

  {:ok, _approved} =
    InventoryDisposals.approve_disposal(
      organization_id,
      approved_expiry_disposal.id,
      primary_distributor.id
    )
end

unless Repo.exists?(
         from d in InventoryDisposals.InventoryDisposal,
           where:
             d.organization_id == ^organization_id and d.notes == "SEED-DISPOSAL-APPROVED-RETURN"
       ) do
  disposal_supplier = hd(suppliers)

  approved_return_batch =
    ensure_disposal_batch.("DISPOSAL-APPROVED-RETURN-001", disposal_demo_product, 8, %{
      "supplier_id" => disposal_supplier.id
    })

  {:ok, approved_return_disposal} =
    InventoryDisposals.create_disposal(organization_id, %{
      "site_id" => warehouse_site.id,
      "kind" => "returned",
      "inventory_type" => "medicine",
      "admin_id" => primary_distributor.id,
      "notes" => "SEED-DISPOSAL-APPROVED-RETURN"
    })

  {:ok, _item} = InventoryDisposals.add_item(approved_return_disposal, approved_return_batch, 8)

  {:ok, _approved} =
    InventoryDisposals.approve_disposal(
      organization_id,
      approved_return_disposal.id,
      primary_distributor.id
    )
end

# Stock takes: a pending count (submitted, awaiting admin review, with a
# genuine variance on one line) and an approved one, at the same warehouse.
unless Repo.exists?(
         from st in StockTakes.StockTake,
           where: st.organization_id == ^organization_id and st.notes == "SEED-STOCKTAKE-PENDING"
       ) do
  {:ok, pending_stock_take} =
    StockTakes.create_stock_take(organization_id, %{
      "site_id" => warehouse_site.id,
      "inventory_type" => "medicine",
      "requested_by_id" => primary_distributor.id,
      "notes" => "SEED-STOCKTAKE-PENDING"
    })

  pending_stock_take = Repo.preload(pending_stock_take, :items, force: true)

  case pending_stock_take.items do
    [first_item | _] ->
      {:ok, _} =
        StockTakes.record_count(
          first_item,
          max(first_item.expected_quantity - 3, 0),
          primary_distributor.id
        )

    [] ->
      :ok
  end

  {:ok, _pending_stock_take} =
    StockTakes.submit_stock_take(organization_id, pending_stock_take.id, primary_distributor.id)
end

unless Repo.exists?(
         from st in StockTakes.StockTake,
           where: st.organization_id == ^organization_id and st.notes == "SEED-STOCKTAKE-APPROVED"
       ) do
  {:ok, approved_stock_take} =
    StockTakes.create_stock_take(organization_id, %{
      "site_id" => warehouse_site.id,
      "inventory_type" => "medicine",
      "admin_id" => primary_distributor.id,
      "notes" => "SEED-STOCKTAKE-APPROVED"
    })

  approved_stock_take = Repo.preload(approved_stock_take, :items, force: true)

  Enum.each(
    approved_stock_take.items,
    &StockTakes.record_count(&1, &1.expected_quantity, primary_distributor.id)
  )

  {:ok, _approved_stock_take} =
    StockTakes.approve_stock_take(organization_id, approved_stock_take.id, primary_distributor.id)
end

# Customer return into quarantine: stock physically came back, but nobody
# has decided yet whether it's resellable, damaged, or needs disposal — so
# it sits `inspected` (condition assigned) without being `completed`. A
# second, already-completed quarantine return demonstrates the far side:
# a real `Batch` in zone `:quarantine`/status `:quarantined` that a later,
# separate disposal decision (see above) would act on.
quarantine_return_shipment =
  Repo.get_by!(Shipment, organization_id: organization_id, order_number: "PO-2026-APPROVAL-TEST")

{:ok, quarantine_return_customer} =
  CustomerReturns.customer_for_shipment(organization_id, quarantine_return_shipment)

unless Repo.exists?(
         from cr in CustomerReturns.CustomerReturn,
           where:
             cr.organization_id == ^organization_id and
               cr.document_reference == "SEED-RETURN-AWAITING-DECISION"
       ) do
  {:ok, awaiting_return} =
    CustomerReturns.create_return(organization_id, %{
      "customer_id" => quarantine_return_customer.id,
      "site_id" => warehouse_site.id,
      "shipment_id" => quarantine_return_shipment.id,
      "reason" => "damaged",
      "document_reference" => "SEED-RETURN-AWAITING-DECISION"
    })

  {:ok, awaiting_item} =
    CustomerReturns.add_item(awaiting_return, %{
      "product_id" => Enum.at(drug_products, 0).id,
      "batch_no" => "CRET-AWAITING-001",
      "expiry_date" => Date.add(today, 365),
      "quantity" => 4
    })

  {:ok, awaiting_return} = CustomerReturns.mark_received(awaiting_return, primary_distributor.id)
  {:ok, _awaiting_item} = CustomerReturns.set_item_condition(awaiting_item, :quarantine)
  {:ok, _awaiting_return} = CustomerReturns.mark_inspected(awaiting_return)
end

unless Repo.exists?(
         from cr in CustomerReturns.CustomerReturn,
           where:
             cr.organization_id == ^organization_id and
               cr.document_reference == "SEED-RETURN-QUARANTINED"
       ) do
  {:ok, quarantined_return} =
    CustomerReturns.create_return(organization_id, %{
      "customer_id" => quarantine_return_customer.id,
      "site_id" => warehouse_site.id,
      "shipment_id" => quarantine_return_shipment.id,
      "reason" => "wrong_item",
      "document_reference" => "SEED-RETURN-QUARANTINED"
    })

  {:ok, quarantined_item} =
    CustomerReturns.add_item(quarantined_return, %{
      "product_id" => Enum.at(drug_products, 0).id,
      "batch_no" => "CRET-QUARANTINED-001",
      "expiry_date" => Date.add(today, 365),
      "quantity" => 6
    })

  {:ok, quarantined_return} =
    CustomerReturns.mark_received(quarantined_return, primary_distributor.id)

  {:ok, _quarantined_item} = CustomerReturns.set_item_condition(quarantined_item, :quarantine)
  {:ok, quarantined_return} = CustomerReturns.mark_inspected(quarantined_return)

  {:ok, _quarantined_return} =
    CustomerReturns.complete_return(
      organization_id,
      quarantined_return.id,
      primary_distributor.id
    )
end

expected_account_roles =
  Map.new(account_specs, fn {email, _name, roles, _sites} -> {email, roles} end)

actual_account_roles = Map.new(accounts, fn {email, user} -> {email, user.roles} end)

if actual_account_roles != expected_account_roles do
  raise """
  Demo account roles are not configured as expected.
  Expected: #{inspect(expected_account_roles)}
  Found: #{inspect(actual_account_roles)}
  """
end

IO.puts("""

Seed complete.

Organization: #{organization.name}
Sites: #{pharmacy_site.name}, #{lab_site.name}, #{combined_site.name}, #{warehouse_site.name}, #{mombasa_warehouse_site.name}
Data: #{length(products)} products, #{length(pharmacy_batches) + length(lab_batches)} active site batches,
      #{length(suppliers)} suppliers, #{length(patients)} patients,
      12 prescriptions, #{length(lab_tests)} lab tests, and 12 lab orders.

All organization accounts use password #{password} and PIN #{pin}.

Admin account:
  admin@gmail.com
  Roles: admin, pharmacist, lab technician, distributor
  Assigned to all four Demo Care sites

Pharmacist account:
  pharmacist@gmail.com

Lab technician account:
  lab@gmail.com

Pharmacy + lab account:
  pharmalab@gmail.com

Platform superadmin account:
  #{superadmin.email}
  #{superadmin_password}

Distributor account:
  distributor@gmail.com
  #{length(destination_sites)} destination sites (on #{counterpart_org.name}), a prepay bundle,
  one shipment in each status (draft, submitted, approved, rejected),
  warehouse stock across receiving/storage/quarantine zones with
  damaged/expired examples, and one return receipt.

Distributor mobile app user:
  username packer.demo, PIN #{mobile_pin}
  Bound to #{warehouse_site.name}

Manufacturer account:
  manufacturer@gmail.com
  Assigned to #{manufacturing_site.name}

Manufacturer + distributor account:
  manufacturer-distributor@gmail.com
  Assigned to #{manufacturing_distribution_site.name}

Receiving test SSCCs (warehouse_site -> mombasa_warehouse_site, Demo Care only):
  Mixed-content case:        #{mixed_shipper.sscc}
  Uniform-content case:      #{uniform_shipper.sscc}
  Already-received manifest: #{discrepancy_source_shipper.sscc}
    (7 accepted, 1 damaged -> quarantined batch, 2 missing -> open discrepancies,
     already posted at #{mombasa_warehouse_site.name})
""")
