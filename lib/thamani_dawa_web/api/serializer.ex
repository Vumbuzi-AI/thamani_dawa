defmodule ThamaniDawaWeb.Api.Serializer do
  @moduledoc """
  Turns context structs into JSON-safe maps. Fields are listed on purpose
  so a password hash or token never leaves with a user.
  """

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.CustomerReturns.CustomerReturn
  alias ThamaniDawa.CustomerReturns.CustomerReturnItem
  alias ThamaniDawa.Customers.Customer
  alias ThamaniDawa.Distributor.MobileUser
  alias ThamaniDawa.Distributor.Shipment
  alias ThamaniDawa.Distributor.ShipmentItem
  alias ThamaniDawa.Distributor.Shipper
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent
  alias ThamaniDawa.GoodsReceipts.GoodsReceipt
  alias ThamaniDawa.GoodsReceipts.ReceivingDiscrepancy
  alias ThamaniDawa.GS1Encoder
  alias ThamaniDawa.InventoryDisposals.InventoryDisposal
  alias ThamaniDawa.InventoryDisposals.InventoryDisposalItem
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.LabTests.LabTest
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Aggregation
  alias ThamaniDawa.Manufacturing.AggregationItem
  alias ThamaniDawa.Manufacturing.Pallet
  alias ThamaniDawa.Manufacturing.ShipperSscc
  alias ThamaniDawa.Organizations.OrganizationGs1Prefix
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Prescriptions.PrescriptionItem
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Recalls.RecallHolder
  alias ThamaniDawa.Requisitions.Requisition
  alias ThamaniDawa.Requisitions.RequisitionLine
  alias ThamaniDawa.Sales.Sale
  alias ThamaniDawa.Sales.SaleItem
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.StockTakes.StockTake
  alias ThamaniDawa.StockTakes.StockTakeItem
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
      strength: product.strength,
      category: product.category,
      manufacturer: product.manufacturer,
      uom: product.uom,
      pack_uom: product.pack_uom,
      units_per_pack: product.units_per_pack,
      net_content_quantity: product.net_content_quantity,
      net_content_uom: product.net_content_uom,
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
        status: batch.status,
        serial: batch.serial,
        serials: batch.serials,
        sscc: batch.sscc,
        logistic_unit_id: batch.logistic_unit_id,
        zone: batch.zone,
        bin: batch.bin,
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

  def stock_take(%StockTake{} = stock_take) do
    json_safe(%{
      id: stock_take.id,
      site_id: stock_take.site_id,
      inventory_type: stock_take.inventory_type,
      status: stock_take.status,
      notes: stock_take.notes,
      rejection_reason: stock_take.rejection_reason,
      requested_by_id: stock_take.requested_by_id,
      admin_id: stock_take.admin_id,
      approved_by_id: stock_take.approved_by_id,
      approved_at: stock_take.approved_at,
      inserted_at: stock_take.inserted_at,
      items: loaded(stock_take.items, &stock_take_item/1)
    })
  end

  def stock_take_item(%StockTakeItem{} = item) do
    json_safe(%{
      id: item.id,
      batch_id: item.batch_id,
      expected_quantity: item.expected_quantity,
      counted_quantity: item.counted_quantity,
      variance: item.variance,
      counted_at: item.counted_at,
      counted_by_id: item.counted_by_id,
      notes: item.notes,
      batch: maybe(item.batch, &batch/1)
    })
  end

  def disposal(%InventoryDisposal{} = disposal) do
    json_safe(%{
      id: disposal.id,
      site_id: disposal.site_id,
      kind: disposal.kind,
      inventory_type: disposal.inventory_type,
      status: disposal.status,
      reason: disposal.reason,
      notes: disposal.notes,
      rejection_reason: disposal.rejection_reason,
      requested_by_id: disposal.requested_by_id,
      admin_id: disposal.admin_id,
      approved_by_id: disposal.approved_by_id,
      approved_at: disposal.approved_at,
      inserted_at: disposal.inserted_at,
      items: loaded(disposal.items, &disposal_item/1)
    })
  end

  def disposal_item(%InventoryDisposalItem{} = item) do
    json_safe(%{
      id: item.id,
      batch_id: item.batch_id,
      available_quantity: item.available_quantity,
      quantity: item.quantity,
      notes: item.notes,
      batch: maybe(item.batch, &batch/1)
    })
  end

  def recall_holder(%RecallHolder{} = holder) do
    json_safe(%{
      id: holder.id,
      batch_id: holder.batch_id,
      quantity_at_recall: holder.quantity_at_recall,
      acknowledged_at: holder.acknowledged_at,
      acknowledged_by_id: holder.acknowledged_by_id,
      recall:
        maybe(holder.recall, fn recall ->
          %{
            id: recall.id,
            gtin: recall.gtin,
            batch_no: recall.batch_no,
            reference: recall.reference,
            classification: recall.classification,
            reason: recall.reason,
            status: recall.status,
            inserted_at: recall.inserted_at
          }
        end),
      batch: maybe(holder.batch, &batch/1)
    })
  end

  def goods_receipt(%GoodsReceipt{} = receipt) do
    json_safe(%{
      id: receipt.id,
      number: receipt.number,
      received_at: receipt.received_at,
      received_by_id: receipt.received_by_id,
      origin_gln: receipt.origin_gln,
      origin_company: receipt.origin_company,
      origin_address: receipt.origin_address,
      origin_site_id: receipt.origin_site_id,
      is_return: receipt.is_return,
      reference_receipt_id: receipt.reference_receipt_id,
      items: loaded(receipt.items, &receipt_item/1),
      discrepancies: loaded(receipt.discrepancies, &discrepancy/1)
    })
  end

  defp receipt_item(%Batch{} = batch) do
    batch
    |> batch()
    |> Map.put(:product, maybe(batch.product, &product/1))
  end

  def discrepancy(%ReceivingDiscrepancy{} = discrepancy) do
    json_safe(%{
      id: discrepancy.id,
      goods_receipt_id: discrepancy.goods_receipt_id,
      product_id: discrepancy.product_id,
      site_id: discrepancy.site_id,
      sscc: discrepancy.sscc,
      gtin: discrepancy.gtin,
      batch_no: discrepancy.batch_no,
      serial: discrepancy.serial,
      quantity: discrepancy.quantity,
      expiry_date: discrepancy.expiry_date,
      reason: discrepancy.reason,
      status: discrepancy.status,
      resolution_reference: discrepancy.resolution_reference,
      resolved_at: discrepancy.resolved_at,
      resolved_by_id: discrepancy.resolved_by_id
    })
  end

  def customer(%Customer{} = customer) do
    json_safe(%{
      id: customer.id,
      name: customer.name,
      gln: customer.gln,
      address: customer.address,
      customer_type: customer.customer_type,
      contact_name: customer.contact_name,
      contact_email: customer.contact_email,
      contact_phone: customer.contact_phone
    })
  end

  def customer_return(%CustomerReturn{} = customer_return) do
    json_safe(%{
      id: customer_return.id,
      status: customer_return.status,
      reason: customer_return.reason,
      notes: customer_return.notes,
      document_reference: customer_return.document_reference,
      customer_id: customer_return.customer_id,
      site_id: customer_return.site_id,
      shipment_id: customer_return.shipment_id,
      received_by_id: customer_return.received_by_id,
      inserted_at: customer_return.inserted_at,
      customer: maybe(customer_return.customer, &customer/1),
      items: loaded(customer_return.items, &customer_return_item/1)
    })
  end

  def customer_return_item(%CustomerReturnItem{} = item) do
    json_safe(%{
      id: item.id,
      product_id: item.product_id,
      quantity: item.quantity,
      batch_no: item.batch_no,
      expiry_date: item.expiry_date,
      serial: item.serial,
      matched: item.matched,
      condition: item.condition,
      batch_id: item.batch_id,
      product: maybe(item.product, &product/1)
    })
  end

  def mobile_session(tokens) do
    json_safe(%{
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_type: "Bearer",
      access_expires_at: tokens.access_expires_at,
      refresh_expires_at: tokens.refresh_expires_at,
      mobile_user: mobile_user(tokens.mobile_user)
    })
  end

  def mobile_user(%MobileUser{} = mobile_user) do
    json_safe(%{
      id: mobile_user.id,
      name: mobile_user.name,
      username: mobile_user.username,
      organization_id: mobile_user.organization_id,
      site_id: mobile_user.site_id,
      last_login_at: mobile_user.last_login_at
    })
  end

  def shipment(%Shipment{} = shipment) do
    json_safe(%{
      id: shipment.id,
      reference: shipment.reference,
      order_number: shipment.order_number,
      status: shipment.status,
      is_return: shipment.is_return,
      origin_gln: shipment.origin_gln,
      origin_company: shipment.origin_company,
      destination_gln: shipment.destination_gln,
      destination_company: shipment.destination_company,
      destination_address: shipment.destination_address,
      assigned_mobile_user_id: shipment.assigned_mobile_user_id,
      submitted_by_mobile_user_id: shipment.submitted_by_mobile_user_id,
      submitted_at: shipment.submitted_at,
      approved_at: shipment.approved_at,
      rejected_at: shipment.rejected_at,
      rejection_reason: shipment.rejection_reason,
      updated_at: shipment.updated_at,
      shippers: loaded(shipment.shippers, &shipper/1)
    })
  end

  def shipper(%Shipper{} = shipper) do
    json_safe(%{
      id: shipper.id,
      sequence: shipper.sequence,
      name: shipper.name,
      material_description: shipper.material_description,
      sscc: shipper.sscc,
      unit_count: shipper.unit_count,
      items: loaded(shipper.items, &shipment_item/1)
    })
  end

  def shipment_item(%ShipmentItem{} = item) do
    json_safe(%{
      id: item.id,
      shipper_id: item.shipper_id,
      shipment_id: item.shipment_id,
      gtin: item.gtin,
      batch: item.batch,
      serial: item.serial,
      production_date: item.production_date,
      expiry_date: item.expiry_date,
      product_id: item.product_id,
      product_name: item.product_name,
      validation_status: item.validation_status,
      scanned_at: item.scanned_at
    })
  end

  # Manufacturer portal

  # The GS1 licence key stays out of the API.
  def manufacturer_product(%Manufacturing.Product{} = product) do
    json_safe(%{
      id: product.id,
      gtin: product.gtin,
      name: product.name,
      description: product.description,
      brand_owner: product.brand_owner,
      brand_owner_address: product.brand_owner_address,
      licence_type: product.licence_type,
      status: product.status,
      inserted_at: product.inserted_at
    })
  end

  def manufacturer_batch(%Manufacturing.Batch{} = batch, serial_count \\ nil) do
    json_safe(%{
      id: batch.id,
      product_id: batch.manufacturer_product_id,
      batch_no: batch.batch_no,
      production_date: batch.production_date,
      expiry_date: batch.expiry_date,
      serial_count: serial_count,
      inserted_at: batch.inserted_at
    })
  end

  def manufacturer_serial(%Manufacturing.Serial{} = serial, gs1_text \\ nil) do
    json_safe(%{
      id: serial.id,
      serial: serial.serial,
      product_id: serial.manufacturer_product_id,
      batch_id: serial.manufacturer_batch_id,
      sscc_id: serial.manufacturer_shipper_sscc_id,
      gs1_text: gs1_text
    })
  end

  def pallet(%Pallet{} = pallet) do
    json_safe(%{
      id: pallet.id,
      code: pallet.code,
      from_gln: pallet.from_gln,
      from_company_name: pallet.from_company_name,
      from_address: pallet.from_address,
      to_gln: pallet.to_gln,
      to_company_name: pallet.to_company_name,
      to_address: pallet.to_address
    })
  end

  def sscc(%ShipperSscc{} = sscc) do
    json_safe(%{
      id: sscc.id,
      code: sscc.code,
      gtin: sscc.gtin,
      batch: sscc.batch,
      production_date: sscc.production_date,
      expiry_date: sscc.expiry_date,
      count_of_trade_items: sscc.count_of_trade_items,
      from_gln: sscc.from_gln,
      from_company_name: sscc.from_company_name,
      from_address: sscc.from_address,
      to_gln: sscc.to_gln,
      to_company_name: sscc.to_company_name,
      to_address: sscc.to_address,
      pallet: maybe(sscc.pallet, &pallet/1),
      batches: loaded(sscc.batches, &manufacturer_batch/1),
      inserted_at: sscc.inserted_at
    })
  end

  def aggregation(%Aggregation{} = aggregation) do
    json_safe(%{
      id: aggregation.id,
      reference: aggregation.reference,
      status: aggregation.status,
      sscc_id: aggregation.manufacturer_shipper_sscc_id,
      sscc: maybe(aggregation.shipper_sscc, &sscc/1),
      item_count: aggregation.item_count || loaded_count(aggregation.items),
      items: loaded(aggregation.items, &aggregation_item/1),
      created_by_id: aggregation.created_by_id,
      approved_by_id: aggregation.approved_by_id,
      rejected_by_id: aggregation.rejected_by_id,
      submitted_at: aggregation.submitted_at,
      approved_at: aggregation.approved_at,
      rejected_at: aggregation.rejected_at,
      rejection_reason: aggregation.rejection_reason,
      updated_at: aggregation.updated_at
    })
  end

  def aggregation_item(%AggregationItem{} = item) do
    json_safe(%{
      id: item.id,
      serial: item.serial,
      gtin: item.gtin,
      raw_data_matrix: item.raw_data_matrix,
      validation_status: item.validation_status,
      serial_id: item.manufacturer_serial_id,
      scanned_at: item.scanned_at
    })
  end

  # The payload and PPB's response are only sent when asked for, since a
  # list of events would otherwise be large.
  def outbox_event(%OutboxEvent{} = event, opts \\ []) do
    data = %{
      id: event.id,
      event_id: event.event_id,
      event_type: event.event_type,
      participant_tier: event.participant_tier,
      status: event.status,
      detail: Outbox.event_detail(event),
      occurred_at: event.occurred_at,
      http_status: event.http_status,
      attempts: event.attempts,
      next_attempt_at: event.next_attempt_at,
      source_type: event.source_type,
      source_id: event.source_id
    }

    data =
      if Keyword.get(opts, :payload, false),
        do: Map.merge(data, %{payload: event.payload, response: event.response}),
        else: data

    json_safe(data)
  end

  def gs1_prefix(%OrganizationGs1Prefix{} = prefix) do
    json_safe(%{
      id: prefix.id,
      prefix: prefix.prefix,
      is_primary: prefix.is_primary,
      verification_status: prefix.verification_status,
      verified_at: prefix.verified_at
    })
  end

  defp loaded_count(list) when is_list(list), do: length(list)
  defp loaded_count(_not_loaded), do: nil

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
       when is_boolean(value) or is_nil(value) or is_number(value) or is_binary(value),
       do: value

  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, nested} -> {key, json_safe(nested)} end)
  end

  defp json_safe(value), do: value
end
