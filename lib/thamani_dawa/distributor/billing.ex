defmodule ThamaniDawa.Distributor.Billing do
  @moduledoc """
  Serialisation billing for distributors: plan choice, allowance
  authorization, and payments.

  An organization must choose a plan before the shipment workflow is
  reachable:

    * **Prepay bundle** — buy a fixed quantity of serials up front
      (`choose_prepay/1`, then `start_prepay_payment/3`).
    * **Flex pay-as-you-go** — no upfront purchase; an uncapped cycle opens
      immediately (`ensure_first_postpay_cycle/1`) and is settled later for
      exactly what was used (`start_postpay_payment/3`).

  Shipment approval is the distributor's billable "generation" event: it
  calls `authorize_generation/2` with the number of SSCCs it is about to
  issue, inside its own transaction.

  Payments go through M-Pesa STK Push (`ThamaniDawa.Daraja`, confirmed by
  `ThamaniDawaWeb.DarajaCallbackController`) or a manually entered
  reference. `confirm_paid/1` is idempotent, so it is safe whichever of the
  callback or a retry gets there first.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Daraja
  alias ThamaniDawa.Distributor.{Pricing, SerialPayment, SerialUsage}
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @plans ~w(prepay flex)
  @methods ~w(mpesa manual)

  ## PubSub

  @doc "PubSub topic for an organization's billing updates."
  def topic(organization_id), do: "distributor_billing:#{organization_id}"

  def subscribe(organization_id),
    do: Phoenix.PubSub.subscribe(ThamaniDawa.PubSub, topic(organization_id))

  defp broadcast(%SerialPayment{} = payment) do
    Phoenix.PubSub.broadcast(
      ThamaniDawa.PubSub,
      topic(payment.organization_id),
      {:serial_payment, payment.status, payment.id}
    )
  end

  ## Plans

  @doc "Whether the organization has chosen a serialisation plan."
  def plan_selected?(%Organization{serialisation_type: type}), do: type in @plans

  def plan_selected?(organization_id) when is_integer(organization_id),
    do: organization_id |> organization!() |> plan_selected?()

  @doc "The organization's active usage cycle, or nil."
  def active_usage(organization_id) do
    Repo.one(
      from u in SerialUsage,
        where: u.organization_id == ^organization_id and u.status == "active"
    )
  end

  @doc "Chooses the prepay plan. Serials become available once a bundle is paid for."
  def choose_prepay(%Organization{} = organization) do
    if plan_selected?(organization) do
      {:error, :plan_already_selected}
    else
      organization
      |> Ecto.Changeset.change(serialisation_type: "prepay")
      |> Repo.update()
    end
  end

  @doc """
  Chooses the flex plan and opens its first billing cycle, atomically.
  Idempotent: an organization already on flex with an open cycle is
  returned unchanged.
  """
  def ensure_first_postpay_cycle(%Organization{} = organization) do
    Repo.transaction(fn ->
      organization = lock_organization!(organization.id)

      cond do
        organization.serialisation_type == "flex" ->
          active_usage(organization.id) || open_flex_cycle!(organization.id)

        plan_selected?(organization) ->
          Repo.rollback(:plan_already_selected)

        true ->
          organization
          |> Ecto.Changeset.change(serialisation_type: "flex")
          |> Repo.update!()

          open_flex_cycle!(organization.id)
      end
    end)
  end

  defp open_flex_cycle!(organization_id, carried \\ {0, 0}) do
    {running_quantity, running_buffer} = carried
    now = now()

    Repo.insert!(%SerialUsage{
      organization_id: organization_id,
      type: "flex",
      status: "active",
      quantity_limit: nil,
      running_quantity: running_quantity,
      running_buffer: running_buffer,
      cycle_started_at: now,
      billing_date: DateTime.add(now, Pricing.flex_cycle_days() * 86_400, :second)
    })
  end

  ## Allowance

  @doc """
  Spends `count` serials from the organization's active allowance. Must run
  inside the caller's transaction; the usage row is locked for update.

  Returns `{:ok, usage}` or `{:error, reason}` where reason is
  `:no_active_plan`, `:insufficient_allowance` (prepay bundle and buffer
  exhausted), or `:overdue` (flex cycle past due and buffer exhausted).
  """
  def authorize_generation(organization_id, count) when is_integer(count) and count > 0 do
    query =
      from u in SerialUsage,
        where: u.organization_id == ^organization_id and u.status == "active",
        lock: "FOR UPDATE"

    case Repo.one(query) do
      nil -> {:error, :no_active_plan}
      usage -> spend(usage, count)
    end
  end

  defp spend(%SerialUsage{type: "prepay"} = usage, count) do
    available = SerialUsage.serials_left(usage)
    overflow = max(count - available, 0)

    if usage.running_buffer + overflow <= Pricing.buffer_limit() do
      usage
      |> Ecto.Changeset.change(
        running_quantity: usage.running_quantity + (count - overflow),
        running_buffer: usage.running_buffer + overflow
      )
      |> Repo.update()
    else
      {:error, :insufficient_allowance}
    end
  end

  defp spend(%SerialUsage{type: "flex"} = usage, count) do
    cond do
      not SerialUsage.overdue?(usage) ->
        usage
        |> Ecto.Changeset.change(running_quantity: usage.running_quantity + count)
        |> Repo.update()

      usage.running_buffer + count <= Pricing.buffer_limit() ->
        usage
        |> Ecto.Changeset.change(running_buffer: usage.running_buffer + count)
        |> Repo.update()

      true ->
        {:error, :overdue}
    end
  end

  ## Quotes

  @doc """
  Quotes a prepay purchase of `quantity` serials, folding in any buffer
  accrued on the current bundle.
  """
  def prepay_quote(%Organization{} = organization, quantity) do
    buffer = current_prepay_buffer(organization.id)

    organization
    |> Pricing.total(:prepay, quantity + buffer)
    |> Map.merge(%{purchased_quantity: quantity, buffer_quantity: buffer})
  end

  @doc "Quotes settlement of the open flex cycle: exactly what was generated."
  def postpay_quote(%Organization{} = organization) do
    case active_usage(organization.id) do
      %SerialUsage{type: "flex"} = usage ->
        organization
        |> Pricing.total(:flex, SerialUsage.generated(usage))
        |> Map.merge(%{
          purchased_quantity: usage.running_quantity,
          buffer_quantity: usage.running_buffer,
          usage: usage
        })

      _ ->
        nil
    end
  end

  defp current_prepay_buffer(organization_id) do
    case active_usage(organization_id) do
      %SerialUsage{type: "prepay", running_buffer: buffer} -> buffer
      _ -> 0
    end
  end

  ## Payments

  @doc "Lists the organization's serialisation payments, newest first."
  def list_payments(organization_id) do
    Repo.all(
      from p in SerialPayment,
        where: p.organization_id == ^organization_id,
        order_by: [desc: p.inserted_at, desc: p.id]
    )
  end

  @doc "Gets an organization's payment. Raises if not found."
  def get_payment!(organization_id, id) do
    Repo.get_by!(SerialPayment, id: id, organization_id: organization_id)
  end

  @doc "Gets a payment by its M-Pesa CheckoutRequestID, or nil."
  def get_payment_by_reference(reference) when is_binary(reference),
    do: Repo.get_by(SerialPayment, provider_reference: reference)

  @doc """
  Starts a prepay bundle purchase. `attrs` carries `"quantity"`,
  `"method"` (`"mpesa"` or `"manual"`), and `"phone"` or
  `"manual_reference"`. M-Pesa payments stay pending until the Daraja
  callback confirms them; manual payments are confirmed immediately.
  """
  def start_prepay_payment(%Organization{} = organization, user, attrs) do
    with :ok <- require_plan(organization, "prepay"),
         {:ok, quantity} <- parse_quantity(attrs),
         {:ok, method} <- parse_method(attrs) do
      charge = prepay_quote(organization, quantity)

      organization
      |> insert_payment!(user, "prepay", method, charge, attrs)
      |> collect(method, attrs, "Serialisation bundle")
    end
  end

  @doc """
  Starts settlement of the open flex cycle for exactly what it generated.
  """
  def start_postpay_payment(%Organization{} = organization, user, attrs) do
    with :ok <- require_plan(organization, "flex"),
         {:ok, method} <- parse_method(attrs),
         %{quantity: billed} = charge when billed > 0 <- postpay_quote(organization) do
      organization
      |> insert_payment!(user, "postpay", method, charge, attrs)
      |> collect(method, attrs, "Serialisation usage")
    else
      nil -> {:error, :nothing_to_pay}
      %{quantity: 0} -> {:error, :nothing_to_pay}
      error -> error
    end
  end

  defp require_plan(%Organization{serialisation_type: type}, type), do: :ok
  defp require_plan(_organization, _type), do: {:error, :wrong_plan}

  defp parse_quantity(attrs) do
    case Integer.parse(to_string(attrs["quantity"] || "")) do
      {quantity, ""} ->
        if quantity >= Pricing.minimum_prepay_quantity(),
          do: {:ok, quantity},
          else: {:error, :quantity_below_minimum}

      _ ->
        {:error, :invalid_quantity}
    end
  end

  defp parse_method(%{"method" => method}) when method in @methods, do: {:ok, method}
  defp parse_method(_attrs), do: {:error, :invalid_method}

  defp insert_payment!(organization, user, kind, charge, attrs) do
    Repo.insert!(%SerialPayment{
      organization_id: organization.id,
      serial_usage_id: charge[:usage] && charge.usage.id,
      initiated_by_id: user && user.id,
      kind: kind,
      method: attrs["method"],
      status: "pending",
      quantity: charge.purchased_quantity,
      buffer_quantity: charge.buffer_quantity,
      unit_price: charge.unit_price,
      amount_excl_vat: charge.amount_excl_vat,
      vat_amount: charge.vat_amount,
      amount: charge.amount,
      phone: blank_to_nil(attrs["phone"]),
      manual_reference: blank_to_nil(attrs["manual_reference"])
    })
  end

  defp collect(payment, "manual", _attrs, _description) do
    if payment.manual_reference do
      confirm_paid(payment)
    else
      fail_payment(payment, "missing_manual_reference")
      {:error, :missing_manual_reference}
    end
  end

  defp collect(payment, "mpesa", attrs, description) do
    case Daraja.initiate_stk_push(
           attrs["phone"] || "",
           payment.amount,
           "SER-#{payment.organization_id}-#{payment.id}",
           description
         ) do
      {:ok, %{checkout_request_id: reference}} ->
        payment
        |> Ecto.Changeset.change(provider_reference: reference)
        |> Repo.update()

      {:error, reason} ->
        fail_payment(payment, "stk_push_#{reason}")
        {:error, reason}
    end
  end

  @doc """
  Confirms a payment as paid and credits the allowance exactly once.
  Idempotent: confirming an already-paid payment is a no-op.

    * prepay — closes the current bundle and opens a new one whose limit is
      the purchased quantity plus any serials left on the old bundle (its
      buffer was billed in this payment)
    * postpay — closes the settled flex cycle and opens a fresh one,
      carrying over anything generated after the settlement was quoted
  """
  def confirm_paid(%SerialPayment{id: id}) do
    result =
      Repo.transaction(fn ->
        payment = Repo.one!(from p in SerialPayment, where: p.id == ^id, lock: "FOR UPDATE")

        case payment.status do
          "paid" -> payment
          "pending" -> mark_paid!(payment)
          status -> Repo.rollback({:invalid_state, status})
        end
      end)

    with {:ok, payment} <- result do
      broadcast(payment)
      {:ok, payment}
    end
  end

  defp mark_paid!(payment) do
    usage = credit_allowance!(payment)

    payment
    |> Ecto.Changeset.change(
      status: "paid",
      paid_at: now(),
      serial_usage_id: usage.id,
      invoice_number: next_invoice_number!(payment.organization_id)
    )
    |> Repo.update!()
  end

  defp credit_allowance!(%SerialPayment{kind: "prepay"} = payment) do
    carryover =
      case close_active_usage!(payment.organization_id) do
        %SerialUsage{type: "prepay"} = usage -> SerialUsage.serials_left(usage)
        _ -> 0
      end

    Repo.insert!(%SerialUsage{
      organization_id: payment.organization_id,
      type: "prepay",
      status: "active",
      quantity_limit: payment.quantity + carryover,
      running_quantity: 0,
      running_buffer: 0,
      cycle_started_at: now()
    })
  end

  defp credit_allowance!(%SerialPayment{kind: "postpay"} = payment) do
    closed = close_active_usage!(payment.organization_id)

    carried =
      case closed do
        %SerialUsage{type: "flex"} = usage ->
          {max(usage.running_quantity - payment.quantity, 0),
           max(usage.running_buffer - payment.buffer_quantity, 0)}

        _ ->
          {0, 0}
      end

    open_flex_cycle!(payment.organization_id, carried)
  end

  defp close_active_usage!(organization_id) do
    query =
      from u in SerialUsage,
        where: u.organization_id == ^organization_id and u.status == "active",
        lock: "FOR UPDATE"

    case Repo.one(query) do
      nil ->
        nil

      usage ->
        usage
        |> Ecto.Changeset.change(status: "closed", closed_at: now())
        |> Repo.update!()
    end
  end

  defp next_invoice_number!(organization_id) do
    {1, [number]} =
      Repo.update_all(
        from(o in Organization,
          where: o.id == ^organization_id,
          select: o.next_serial_invoice_number
        ),
        inc: [next_serial_invoice_number: 1]
      )

    "INV-SER-" <> String.pad_leading(Integer.to_string(number), 6, "0")
  end

  @doc "Marks a pending payment as failed. Idempotent."
  def fail_payment(%SerialPayment{status: "failed"} = payment, _reason), do: {:ok, payment}
  def fail_payment(%SerialPayment{status: "paid"}, _reason), do: {:error, :already_paid}

  def fail_payment(%SerialPayment{} = payment, reason) do
    with {:ok, payment} <-
           payment
           |> Ecto.Changeset.change(status: "failed", failure_reason: reason)
           |> Repo.update() do
      broadcast(payment)
      {:ok, payment}
    end
  end

  defp organization!(organization_id), do: Repo.get!(Organization, organization_id)

  defp lock_organization!(organization_id) do
    Repo.one!(from o in Organization, where: o.id == ^organization_id, lock: "FOR UPDATE")
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
