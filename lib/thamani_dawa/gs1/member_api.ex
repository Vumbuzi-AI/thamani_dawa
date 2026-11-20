defmodule ThamaniDawa.GS1.MemberApi do
  @moduledoc """
  Client for the GS1 Kenya member API (`/activate`).

  SSCC numbers are minted by `POST /create_sscc`. The serials inside a case
  are read with `POST /get_sscc_contents`. Both calls use the sandbox
  contract as-is: the API chooses the SSCC, and contents returns every
  serial that member account has already issued for each GTIN and batch
  listed on the case.

  Credentials come from the environment, unless the caller passes an
  organization token:

    * `GS1_MEMBER_API_BASE_URL` — origin plus `/activate`, no trailing slash
    * `GS1_MEMBER_API_TOKEN` — bearer token used when no `:api_token` is passed

  `create_sscc` is not retried. A timeout can mean the SSCC was minted
  even though this process did not see it, and a second call would mint
  another one.
  """

  @callback post_create_sscc(map()) :: {:ok, String.t()} | {:error, term()}
  @callback post_sscc_contents(String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Mints an SSCC. `params` is the member-API body: `batch_info` and `address`
  are required by the API.
  """
  def create_sscc(params, opts \\ []) when is_map(params) and is_list(opts) do
    dispatch(:post_create_sscc, [params], opts)
  end

  @doc "Products, batches, and serials packed in `sscc`."
  def sscc_contents(sscc, opts \\ []) when is_binary(sscc) and is_list(opts) do
    dispatch(:post_sscc_contents, [sscc], opts)
  end

  def post_create_sscc(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/create_sscc", opts)
    |> decode_create_response()
  end

  def post_sscc_contents(sscc, opts \\ []) when is_binary(sscc) and is_list(opts) do
    %{"sscc" => sscc}
    |> post("/get_sscc_contents", opts)
    |> decode_contents_response()
  end

  # The test stub implements the callbacks at arity 1. The live client
  # carries the organization's token through to the request.
  defp dispatch(fun, args, opts) do
    case impl() do
      __MODULE__ -> apply(__MODULE__, fun, args ++ [opts])
      client -> apply(client, fun, args)
    end
  end

  @doc false
  def decode_create_response({:ok, status, body}) when status in 200..299 do
    extract_sscc(body)
  end

  def decode_create_response({:ok, status, body}) when status in [401, 403],
    do: {:error, auth_error(status, body)}

  def decode_create_response({:ok, 400, %{"result" => message}}) when is_binary(message),
    do: {:error, {:invalid, message}}

  def decode_create_response({:ok, 400, _body}),
    do: {:error, {:invalid, "GS1 rejected the SSCC request"}}

  def decode_create_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_create_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_create_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_contents_response({:ok, status, body}) when status in 200..299, do: {:ok, body}
  def decode_contents_response({:ok, 404, _body}), do: {:error, :not_found}

  def decode_contents_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_contents_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_contents_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_contents_response({:error, _reason}), do: {:error, :unavailable}

  defp extract_sscc(%{"sscc" => %{"sscc" => sscc}}) when is_binary(sscc) and sscc != "",
    do: {:ok, sscc}

  defp extract_sscc(%{"sscc" => sscc}) when is_binary(sscc) and sscc != "", do: {:ok, sscc}
  defp extract_sscc(_body), do: {:error, {:invalid, "GS1 did not return an SSCC"}}

  defp auth_error(401, _body), do: :unauthorized
  defp auth_error(403, _body), do: :forbidden

  defp post(params, path, opts) do
    with {:ok, base_url, token} <- credentials(opts) do
      options = [
        base_url: base_url,
        url: path,
        headers: [{"authorization", "Bearer " <> token}],
        json: params,
        receive_timeout: 15_000,
        retry: false
      ]

      options =
        case Keyword.get(config(), :plug) do
          nil -> options
          plug -> Keyword.put(options, :plug, plug)
        end

      case Req.post(Req.new(options)) do
        {:ok, %Req.Response{status: status, body: body}} ->
          {:ok, status, normalize_body(body)}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  defp credentials(opts) do
    cfg = config()
    base_url = cfg |> Keyword.get(:base_url) |> normalize_base()

    token =
      case Keyword.get(opts, :api_token) do
        value when is_binary(value) and value != "" -> value
        _ -> cfg |> Keyword.get(:api_token) |> blank_to_nil()
      end

    if is_binary(base_url) and is_binary(token) do
      {:ok, base_url, token}
    else
      {:error, :unconfigured}
    end
  end

  defp normalize_base(nil), do: nil

  defp normalize_base(url) when is_binary(url) do
    url = String.trim(url)

    case String.trim_trailing(url, "/") do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_body(body) when is_map(body), do: body

  defp normalize_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{"result" => body}
    end
  end

  defp normalize_body(body), do: %{"result" => inspect(body)}

  defp impl, do: Keyword.get(config(), :client, __MODULE__)
  defp config, do: Application.get_env(:thamani_dawa, __MODULE__, [])
end
