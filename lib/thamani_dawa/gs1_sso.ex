defmodule ThamaniDawa.Gs1Sso do
  @moduledoc false

  def exchange_code(code, verifier) do
    config = config()

    result =
      Req.post(request(config),
        url: config[:token_url],
        form: [
          grant_type: "authorization_code",
          code: code,
          redirect_uri: config[:callback_url],
          client_id: config[:client_id],
          client_secret: config[:client_secret],
          code_verifier: verifier
        ]
      )

    case result do
      {:ok, %Req.Response{status: status, body: %{"access_token" => token}}}
      when status in 200..299 and is_binary(token) ->
        {:ok, token}

      _ ->
        {:error, :token_exchange_failed}
    end
  end

  def fetch_userinfo(token) do
    config = config()

    result = Req.get(request(config), url: config[:userinfo_url], auth: {:bearer, token})

    case result do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        validate_userinfo(body)

      _ ->
        {:error, :userinfo_failed}
    end
  end

  def authorization_url(state, challenge) do
    config = config()

    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => config[:client_id],
        "redirect_uri" => config[:callback_url],
        "scope" => "openid profile email",
        "state" => state,
        "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      })

    config[:authorization_url] <> "?" <> query
  end

  defp validate_userinfo(%{"sub" => sub, "email" => email, "email_verified" => true})
       when is_binary(sub) and sub != "" and is_binary(email) and email != "" do
    {:ok, %{sub: sub, email: email}}
  end

  defp validate_userinfo(_body), do: {:error, :invalid_userinfo}

  defp request(config) do
    [receive_timeout: 10_000, retry: config[:retry] || false]
    |> Keyword.merge(Keyword.take(config, [:plug]))
    |> Req.new()
  end

  defp config, do: Application.fetch_env!(:thamani_dawa, __MODULE__)
end
