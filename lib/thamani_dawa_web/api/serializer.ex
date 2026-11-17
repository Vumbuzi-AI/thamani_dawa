defmodule ThamaniDawaWeb.Api.Serializer do
  @moduledoc """
  Turns context structs into JSON-safe maps. Fields are listed on purpose
  so a password hash or token never leaves with a user.
  """

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GS1Encoder
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.LabTests.LabTest
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Prescriptions.PrescriptionItem
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Requisitions.Requisition
  alias ThamaniDawa.Requisitions.RequisitionLine
  alias ThamaniDawa.Sales.Sale
  alias ThamaniDawa.Sales.SaleItem
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers.Supplier
  alias ThamaniDawaWeb.Api.Access

  def session(tokens, %User{} = user) do
    %{
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_type: "Bearer",
      expires_in: tokens.expires_in,
      user: user(user)
    }
  end

  def user(%User{} = user) do
    scope = Scope.for_user(user)

    %{
      id: user.id,
      name: user.name,
      email: user.email,
      roles: user.roles,
      organization: organization(user.organization),
      current_site: maybe(user.current_site, &site/1),
      portals: Enum.map(Access.portals(scope), &Atom.to_string/1)
    }
    |> json_safe()
  end

  def organization(org) do
    %{
      id: org.id,
      name: org.name,
      operating_models: org.operating_models,
      is_active: org.is_active
    }
  end

  def site(%Site{} = site) do
    json_safe(%{
      id: site.id,
      name: site.name,
      activities: site.activities,
      gln: site.gln,
      address: site.address,
      is_active: site.is_active
    })
  end

  def product(%Product{} = product) do
    json_safe(%{
      id: product.id,
      generic_name: product.generic_name,
      brand_name: product.brand_name,
      category: product.category,
      manufacturer: product.manufacturer,
      uom: product.uom,
      gtin: product.gtin,
      inventory_type: product.inventory_type,
      is_otc: product.is_otc,
      is_dangerous_drug: product.is_dangerous_drug,
      reorder_level: product.reorder_level,
      price: product.price,
      is_active: product.is_active
    })
  end

  def product(%{id: _} = row) do
    json_safe(Map.take(row, [:id, :generic_name, :brand_name, :category, :gtin, :price, :stock]))
  end

  def batch(%Batch{} = batch, opts \\ []) do
    data =
      json_safe(%{
        id: batch.id,
        product_id: batch.product_id,
        site_id: batch.site_id,
        gtin: batch.gtin,
        batch_no: batch.batch_no,
        serial: batch.serial,
        manufacturer: batch.manufacturer,
        manufacture_date: batch.manufacture_date,
        expiry_date: batch.expiry_date,
        quantity: batch.quantity,
        remaining_quantity: batch.remaining_quantity,
        cost_per_unit: batch.cost_per_unit,
        supplier_id: batch.supplier_id,
        received_at: batch.received_at,
        approver_id: batch.approver_id,
        source_batch_id: batch.source_batch_id
      })

    if Keyword.get(opts, :label, false), do: Map.merge(data, label(batch)), else: data
  end

  def supplier(%Supplier{} = supplier) do
    json_safe(%{
      id: supplier.id,
      name: supplier.name,
      contact: supplier.contact,
      phone: supplier.phone,
      email: supplier.email,
      gln: supplier.gln,
      location: supplier.location,
      is_active: supplier.is_active
    })
  end

  def patient(%Patient{} = patient) do
    json_safe(%{
      id: patient.id,
      full_name: patient.full_name,
      date_of_birth: patient.date_of_birth,
      age: Patient.age(patient),
      gender: patient.gender,
      phone: patient.phone,
      national_id: patient.national_id,
      gsrn: patient.gsrn
    })
  end

  def sale(%Sale{} = sale) do
    json_safe(%{
      id: sale.id,
      status: sale.status,
      has_paid: sale.has_paid,
      total_amount: sale.total_amount,
      site_id: sale.site_id,
      user_id: sale.user_id,
      inserted_at: sale.inserted_at,
      items: loaded(sale.items, &sale_item/1)
    })
  end

  def sale_item(%SaleItem{} = item) do
    json_safe(%{
      id: item.id,
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      is_verified: item.is_verified
    })
  end

  def prescription(%Prescription{} = prescription) do
    json_safe(%{
      id: prescription.id,
      status: prescription.status,
      payment_type: prescription.payment_type,
      has_paid: prescription.has_paid,
      total_amount: prescription.total_amount,
      notes: prescription.notes,
      patient_visit_id: prescription.patient_visit_id,
      site_id: Map.get(prescription, :site_id),
      patient_name: Map.get(prescription, :patient_name),
      patient_phone: Map.get(prescription, :patient_phone),
      items_count: Map.get(prescription, :items_count),
      inserted_at: prescription.inserted_at,
      items: loaded(prescription.items, &prescription_item/1)
    })
  end

  def prescription_item(%PrescriptionItem{} = item) do
    json_safe(%{
      id: item.id,
      product_id: item.product_id,
      quantity_prescribed: item.quantity_prescribed,
      quantity_dispensed: item.quantity_dispensed,
      dosage_instructions: Map.get(item, :dosage_instructions),
      is_verified: Map.get(item, :is_verified)
    })
  end

  def payment(%Payment{} = payment) do
    json_safe(%{
      id: payment.id,
      amount: payment.amount,
      payment_type: payment.payment_type,
      status: payment.status,
      provider_reference: payment.provider_reference,
      paid_at: payment.paid_at,
      site_id: payment.site_id,
      prescription_id: payment.prescription_id,
      lab_order_id: payment.lab_order_id,
      inserted_at: payment.inserted_at
    })
  end

  def requisition(%Requisition{} = requisition) do
    json_safe(%{
      id: requisition.id,
      number: requisition.number,
      status: requisition.status,
      quantity: requisition.quantity,
      notes: requisition.notes,
      rejection_reason: requisition.rejection_reason,
      site_id: requisition.site_id,
      product_id: requisition.product_id,
      inserted_at: requisition.inserted_at,
      lines: loaded(requisition.lines, &requisition_line/1)
    })
  end

  def requisition_line(%RequisitionLine{} = line) do
    json_safe(%{
      id: line.id,
      product_id: line.product_id,
      requested_quantity: line.requested_quantity,
      approved_quantity: line.approved_quantity,
      status: line.status,
      rejection_reason: line.rejection_reason
    })
  end

  def lab_order(%LabOrder{} = order) do
    json_safe(%{
      id: order.id,
      status: order.status,
      site_id: order.site_id,
      payment_type: order.payment_type,
      has_paid: order.has_paid,
      total_amount: order.total_amount,
      prescriber_name: order.prescriber_name,
      is_referral: order.is_referral,
      referring_facility: order.referring_facility,
      referring_doctor: order.referring_doctor,
      inserted_at: order.inserted_at,
      results: loaded(order.lab_order_results, &lab_result/1)
    })
  end

  def lab_result(result) do
    json_safe(%{
      id: result.id,
      lab_test_id: result.lab_test_id,
      status: result.status,
      results: result.results
    })
  end

  def lab_test(%LabTest{} = test) do
    json_safe(%{
      id: test.id,
      name: test.name,
      price: test.price,
      is_active: test.is_active,
      category_id: test.category_id,
      field_definitions: test.field_definitions
    })
  end

  def scan(%{state: state, decoded: decoded, product: product, batches: batches} = payload) do
    json_safe(%{
      state: state,
      decoded: decoded,
      product: maybe(product, &product/1),
      site: maybe(Map.get(payload, :site), &site/1),
      total_quantity: Map.get(payload, :total_quantity),
      batches: Enum.map(batches, &batch/1)
    })
  end

  def stats(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, json_safe(value)} end)
    |> Map.new()
  end

  def series(rows) do
    Enum.map(rows, fn
      {%Date{} = date, quantity} ->
        %{date: json_safe(date), quantity: json_safe(quantity)}

      {%DateTime{} = date, quantity} ->
        %{date: json_safe(date), quantity: json_safe(quantity)}

      {%NaiveDateTime{} = date, quantity} ->
        %{date: json_safe(date), quantity: json_safe(quantity)}

      {name, quantity} when is_binary(name) ->
        %{name: name, quantity: json_safe(quantity)}

      {type, amount} ->
        %{payment_type: json_safe(type), amount: json_safe(amount)}
    end)
  end

  defp label(batch) do
    %{datamatrix: GS1Encoder.encode_raw(batch), hri: GS1Encoder.human_readable(batch)}
  rescue
    _ -> %{datamatrix: nil, hri: nil}
  end

  defp loaded(%Ecto.Association.NotLoaded{}, _fun), do: nil
  defp loaded(nil, _fun), do: nil
  defp loaded(list, fun) when is_list(list), do: Enum.map(list, fun)

  defp maybe(nil, _fun), do: nil
  defp maybe(%Ecto.Association.NotLoaded{}, _fun), do: nil
  defp maybe(value, fun), do: fun.(value)

  defp json_safe(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp json_safe(%Date{} = value), do: Date.to_iso8601(value)
  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp json_safe(value)
       when is_boolean(value) or is_nil(value) or is_number(value) or is_binary(value), do: value

  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, nested} -> {key, json_safe(nested)} end)
  end

  defp json_safe(value), do: value
end
