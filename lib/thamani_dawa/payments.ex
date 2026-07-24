defmodule ThamaniDawa.Payments do
  @moduledoc """
  Organization-scoped payment records tied to a `Prescription` or a
  `LabOrder`, plus the immutable `WalletEntry` ledger that is the sole
  source of truth for site earnings — there is no mutable balance column
  anywhere in this context.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Payments.WalletEntry
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Repo

  @doc "Lists all payments for an organization."
  def list_payments(organization_id) do
    Repo.all(from p in Payment, where: p.organization_id == ^organization_id)
  end

  @doc "Gets a single payment scoped to an organization. Raises if not found."
  def get_payment!(organization_id, id) do
    Repo.get_by!(Payment, id: id, organization_id: organization_id)
  end

  @doc """
  Records a new payment attempt against exactly one of `prescription_id` or
  `lab_order_id`. `site_id` is derived from that order (not accepted from
  `attrs`) so a payment can never be attributed to a site other than the
  one its order actually belongs to.
  """
  def create_payment(organization_id, attrs) when is_integer(organization_id) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> validate_belongs_to_org(:prescription_id, Prescription, organization_id)
    |> validate_belongs_to_org(:lab_order_id, LabOrder, organization_id)
    |> put_site_id(organization_id)
    |> Repo.insert()
  end

  @doc """
  Marks a pending payment as completed and credits the site wallet exactly
  once. Idempotent: calling this again on an already-completed payment is a
  no-op, and the unique index on `wallet_entries.payment_id` keeps the
  credit itself idempotent even under a concurrent duplicate call.
  """
  def complete_payment(%Payment{status: :completed} = payment), do: {:ok, payment}
  def complete_payment(%Payment{status: :failed}), do: {:error, :already_failed}

  def complete_payment(%Payment{status: :pending} = payment) do
    Repo.transaction(fn ->
      with {:ok, completed} <-
             payment
             |> Payment.complete_changeset(%{paid_at: DateTime.utc_now()})
             |> Repo.update(),
           {:ok, _entry} <- credit_wallet(completed) do
        completed
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Marks a pending payment as failed, recording `reason`. Creates no wallet
  credit. Idempotent: calling this again on an already-failed payment is a
  no-op.
  """
  def fail_payment(%Payment{status: :failed} = payment, _reason), do: {:ok, payment}
  def fail_payment(%Payment{status: :completed}, _reason), do: {:error, :already_completed}

  def fail_payment(%Payment{status: :pending} = payment, reason) do
    payment
    |> Payment.fail_changeset(%{failure_reason: reason})
    |> Repo.update()
  end

  @doc "Sums wallet credits for a site — the site's earnings ledger balance."
  def site_earnings(organization_id, site_id) do
    Repo.one(
      from w in WalletEntry,
        where: w.organization_id == ^organization_id,
        where: w.site_id == ^site_id,
        select: sum(w.amount)
    ) || Decimal.new(0)
  end

  defp credit_wallet(%Payment{} = payment) do
    %WalletEntry{}
    |> WalletEntry.changeset(%{
      site_id: payment.site_id,
      payment_id: payment.id,
      amount: payment.amount
    })
    |> Ecto.Changeset.put_change(:organization_id, payment.organization_id)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :payment_id)
  end

  defp put_site_id(changeset, organization_id) do
    case Ecto.Changeset.get_field(changeset, :lab_order_id) do
      nil -> put_site_id_from_prescription(changeset, organization_id)
      lab_order_id -> put_site_id_from_lab_order(changeset, organization_id, lab_order_id)
    end
  end

  defp put_site_id_from_lab_order(changeset, organization_id, lab_order_id) do
    case Repo.get_by(LabOrder, id: lab_order_id, organization_id: organization_id) do
      nil -> changeset
      lab_order -> Ecto.Changeset.put_change(changeset, :site_id, lab_order.site_id)
    end
  end

  defp put_site_id_from_prescription(changeset, organization_id) do
    case Ecto.Changeset.get_field(changeset, :prescription_id) do
      nil ->
        changeset

      prescription_id ->
        with %Prescription{patient_visit_id: patient_visit_id} <-
               Repo.get_by(Prescription, id: prescription_id, organization_id: organization_id),
             %PatientVisit{site_id: site_id} <-
               Repo.get_by(PatientVisit, id: patient_visit_id, organization_id: organization_id) do
          Ecto.Changeset.put_change(changeset, :site_id, site_id)
        else
          nil -> changeset
        end
    end
  end

  defp validate_belongs_to_org(changeset, field, schema, organization_id) do
    Ecto.Changeset.validate_change(changeset, field, fn _field, id ->
      case Repo.get_by(schema, id: id, organization_id: organization_id) do
        nil -> [{field, "does not belong to this organization"}]
        _record -> []
      end
    end)
  end
end
