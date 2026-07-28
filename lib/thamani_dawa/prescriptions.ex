defmodule ThamaniDawa.Prescriptions do
  @moduledoc """
  Pharmacy dispensing (§4.3, §9): a `prescriptions` header with one or more
  `prescription_items`, dispensed against a site's own `batches` stock via
  FEFO (first-expired-first-out — `ThamaniDawa.Batches.fefo_batches/3`).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Batches
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Prescriptions.{BatchDispense, Prescription, PrescriptionItem}
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Repo

  ## Prescriptions

  @doc """
  Lists an organization's prescriptions. Each returned struct has a virtual
  `:site_id` field populated from the associated `patient_visits` row so that
  `SiteScoping.for_current_site/2` can filter by site without a second query.
  """
  def list_prescriptions(organization_id) do
    items_count_query =
      from i in PrescriptionItem,
        group_by: i.prescription_id,
        select: %{prescription_id: i.prescription_id, count: count(i.id)}

    Repo.all(
      from p in Prescription,
        left_join: v in PatientVisit,
        on: v.id == p.patient_visit_id,
        left_join: pat in ThamaniDawa.Patients.Patient,
        on: pat.id == v.patient_id,
        left_join: ic in subquery(items_count_query),
        on: ic.prescription_id == p.id,
        where: p.organization_id == ^organization_id,
        select: %{
          p
          | site_id: v.site_id,
            patient_name: pat.full_name,
            patient_phone: pat.phone,
            items_count: coalesce(ic.count, 0)
        },
        order_by: [desc: p.inserted_at]
    )
  end

  @doc """
  Lists an organization's prescriptions with pagination. Each returned struct has a virtual
  `:site_id` field populated from the associated `patient_visits` row so that
  `SiteScoping.for_current_site/2` can filter by site without a second query.
  """
  def list_prescriptions_paginated(organization_id, page \\ 1) do
    items_count_query =
      from i in PrescriptionItem,
        group_by: i.prescription_id,
        select: %{prescription_id: i.prescription_id, count: count(i.id)}

    from(p in Prescription,
      left_join: v in PatientVisit,
      on: v.id == p.patient_visit_id,
      left_join: pat in ThamaniDawa.Patients.Patient,
      on: pat.id == v.patient_id,
      left_join: ic in subquery(items_count_query),
      on: ic.prescription_id == p.id,
      where: p.organization_id == ^organization_id,
      select: %{
        p
        | site_id: v.site_id,
          patient_name: pat.full_name,
          patient_phone: pat.phone,
          items_count: coalesce(ic.count, 0)
      },
      order_by: [desc: p.inserted_at]
    )
    |> Repo.paginate(page: page)
  end

  @doc "Gets a single prescription scoped to an organization. Raises if not found."
  def get_prescription!(organization_id, id) do
    Repo.get_by!(Prescription, id: id, organization_id: organization_id)
  end

  @doc "Creates a prescription header under the given organization."
  def create_prescription(organization_id, attrs) when is_integer(organization_id) do
    %Prescription{}
    |> Prescription.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> put_computed_total_amount(organization_id)
    |> Repo.insert()
  end

  defp put_computed_total_amount(changeset, organization_id) do
    items = Ecto.Changeset.get_field(changeset, :items) || []

    Ecto.Changeset.put_change(
      changeset,
      :total_amount,
      total_amount_for_items(items, organization_id)
    )
  end

  defp total_amount_for_items(items, organization_id) do
    product_ids = items |> Enum.map(& &1.product_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    prices =
      Map.new(
        Repo.all(
          from p in Product,
            where: p.organization_id == ^organization_id and p.id in ^product_ids,
            select: {p.id, p.price}
        )
      )

    Enum.reduce(items, Decimal.new(0), fn item, acc ->
      case {Map.get(prices, item.product_id), item.quantity_prescribed} do
        {price, qty} when is_integer(price) and is_integer(qty) ->
          Decimal.add(acc, Decimal.mult(Decimal.new(price), Decimal.new(qty)))

        _ ->
          acc
      end
    end)
  end

  @doc """
  Creates a new patient and a prescription for that patient in a single transaction.
  Rolls back if either fails to prevent orphaned records.
  """
  def create_prescription_with_new_patient(
        organization_id,
        patient_attrs,
        site_id,
        user_id,
        prescription_attrs
      )
      when is_integer(organization_id) do
    Repo.transaction(fn ->
      with {:ok, patient} <- ThamaniDawa.Patients.create_patient(organization_id, patient_attrs),
           {:ok, prescription} <-
             create_prescription_for_patient(
               organization_id,
               patient.id,
               site_id,
               user_id,
               prescription_attrs
             ) do
        prescription
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Creates a prescription header for a patient, automatically creating a
  PatientVisit for the current site and user in the same transaction.
  """
  def create_prescription_for_patient(organization_id, patient_id, site_id, user_id, attrs)
      when is_integer(organization_id) do
    Repo.transaction(fn ->
      do_create_prescription_for_patient(organization_id, patient_id, site_id, user_id, attrs)
    end)
  end

  defp do_create_prescription_for_patient(organization_id, patient_id, site_id, user_id, attrs) do
    visit_attrs = %{
      patient_id: patient_id,
      site_id: site_id,
      user_id: user_id,
      visit_type: :pharmacy
    }

    with {:ok, visit} <-
           ThamaniDawa.PatientVisits.create_patient_visit(organization_id, visit_attrs),
         attrs =
           if(Enum.any?(Map.keys(attrs), &is_binary/1),
             do: Map.put(attrs, "patient_visit_id", visit.id),
             else: Map.put(attrs, :patient_visit_id, visit.id)
           ),
         attrs = inject_organization_id_into_items(attrs, organization_id),
         {:ok, prescription} <- create_prescription(organization_id, attrs) do
      prescription
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp inject_organization_id_into_items(%{"items" => items} = attrs, org_id)
       when is_map(items) do
    items = Map.new(items, fn {k, v} -> {k, Map.put(v, "organization_id", org_id)} end)
    %{attrs | "items" => items}
  end

  defp inject_organization_id_into_items(%{"items" => items} = attrs, org_id)
       when is_list(items) do
    items = Enum.map(items, &Map.put(&1, "organization_id", org_id))
    %{attrs | "items" => items}
  end

  defp inject_organization_id_into_items(%{items: items} = attrs, org_id) when is_list(items) do
    items = Enum.map(items, &Map.put(&1, :organization_id, org_id))
    %{attrs | items: items}
  end

  defp inject_organization_id_into_items(attrs, _org_id), do: attrs

  @doc """
  Creates a prescription header together with its `prescription_items`, all
  in one transaction (§9 "Walk-in prescription → dispense", step 1). Rolls
  back the header if any item fails to validate. Returns
  `{:ok, %{prescription: prescription, prescription_items: items}}`.
  """
  def create_prescription_with_items(organization_id, attrs, items_attrs)
      when is_integer(organization_id) and is_list(items_attrs) do
    Repo.transaction(fn ->
      with {:ok, prescription} <- create_prescription(organization_id, attrs),
           {:ok, items} <-
             create_prescription_items(organization_id, prescription.id, items_attrs),
           {:ok, prescription} <-
             prescription
             |> Ecto.Changeset.change(
               total_amount: total_amount_for_items(items, organization_id)
             )
             |> Repo.update() do
        %{prescription: prescription, prescription_items: items}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_prescription_items(organization_id, prescription_id, items_attrs) do
    items_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case create_prescription_item(organization_id, prescription_id, attrs) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  ## Prescription items

  @doc "Gets a single prescription item scoped to an organization. Raises if not found."
  def get_prescription_item!(organization_id, id) do
    Repo.get_by!(PrescriptionItem, id: id, organization_id: organization_id)
  end

  @doc "Lists a prescription's items, preloaded with `product` (scoped to the organization)."
  def list_prescription_items(organization_id, prescription_id) do
    product_query = from p in Product, where: p.organization_id == ^organization_id

    Repo.all(
      from i in PrescriptionItem,
        where: i.organization_id == ^organization_id and i.prescription_id == ^prescription_id,
        preload: [product: ^product_query]
    )
  end

  @doc """
  Creates a prescription item under the given prescription. Rejects a
  `product_id` that's missing, belongs to another organization, is
  inactive, or has no stock available at the prescription's site — before
  any header/items transaction commits. This is independent of the
  post-dispense GTIN scan check in `verify_dispensed_item/3`, which stays
  unchanged.
  """
  def create_prescription_item(organization_id, prescription_id, attrs)
      when is_integer(organization_id) and is_integer(prescription_id) do
    %PrescriptionItem{}
    |> PrescriptionItem.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:prescription_id, prescription_id)
    |> validate_belongs_to_org(:product_id, Product, organization_id)
    |> validate_product_active(organization_id)
    |> validate_product_available_at_site(organization_id, prescription_id)
    |> Repo.insert()
  end

  defp validate_belongs_to_org(changeset, field, schema, organization_id) do
    Ecto.Changeset.validate_change(changeset, field, fn _field, id ->
      case Repo.get_by(schema, id: id, organization_id: organization_id) do
        nil -> [{field, "does not belong to this organization"}]
        _record -> []
      end
    end)
  end

  defp validate_product_active(changeset, organization_id) do
    if Keyword.has_key?(changeset.errors, :product_id) do
      changeset
    else
      case Ecto.Changeset.get_field(changeset, :product_id) do
        nil -> changeset
        product_id -> validate_active(changeset, organization_id, product_id)
      end
    end
  end

  defp validate_active(changeset, organization_id, product_id) do
    if Products.get_product!(organization_id, product_id).is_active do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :product_id, "is not active")
    end
  end

  defp validate_product_available_at_site(changeset, organization_id, prescription_id) do
    if Keyword.has_key?(changeset.errors, :product_id) do
      changeset
    else
      case Ecto.Changeset.get_field(changeset, :product_id) do
        nil ->
          changeset

        product_id ->
          validate_available_at_prescription_site(
            changeset,
            organization_id,
            prescription_id,
            product_id
          )
      end
    end
  end

  defp validate_available_at_prescription_site(
         changeset,
         organization_id,
         prescription_id,
         product_id
       ) do
    prescription = get_prescription!(organization_id, prescription_id)

    case prescription.patient_visit_id do
      nil ->
        changeset

      patient_visit_id ->
        site_id = PatientVisits.get_patient_visit!(organization_id, patient_visit_id).site_id

        if Batches.any_batch_for_site?(organization_id, site_id, product_id) do
          changeset
        else
          Ecto.Changeset.add_error(
            changeset,
            :product_id,
            "is not available at this prescription's site"
          )
        end
    end
  end

  ## Dispensing (§9 "Walk-in prescription → dispense", steps 2-3)

  @doc """
  Dispenses `quantity` for a prescription item by decrementing stock from eligible
  batches in FEFO order at the prescription's site. Updates the status of the item
  and prescription. Operates within a transaction to guarantee data integrity.

  Returns `{:error, :out_of_stock}` if stock is insufficient, `{:error, :over_dispensed}`
  if `quantity` exceeds the prescribed amount, `{:error, :invalid_prescription_site}` if the
  prescription has no resolvable site, or `{:error, changeset}` for validation failures.
  """
  def dispense_item(organization_id, prescription_item_id, pharmacist_id, quantity)
      when is_integer(organization_id) and is_integer(quantity) and quantity > 0 do
    Repo.transaction(fn ->
      item = get_prescription_item!(organization_id, prescription_item_id)
      prescription = get_prescription!(organization_id, item.prescription_id)
      site_id = prescription_site_id(prescription)

      with :ok <- validate_not_over_dispensed(item, quantity),
           :ok <- validate_site_id_present(site_id),
           batches = Batches.fefo_batches(organization_id, site_id, item.product_id),
           {:ok, allocations} <- consume_quantity_across_batches(batches, quantity),
           :ok <- record_batch_dispenses(organization_id, item, pharmacist_id, allocations),
           {:ok, updated_item} <- bump_quantity_dispensed(item, quantity),
           {:ok, _prescription} <- recompute_status(prescription) do
        updated_item
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Lists the batches actually dispensed against a prescription item, preloaded
  with `batch` — the persisted, authoritative record of what was given (unlike
  the live FEFO preview, which can go stale between preview and dispense).
  """
  def list_batch_dispenses_for_item(organization_id, prescription_item_id) do
    batch_query =
      from b in ThamaniDawa.Batches.Batch, where: b.organization_id == ^organization_id

    user_query = from u in ThamaniDawa.Accounts.User, where: u.organization_id == ^organization_id

    Repo.all(
      from d in BatchDispense,
        where:
          d.organization_id == ^organization_id and
            d.prescription_item_id == ^prescription_item_id,
        order_by: [asc: d.dispensed_at],
        preload: [batch: ^batch_query, dispensed_by: ^user_query]
    )
  end

  @doc """
  Verifies a dispensed item by matching the scanned GTIN against the prescribed product's GTIN.
  Updates `is_verified` to `true` on success.

  Returns `{:error, :invalid_gtin}` if the scanned code isn't a digits-only string or doesn't
  normalize to a valid GTIN, or `{:error, :gtin_mismatch}` if it's a valid GTIN for a different
  product.
  """
  def verify_dispensed_item(organization_id, prescription_item_id, scanned_gtin) do
    item = get_prescription_item!(organization_id, prescription_item_id)
    product = ThamaniDawa.Products.get_product!(organization_id, item.product_id)

    with {:match, true} <- {:match, String.match?(scanned_gtin, ~r/^\d+$/)},
         {:ok, normalized_gtin} <- ExGtin.normalize(scanned_gtin),
         {:gtin, true} <- {:gtin, product.gtin == normalized_gtin} do
      item
      |> PrescriptionItem.changeset(%{is_verified: true})
      |> Repo.update()
    else
      {:match, false} -> {:error, :invalid_gtin}
      {:error, _reason} -> {:error, :invalid_gtin}
      {:gtin, false} -> {:error, :gtin_mismatch}
    end
  end

  defp consume_quantity_across_batches([], _quantity_needed), do: {:error, :out_of_stock}

  defp consume_quantity_across_batches([batch | rest], quantity_needed) do
    take = min(batch.remaining_quantity, quantity_needed)
    {:ok, _} = Batches.decrement_remaining_quantity(batch, take)

    if take == quantity_needed do
      {:ok, [%{batch: batch, quantity: take}]}
    else
      with {:ok, more} <- consume_quantity_across_batches(rest, quantity_needed - take) do
        {:ok, [%{batch: batch, quantity: take} | more]}
      end
    end
  end

  defp record_batch_dispenses(organization_id, item, pharmacist_id, allocations) do
    Enum.reduce_while(allocations, :ok, fn %{batch: batch, quantity: qty}, :ok ->
      %BatchDispense{}
      |> BatchDispense.changeset(%{
        organization_id: organization_id,
        prescription_item_id: item.id,
        batch_id: batch.id,
        quantity: qty,
        dispensed_by_id: pharmacist_id,
        dispensed_at: DateTime.utc_now()
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # `prescriptions` no longer carries its own `site_id` — it's derived from
  # the `patient_visits` row it's tied to via `patient_visit_id`.
  defp prescription_site_id(%Prescription{patient_visit_id: nil}), do: nil

  defp prescription_site_id(%Prescription{patient_visit_id: patient_visit_id}) do
    Repo.get!(PatientVisit, patient_visit_id).site_id
  end

  defp validate_site_id_present(nil), do: {:error, :invalid_prescription_site}
  defp validate_site_id_present(_site_id), do: :ok

  defp validate_not_over_dispensed(%PrescriptionItem{} = item, quantity) do
    if item.quantity_dispensed + quantity > item.quantity_prescribed do
      {:error, :over_dispensed}
    else
      :ok
    end
  end

  defp bump_quantity_dispensed(%PrescriptionItem{} = item, quantity) do
    item
    |> Ecto.Changeset.change(quantity_dispensed: item.quantity_dispensed + quantity)
    |> Repo.update()
  end

  # A prescription is `completed` once every item is fully dispensed,
  # `partially_dispensed` once at least one dispense has happened, and left
  # alone otherwise (e.g. still `cancelled`).
  defp recompute_status(%Prescription{} = prescription) do
    items = Repo.all(from i in PrescriptionItem, where: i.prescription_id == ^prescription.id)

    status =
      cond do
        Enum.all?(items, &(&1.quantity_dispensed >= &1.quantity_prescribed)) -> :completed
        Enum.any?(items, &(&1.quantity_dispensed > 0)) -> :partially_dispensed
        true -> prescription.status
      end

    prescription
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end
end
