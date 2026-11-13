defmodule ThamaniDawaWeb.DarajaCallbackController do
  @moduledoc """
  Receives Safaricom's STK Push result callback. Daraja has no way to attach custom auth
  headers to callback delivery, so the shared secret lives in the URL itself (`:token`) —
  checked with a constant-time comparison before anything in the body is trusted.

  Always acknowledges with `200 OK` once authenticated, even for a payload we can't act on
  (unknown reference, malformed shape) — returning a non-2xx makes Safaricom retry delivery,
  which would just repeat the same problem. Never logs the request body: it can contain a
  phone number and (indirectly, via ResultDesc echoing back input) provider-side detail we
  don't need to persist verbatim.
  """

  use ThamaniDawaWeb, :controller

  require Logger

  alias ThamaniDawa.Distributor.{Billing, SerialPayment}
  alias ThamaniDawa.Payments

  def create(conn, %{"token" => token} = params) do
    if Plug.Crypto.secure_compare(token, callback_token()) do
      handle_callback(params)
      ack(conn)
    else
      Logger.warning("Daraja callback: rejected, token mismatch")
      conn |> put_status(:unauthorized) |> json(%{"error" => "unauthorized"})
    end
  end

  defp callback_token do
    Application.get_env(:thamani_dawa, ThamaniDawa.Daraja, [])[:callback_token] || ""
  end

  defp handle_callback(%{"Body" => %{"stkCallback" => stk_callback}})
       when is_map(stk_callback) do
    with %{"CheckoutRequestID" => reference, "ResultCode" => result_code} <- stk_callback,
         payment when not is_nil(payment) <- find_payment(reference) do
      apply_result(payment, result_code, stk_callback)
    else
      nil ->
        Logger.warning("Daraja callback: no payment found for the given reference")

      _ ->
        Logger.warning("Daraja callback: missing CheckoutRequestID/ResultCode")
    end
  end

  defp handle_callback(_params) do
    Logger.warning("Daraja callback: malformed payload, ignoring")
  end

  # STK pushes are initiated both for patient payments and for distributor
  # serialisation billing; the CheckoutRequestID is unique across both.
  defp find_payment(reference) when is_binary(reference) do
    Payments.get_payment_by_reference(reference) || Billing.get_payment_by_reference(reference)
  end

  defp find_payment(_reference), do: nil

  defp apply_result(%SerialPayment{} = payment, 0, _stk_callback),
    do: Billing.confirm_paid(payment)

  defp apply_result(%SerialPayment{} = payment, result_code, stk_callback),
    do: Billing.fail_payment(payment, failure_reason(result_code, stk_callback))

  defp apply_result(payment, 0, _stk_callback), do: Payments.complete_payment(payment)

  defp apply_result(payment, 1032, _stk_callback),
    do: Payments.fail_payment(payment, "cancelled_by_user")

  defp apply_result(payment, 1037, _stk_callback),
    do: Payments.fail_payment(payment, "timeout")

  defp apply_result(payment, result_code, stk_callback) do
    Payments.fail_payment(payment, "provider_error_#{result_code}: #{stk_callback["ResultDesc"]}")
  end

  defp failure_reason(1032, _stk_callback), do: "cancelled_by_user"
  defp failure_reason(1037, _stk_callback), do: "timeout"

  defp failure_reason(result_code, stk_callback),
    do: "provider_error_#{result_code}: #{stk_callback["ResultDesc"]}"

  defp ack(conn) do
    conn |> put_status(200) |> json(%{"ResultCode" => 0, "ResultDesc" => "Accepted"})
  end
end
