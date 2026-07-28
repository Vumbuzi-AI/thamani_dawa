defmodule ThamaniDawa.PbbVerification do
  @moduledoc """
  Verifies PBB license numbers against external regulatory lookup endpoints or sandbox mocks.
  """

  require Logger
  alias ThamaniDawa.PbbNumber

  @type verification_result ::
          {:ok,
           %{status: :verified, premise_name: String.t() | nil, expiry_date: String.t() | nil}}
          | {:ok, %{status: :invalid_license}}
          | {:error, :invalid_format | :timeout | :provider_error | :network_error}

  @doc """
  Verifies a raw PBB number string. Normalizes and validates format first, then queries lookup API.
  """
  @spec verify(String.t() | nil) :: verification_result
  def verify(raw_pbb) do
    with {:ok, normalized} <- PbbNumber.validate_format(raw_pbb) do
      do_verify(normalized)
    end
  end

  defp do_verify(normalized_pbb) do
    # Check if a custom mock backend or environment configuration is set
    case Application.get_env(:thamani_dawa, :pbb_verification_backend) do
      :mock ->
        mock_verify(normalized_pbb)

      _ ->
        remote_verify(normalized_pbb)
    end
  end

  defp remote_verify(normalized_pbb) do
    endpoint =
      Application.get_env(
        :thamani_dawa,
        :pbb_api_url,
        "https://practice.pharmacyboardkenya.org/api/verify"
      )

    req_opts = [
      params: [license: normalized_pbb],
      retry: :transient,
      max_retries: 2,
      receive_timeout: 5000
    ]

    case Req.get(endpoint, req_opts) do
      {:ok, %Req.Response{status: 200, body: %{"valid" => true} = body}} ->
        {:ok,
         %{
           status: :verified,
           premise_name: body["premise_name"],
           expiry_date: body["expiry_date"]
         }}

      {:ok, %Req.Response{status: 200, body: %{"valid" => false}}} ->
        {:ok, %{status: :invalid_license}}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("PPB API lookup for #{normalized_pbb} returned status #{status}")
        {:ok, %{status: :unconfirmed}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("PPB API lookup for #{normalized_pbb} timed out")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("PPB API request failed for #{normalized_pbb}: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp mock_verify(normalized_pbb) do
    cond do
      String.contains?(normalized_pbb, "INVALID") ->
        {:ok, %{status: :invalid_license}}

      String.contains?(normalized_pbb, "TIMEOUT") ->
        {:error, :timeout}

      true ->
        {:ok,
         %{
           status: :verified,
           premise_name: "Mock Pharmacy Ltd",
           expiry_date: "2026-12-31"
         }}
    end
  end
end
