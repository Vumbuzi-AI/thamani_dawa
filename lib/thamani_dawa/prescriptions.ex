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
    Repo.all(
      from p in Prescription,
        left_join: v in PatientVisit,
        on: v.id == p.patient_visit_id,
        where: p.organization_id == ^organization_id,
        select: %{p | site_id: v.site_id}
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
  Dispenses `quantity` of a `prescription_items` row: FEFO-picks a batch at
  the prescription's own site, decrements its `remaining_quantity`, then
  rolls `prescription_items`/`prescriptions` status forward. All in one
  transaction, so stock and dispensing state never drift apart.

  Returns `{:error, :out_of_stock}` when no eligible batch exists at that
  site, `{:error, :over_dispensed}` when `quantity` would exceed what's left
  to dispense on the item, or `{:error, changeset}` for any other
  validation failure.
  """
  def dispense_item(organization_id, prescription_item_id, _pharmacist_id, quantity)
      when is_integer(organization_id) and is_integer(quantity) and quantity > 0 do
    Repo.transaction(fn ->
      item = get_prescription_item!(organization_id, prescription_item_id)
      prescription = get_prescription!(organization_id, item.prescription_id)
      site_id = prescription_site_id(prescription)

      with :ok <- validate_not_over_dispensed(item, quantity),
           {:ok, batch} <-
             Batches.fefo_batch(organization_id, site_id, item.product_id),
           {:ok, _batch} <- Batches.decrement_remaining_quantity(batch, quantity),
           {:ok, updated_item} <- bump_quantity_dispensed(item, quantity),
           {:ok, _prescription} <- recompute_status(prescription) do
        updated_item
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # `prescriptions` no longer carries its own `site_id` — it's derived from
  # the `patient_visits` row it's tied to via `patient_visit_id`.
  defp prescription_site_id(%Prescription{patient_visit_id: nil}), do: nil

  defp prescription_site_id(%Prescription{patient_visit_id: patient_visit_id}) do
    Repo.get!(PatientVisit, patient_visit_id).site_id
  end

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
