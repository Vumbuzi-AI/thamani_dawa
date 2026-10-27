defmodule ThamaniDawa.DistributorInvoices do
  import Ecto.Query, warn: false

  alias ThamaniDawa.DistributorInvoices.{Invoice, Payment}
  alias ThamaniDawa.Repo

  @doc "Lists all invoices for an organization, newest first, preloading customer and order."
  def list_invoices(organization_id) do
    Repo.all(
      from invoice in Invoice,
        where: invoice.organization_id == ^organization_id,
        order_by: [desc: invoice.number],
        preload: [:customer, :order]
    )
  end

  @doc """
  Gets a single invoice scoped to an organization, preloading customer, order,
  invoice lines (with product), and payments. Raises if not found.
  """
  def get_invoice!(organization_id, id) do
    Repo.one!(
      from invoice in Invoice,
        where: invoice.organization_id == ^organization_id,
        where: invoice.id == ^id,
        preload: [:customer, :order, lines: :product, payments: []]
    )
  end

  @doc """
  Returns the outstanding balance on an invoice in cents.

  Requires `invoice.payments` to be preloaded.
  """
  def invoice_balance(%Invoice{} = invoice) do
    paid = Enum.reduce(invoice.payments, 0, fn p, acc -> acc + p.amount end)
    invoice.total - paid
  end

  @doc """
  Returns the payment status of an invoice.

  - `:paid` — balance is zero or negative
  - `:partially_paid` — some payments recorded but balance remains
  - `:issued` — no payments recorded

  Requires `invoice.payments` to be preloaded.
  """
  def invoice_status(%Invoice{} = invoice) do
    balance = invoice_balance(invoice)

    cond do
      balance <= 0 -> :paid
      balance < invoice.total -> :partially_paid
      true -> :issued
    end
  end

  @doc "Lists all payments for an invoice, newest first."
  def list_payments(%Invoice{} = invoice) do
    Repo.all(
      from payment in Payment,
        where: payment.invoice_id == ^invoice.id,
        order_by: [desc: payment.paid_at]
    )
  end

  @doc """
  Records a payment against an invoice.

  Validates that `amount` does not exceed the current outstanding balance.
  Requires `invoice.payments` to be preloaded so the balance can be computed.

  Returns `{:ok, payment}` or `{:error, changeset}`.
  """
  def record_payment(organization_id, %Invoice{} = invoice, attrs) do
    attrs = Map.put_new(attrs, "paid_at", DateTime.utc_now() |> DateTime.truncate(:second))

    changeset =
      %Payment{}
      |> Payment.changeset(attrs)
      |> Ecto.Changeset.put_change(:organization_id, organization_id)
      |> Ecto.Changeset.put_change(:invoice_id, invoice.id)

    amount = Ecto.Changeset.get_field(changeset, :amount)
    balance = invoice_balance(invoice)

    changeset =
      if amount && amount > balance do
        Ecto.Changeset.add_error(
          changeset,
          :amount,
          "cannot exceed invoice balance of #{balance}"
        )
      else
        changeset
      end

    Repo.insert(changeset)
  end
end
