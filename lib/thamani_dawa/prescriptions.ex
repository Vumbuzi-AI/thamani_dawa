defmodule ThamaniDawa.Prescriptions do
  @moduledoc """
  Pharmacy dispensing (§4.3, §9): a `prescriptions` header with one or more
  `prescription_items`, dispensed against a site's own `batches` stock via
  FEFO (first-expired-first-out — `ThamaniDawa.Batches.fefo_batch/3`).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Batches
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Prescriptions.{Prescription, PrescriptionItem}
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

  @doc "Gets a single prescription scoped to an organization. Raises if not found."
  def get_prescription!(organization_id, id) do
    Repo.get_by!(Prescription, id: id, organization_id: organization_id)
  end

  @doc "Creates a prescription header under the given organization."
  def create_prescription(organization_id, attrs) when is_integer(organization_id) do
    %Prescription{}
    |> Prescription.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
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
         # Stringify keys if attrs has string keys, otherwise atom keys
         attrs =
           if(is_map_key(attrs, "patient_visit_id") or is_map_key(attrs, "referring_doctor"),
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
             create_prescription_items(organization_id, prescription.id, items_attrs) do
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

  @doc "Lists a prescription's items."
  def list_prescription_items(organization_id, prescription_id) do
    Repo.all(
      from i in PrescriptionItem,
        where: i.organization_id == ^organization_id and i.prescription_id == ^prescription_id
    )
  end

  @doc "Creates a prescription item under the given prescription."
  def create_prescription_item(organization_id, prescription_id, attrs)
      when is_integer(organization_id) and is_integer(prescription_id) do
    %PrescriptionItem{}
    |> PrescriptionItem.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:prescription_id, prescription_id)
    |> Repo.insert()
  end

  ## Dispensing (§9 "Walk-in prescription → dispense", steps 2-3)

  @doc """
  Dispenses `quantity` for a prescription item by decrementing stock from eligible
  batches in FEFO order at the prescription's site. Updates the status of the item
  and prescription. Operates within a transaction to guarantee data integrity.

  Returns `{:error, :out_of_stock}` if stock is insufficient, `{:error, :over_dispensed}` 
  if `quantity` exceeds the prescribed amount, or `{:error, changeset}` for validation failures.
  """
  def dispense_item(organization_id, prescription_item_id, _pharmacist_id, quantity)
      when is_integer(organization_id) and is_integer(quantity) and quantity > 0 do
    Repo.transaction(fn ->
      item = get_prescription_item!(organization_id, prescription_item_id)
      prescription = get_prescription!(organization_id, item.prescription_id)
      site_id = prescription_site_id(prescription)

      with :ok <- validate_not_over_dispensed(item, quantity),
           :ok <- validate_site_id_present(site_id),
           batches = Batches.fefo_batches(organization_id, site_id, item.product_id),
           :ok <- consume_quantity_across_batches(batches, quantity),
           {:ok, updated_item} <- bump_quantity_dispensed(item, quantity),
           {:ok, _prescription} <- recompute_status(prescription) do
        updated_item
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp consume_quantity_across_batches(_batches, 0), do: :ok

  defp consume_quantity_across_batches([], quantity_needed) when quantity_needed > 0 do
    {:error, :out_of_stock}
  end

  defp consume_quantity_across_batches([%{remaining_quantity: rq} | rest], quantity_needed)
       when rq <= 0 do
    consume_quantity_across_batches(rest, quantity_needed)
  end

  defp consume_quantity_across_batches([batch | rest], quantity_needed) do
    to_consume = min(batch.remaining_quantity, quantity_needed)

    case Batches.decrement_remaining_quantity(batch, to_consume) do
      {:ok, _updated_batch} ->
        consume_quantity_across_batches(rest, quantity_needed - to_consume)

      {:error, reason} ->
        {:error, reason}
    end
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
