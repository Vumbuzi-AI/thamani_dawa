defmodule ThamaniDawa.Daraja do
  @moduledoc """
  Safaricom Daraja STK Push client: authenticates via OAuth client-credentials, then initiates
  an STK Push prompting a patient's phone for M-Pesa payment. Stateless and tenant-agnostic —
  callers (`ThamaniDawa.Payments`) decide how a result maps into their own org-scoped records.

  Never logs credentials (consumer key/secret, passkey), the derived STK Push password, the
  OAuth token, or full request/response bodies — only high-level outcome data (status, provider
  response/error codes).
  """

  require Logger

  @auth_path "/oauth/v1/generate?grant_type=client_credentials"
  @stk_push_path "/mpesa/stkpush/v1/processrequest"

  @type stk_push_result :: %{checkout_request_id: String.t(), merchant_request_id: String.t()}

  @doc """
  Authenticates, then initiates an STK Push prompting `phone` to pay `amount` (in KES).
  `account_reference` and `transaction_desc` are surfaced to the customer's phone and in
  Safaricom's own transaction records.
  """
  @spec initiate_stk_push(String.t(), number(), String.t(), String.t()) ::
          {:ok, stk_push_result}
          | {:error, :invalid_phone | :invalid_amount | :auth_failed | :provider_error | :timeout}
  def initiate_stk_push(phone, amount, account_reference, transaction_desc) do
    with {:ok, formatted_phone} <- normalize_phone(phone),
         {:ok, whole_amount} <- normalize_amount(amount),
         {:ok, token} <- authenticate() do
      request_stk_push(token, formatted_phone, whole_amount, account_reference, transaction_desc)
    end
  end

  @doc """
  Normalizes a Kenyan phone number (`0712345678`, `+254712345678`, `254712345678`, with or
  without spaces/dashes) to Safaricom's required `2547XXXXXXXX`/`2541XXXXXXXX` form.
  """
  @spec normalize_phone(String.t()) :: {:ok, String.t()} | {:error, :invalid_phone}
  def normalize_phone(phone) when is_binary(phone) do
    case String.replace(phone, ~r/[^\d]/, "") do
      "0" <> <<lead::binary-size(1), _::binary>> = digits when byte_size(digits) == 10 ->
        maybe_valid_lead(lead, "254" <> binary_part(digits, 1, 9))

      "254" <> <<lead::binary-size(1), _::binary>> = rest when byte_size(rest) == 12 ->
        maybe_valid_lead(lead, "254" <> binary_part(rest, 3, 9))

      <<lead::binary-size(1), _::binary>> = digits when byte_size(digits) == 9 ->
        maybe_valid_lead(lead, "254" <> digits)

      _ ->
        {:error, :invalid_phone}
    end
  end

  def normalize_phone(_phone), do: {:error, :invalid_phone}

  defp maybe_valid_lead(lead, formatted) when lead in ["1", "7"], do: {:ok, formatted}
  defp maybe_valid_lead(_lead, _formatted), do: {:error, :invalid_phone}

  defp normalize_amount(amount) when is_integer(amount) and amount > 0, do: {:ok, amount}

  defp normalize_amount(%Decimal{} = amount) do
    if Decimal.compare(amount, 0) == :gt do
      {:ok, amount |> Decimal.round(0, :up) |> Decimal.to_integer()}
    else
      {:error, :invalid_amount}
    end
  end

  defp normalize_amount(amount) when is_float(amount) and amount > 0, do: {:ok, ceil(amount)}
  defp normalize_amount(_amount), do: {:error, :invalid_amount}

  defp authenticate do
    config = config()
    auth = {:basic, "#{config[:consumer_key]}:#{config[:consumer_secret]}"}
    req = base_req(config, auth: auth)

    case Req.get(req, url: @auth_path) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("Daraja OAuth failed with status #{status}")
        {:error, :auth_failed}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _exception} ->
        Logger.warning("Daraja OAuth request failed")
        {:error, :timeout}
    end
  end

  defp request_stk_push(token, phone, amount, account_reference, transaction_desc) do
    config = config()
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    password = Base.encode64(config[:shortcode] <> config[:passkey] <> timestamp)

    req = base_req(config, auth: {:bearer, token})

    body = %{
      "BusinessShortCode" => config[:shortcode],
      "Password" => password,
      "Timestamp" => timestamp,
      "TransactionType" => "CustomerPayBillOnline",
      "Amount" => amount,
      "PartyA" => phone,
      "PartyB" => config[:shortcode],
      "PhoneNumber" => phone,
      "CallBackURL" => config[:callback_url],
      "AccountReference" => account_reference,
      "TransactionDesc" => transaction_desc
    }

    case Req.post(req, url: @stk_push_path, json: body) do
      {:ok, %Req.Response{status: 200, body: %{"ResponseCode" => "0"} = resp}} ->
        {:ok,
         %{
           checkout_request_id: resp["CheckoutRequestID"],
           merchant_request_id: resp["MerchantRequestID"]
         }}

      {:ok, %Req.Response{status: status, body: resp}} ->
        Logger.warning(
          "Daraja STK push rejected (status #{status}): #{inspect(safe_error_fields(resp))}"
        )

        {:error, :provider_error}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, _exception} ->
        Logger.warning("Daraja STK push request failed")
        {:error, :timeout}
    end
  end

  defp safe_error_fields(resp) when is_map(resp) do
    Map.take(resp, ["ResponseCode", "ResponseDescription", "errorCode", "errorMessage"])
  end

  defp safe_error_fields(_resp), do: %{}

  defp base_req(config, extra_opts) do
    opts = [base_url: config[:base_url], receive_timeout: 10_000, retry: false]

    opts
    |> Keyword.merge(Keyword.take(config, [:plug]))
    |> Keyword.merge(extra_opts)
    |> Req.new()
  end

  defp config, do: Application.get_env(:thamani_dawa, __MODULE__, [])
end
