defmodule ThamaniDawa.VerifyGtin do
  def verify(gtin) do
    url = "https://grp.gs1.org/grp/v3.2/gtins/verified"

    headers = [
      {"Content-Type", "application/json"},
      {"Cache-Control", "no-cache"},
      {"APIKEY", "5c969e5eb17a4704a07c9ad7557190fa"}
    ]

    body = [gtin]

    req_options = [
      headers: headers,
      json: body,
      retry: :transient,
      max_retries: 5,
      receive_timeout: 60_000
    ]

    case Req.post(url, req_options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        if Enum.empty?(body) do
          {:ok, :not_verified}
        else
          {:ok, body}
        end

      {:ok, %Req.Response{status: status}} when status in 400..599 ->
        {:ok, :not_verified}

      {:error, _reason} ->
        {:ok, :not_verified}
    end
  end
end
