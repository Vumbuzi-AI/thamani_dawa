defmodule ThamaniDawa.GS1.MemberApi do
  @moduledoc """
  Client for the GS1 Kenya member API (`/activate`, plus the sibling
  `/HBS/products` endpoint on the same host).

  Standalone SSCC numbers are minted by `POST /create_sscc`; shipper SSCCs
  around already-issued primary serials are minted by `POST /create_shipper_sscc`.
  The serials inside a case
  are read with `POST /get_sscc_contents`. Both calls use the sandbox
  contract as-is: the API chooses the SSCC, and contents returns every
  serial that member account has already issued for each GTIN and batch
  listed on the case. `GET /HBS/products` lists every GTIN registered to
  the member account — unlike every other call here, it isn't under
  `/activate`, so it's requested against the base URL's host directly.
  `POST /get_company_prefixes` and `POST /list_glns` read the member's
  company prefixes and GLNs, used during signup.

  The base URL comes from the environment; the bearer token never does —
  every call must pass the calling organization's own token as `:api_token`
  (`ThamaniDawa.Organizations.gs1_api_key/1`). A call with no token returns
  `{:error, :unconfigured}` rather than silently using any platform-wide
  default.

    * `GS1_MEMBER_API_BASE_URL` — origin plus `/activate`, no trailing slash

  `create_sscc` is not retried. A timeout can mean the SSCC was minted
  even though this process did not see it, and a second call would mint
  another one.
  """

  @callback post_create_sscc(map()) :: {:ok, String.t()} | {:error, term()}
  @callback post_create_shipper_sscc(map()) :: {:ok, String.t()} | {:error, term()}
  @callback post_sscc_contents(String.t()) :: {:ok, map()} | {:error, term()}
  @callback post_create_serials(map()) :: {:ok, map()} | {:error, term()}
  @callback post_list_products(map()) :: {:ok, [map()]} | {:error, term()}
  @callback post_get_company_prefixes(map()) :: {:ok, [String.t()]} | {:error, term()}
  @callback post_list_glns(map()) :: {:ok, [map()]} | {:error, term()}
  @callback post_search_glns(map()) :: {:ok, [map()]} | {:error, term()}
  @callback post_barcode_batches(String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback post_batch_serials(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback post_unpacked_serials(String.t(), String.t() | nil) ::
              {:ok, [map()]} | {:error, term()}
  @callback post_mobile_users(String.t(), map()) :: {:ok, map()} | {:error, term()}

  @mobile_user_actions ~w(list create update resend_pin set_active)

  @doc """
  Mints an SSCC. `params` is the member-API body: `batch_info` and `address`
  are required by the API.
  """
  def create_sscc(params, opts \\ []) when is_map(params) and is_list(opts) do
    dispatch(:post_create_sscc, [params], opts)
  end

  @doc "Mints a shipper SSCC around previously issued primary serials."
  def create_shipper_sscc(params, opts \\ []) when is_map(params) and is_list(opts) do
    dispatch(:post_create_shipper_sscc, [params], opts)
  end

  @doc "Products, batches, and serials packed in `sscc`."
  def sscc_contents(sscc, opts \\ []) when is_binary(sscc) and is_list(opts) do
    dispatch(:post_sscc_contents, [sscc], opts)
  end

  @doc """
  Generates serialised DataMatrix codes for a GTIN/batch. `params` mirrors
  the member-API body: `barcode`, `batch`, `production`, `expiry`,
  `trade_item_qty`, `shipper_qty`, `from`, and `to` are required.
  """
  def create_serials(params, opts \\ []) when is_map(params) and is_list(opts) do
    dispatch(:post_create_serials, [params], opts)
  end

  @doc """
  Lists the GTINs registered to this member account, via
  `GET /HBS/products` — a sibling endpoint of the host the configured
  `/activate` base URL points at, not an `/activate` path itself.
  """
  def list_products(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    dispatch(:post_list_products, [params], opts)
  end

  @doc """
  Lists the company prefixes registered to the member account behind
  `opts[:api_token]`, via `POST /get_company_prefixes`.
  """
  def get_company_prefixes(opts \\ []) when is_list(opts) do
    dispatch(:post_get_company_prefixes, [%{}], opts)
  end

  @doc """
  Lists the GLNs registered to the member account behind
  `opts[:api_token]`, via `POST /list_glns`.
  """
  def list_glns(opts \\ []) when is_list(opts) do
    dispatch(:post_list_glns, [%{"per_page" => 500, "page" => 1}], opts)
  end

  @doc "Searches the GS1 directory for GLNs available to the supplied API token."
  def search_glns(query, opts \\ []) when is_binary(query) and is_list(opts) do
    dispatch(:post_search_glns, [%{"query" => query, "per_page" => 25, "page" => 1}], opts)
  end

  @doc """
  Every batch row GS1 has recorded for a GTIN, via
  `POST /getbarcode_batches`. Rows can repeat per serial; each carries
  `batch`, `production`, `expiry`, and (when serialised) `serial`.
  """
  def barcode_batches(gtin, opts \\ []) when is_binary(gtin) and is_list(opts) do
    dispatch(:post_barcode_batches, [gtin], opts)
  end

  @doc """
  Every serial GS1 has issued for a GTIN + batch, via
  `POST /get_batch_serials`. Each result carries `serial`, `payload`,
  `human_readable`, and `image`.
  """
  def batch_serials(gtin, batch, opts \\ [])
      when is_binary(gtin) and is_binary(batch) and is_list(opts) do
    dispatch(:post_batch_serials, [gtin, batch], opts)
  end

  @doc """
  Primary serials for a GTIN (optionally one batch) not yet packed into a
  shipper, via `POST /list_unpacked_serials` — the candidates for
  `create_shipper_sscc/2`. Each carries `serial`, `batch`, `production`,
  `expiry`.
  """
  def unpacked_serials(gtin, batch \\ nil, opts \\ []) when is_binary(gtin) and is_list(opts) do
    dispatch(:post_unpacked_serials, [gtin, batch], opts)
  end

  @doc """
  Healthcare mobile users on the member account, via
  `POST /list_healthcare_mobile_users`. Each is the API's JSON map: `id`
  (a UUID), `name`, `username`, `email`, `phone`, `active`, `role`
  (`"distribution"`/`"manufacturing"`), `access_scope`
  (`"full"`/`"aggregation_only"`), `last_login_at`.
  """
  def list_mobile_users(opts \\ []) when is_list(opts) do
    with {:ok, body} <- dispatch(:post_mobile_users, ["list", %{}], opts) do
      {:ok, List.wrap(body["mobile_users"])}
    end
  end

  @doc "Creates a mobile user; GS1 generates and emails the PIN."
  def create_mobile_user(params, opts \\ []) when is_map(params) and is_list(opts) do
    dispatch(:post_mobile_users, ["create", params], opts)
  end

  def update_mobile_user(id, params, opts \\ [])
      when is_binary(id) and is_map(params) and is_list(opts) do
    dispatch(:post_mobile_users, ["update", Map.put(params, "id", id)], opts)
  end

  @doc "Generates a new PIN, emails it, and signs the user out everywhere."
  def resend_mobile_user_pin(id, opts \\ []) when is_binary(id) and is_list(opts) do
    dispatch(:post_mobile_users, ["resend_pin", %{"id" => id}], opts)
  end

  def set_mobile_user_active(id, active, opts \\ [])
      when is_binary(id) and is_boolean(active) and is_list(opts) do
    dispatch(:post_mobile_users, ["set_active", %{"id" => id, "active" => active}], opts)
  end

  def post_mobile_users(action, params, opts \\ []) when action in @mobile_user_actions do
    params
    |> post(mobile_users_path(action), opts)
    |> decode_mobile_users_response()
  end

  defp mobile_users_path("list"), do: "/list_healthcare_mobile_users"
  defp mobile_users_path("create"), do: "/create_healthcare_mobile_user"
  defp mobile_users_path("update"), do: "/update_healthcare_mobile_user"
  defp mobile_users_path("resend_pin"), do: "/resend_healthcare_mobile_user_pin"
  defp mobile_users_path("set_active"), do: "/set_healthcare_mobile_user_active"

  @doc false
  def decode_mobile_users_response({:ok, status, body}) when status in 200..299,
    do: {:ok, body}

  def decode_mobile_users_response({:ok, 422, %{"errors" => errors}}) when is_map(errors),
    do: {:error, {:validation, errors}}

  def decode_mobile_users_response({:ok, 404, _body}), do: {:error, :not_found}

  # A 403 with a message means the key is valid but the member isn't a
  # healthcare account; without one it's an auth failure.
  def decode_mobile_users_response({:ok, 403, %{"result" => message}})
      when is_binary(message),
      do: {:error, {:invalid, message}}

  def decode_mobile_users_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, :unauthorized}

  def decode_mobile_users_response({:ok, status, %{"result" => message}})
      when status in 400..499 and is_binary(message),
      do: {:error, {:invalid, message}}

  def decode_mobile_users_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_mobile_users_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_mobile_users_response({:error, _reason}), do: {:error, :unavailable}

  def post_unpacked_serials(gtin, batch, opts \\ []) when is_binary(gtin) and is_list(opts) do
    %{"barcode" => gtin, "limit" => 1_000}
    |> then(&if(is_binary(batch) and batch != "", do: Map.put(&1, "batch", batch), else: &1))
    |> post("/list_unpacked_serials", opts)
    |> decode_unpacked_serials_response()
  end

  def post_barcode_batches(gtin, opts \\ []) when is_binary(gtin) and is_list(opts) do
    %{"barcode" => gtin}
    |> post("/getbarcode_batches", opts)
    |> decode_barcode_batches_response()
  end

  def post_batch_serials(gtin, batch, opts \\ [])
      when is_binary(gtin) and is_binary(batch) and is_list(opts) do
    %{"barcode" => gtin, "batch" => batch}
    |> post("/get_batch_serials", opts)
    |> decode_batch_serials_response()
  end

  def post_create_sscc(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/create_sscc", opts)
    |> decode_create_response()
  end

  def post_create_shipper_sscc(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/create_shipper_sscc", opts)
    |> decode_create_response()
  end

  def post_sscc_contents(sscc, opts \\ []) when is_binary(sscc) and is_list(opts) do
    %{"sscc" => sscc}
    |> post("/get_sscc_contents", opts)
    |> decode_contents_response()
  end

  def post_create_serials(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/create_serialised_datamatrix", opts)
    |> decode_serials_response()
  end

  def post_list_products(_params, opts \\ []) when is_list(opts) do
    opts
    |> get("/HBS/products")
    |> decode_products_response()
  end

  def post_get_company_prefixes(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/get_company_prefixes", opts)
    |> decode_prefixes_response()
  end

  def post_list_glns(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/list_glns", opts)
    |> decode_glns_response()
  end

  def post_search_glns(params, opts \\ []) when is_map(params) and is_list(opts) do
    params
    |> post("/search_glns", opts)
    |> decode_glns_response()
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

  # 400 bad request; 402 plan/allocation exhausted; 404 GLN not found;
  # 422 serials missing, already packed, or mixed batches.
  def decode_create_response({:ok, status, %{"result" => message}})
      when status in [400, 402, 404, 422] and is_binary(message),
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

  @doc false
  def decode_serials_response({:ok, status, body}) when status in 200..299, do: {:ok, body}

  def decode_serials_response({:ok, 404, _body}), do: {:error, :not_found}

  def decode_serials_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_serials_response({:ok, 400, %{"result" => message}}) when is_binary(message),
    do: {:error, {:invalid, message}}

  def decode_serials_response({:ok, 400, _body}),
    do: {:error, {:invalid, "GS1 rejected the serialisation request"}}

  def decode_serials_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_serials_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_serials_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_products_response({:ok, status, %{"products" => products}})
      when status in 200..299 and is_list(products) do
    {:ok, Enum.map(products, &normalize_product/1)}
  end

  def decode_products_response({:ok, status, _body}) when status in 200..299,
    do: {:ok, []}

  def decode_products_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_products_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_products_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_products_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_unpacked_serials_response({:ok, status, %{"serials" => serials}})
      when status in 200..299 and is_list(serials),
      do: {:ok, Enum.filter(serials, &is_map/1)}

  def decode_unpacked_serials_response({:ok, status, _body}) when status in 200..299,
    do: {:ok, []}

  def decode_unpacked_serials_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_unpacked_serials_response({:ok, 400, %{"result" => message}})
      when is_binary(message),
      do: {:error, {:invalid, message}}

  def decode_unpacked_serials_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_unpacked_serials_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_unpacked_serials_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_barcode_batches_response({:ok, status, %{"product" => %{"batches" => batches}}})
      when status in 200..299 and is_list(batches),
      do: {:ok, Enum.filter(batches, &is_map/1)}

  def decode_barcode_batches_response({:ok, status, _body}) when status in 200..299,
    do: {:ok, []}

  # GS1 answers 404 when the GTIN has no record yet: no batches.
  def decode_barcode_batches_response({:ok, 404, _body}), do: {:ok, []}

  def decode_barcode_batches_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_barcode_batches_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_barcode_batches_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_barcode_batches_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_batch_serials_response({:ok, status, %{"results" => results}})
      when status in 200..299 and is_list(results),
      do: {:ok, Enum.filter(results, &is_map/1)}

  def decode_batch_serials_response({:ok, status, _body}) when status in 200..299,
    do: {:ok, []}

  # GS1 answers 404 when the batch carries no serials yet.
  def decode_batch_serials_response({:ok, 404, _body}), do: {:ok, []}

  def decode_batch_serials_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_batch_serials_response({:ok, 400, %{"result" => message}}) when is_binary(message),
    do: {:error, {:invalid, message}}

  def decode_batch_serials_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_batch_serials_response({:error, :unconfigured}), do: {:error, :unconfigured}
  def decode_batch_serials_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_prefixes_response({:ok, status, %{"company_prefixes" => prefixes}})
      when status in 200..299 and is_list(prefixes) do
    {:ok, prefixes}
  end

  def decode_prefixes_response({:ok, status, _body}) when status in 200..299, do: {:ok, []}

  def decode_prefixes_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_prefixes_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_prefixes_response({:error, :unconfigured}), do: {:error, :unavailable}
  def decode_prefixes_response({:error, _reason}), do: {:error, :unavailable}

  @doc false
  def decode_glns_response({:ok, status, %{"glns" => glns}})
      when status in 200..299 and is_list(glns) do
    {:ok, glns}
  end

  def decode_glns_response({:ok, status, _body}) when status in 200..299, do: {:ok, []}

  def decode_glns_response({:ok, status, _body}) when status in [401, 403],
    do: {:error, auth_error(status, nil)}

  def decode_glns_response({:ok, _status, _body}), do: {:error, :unavailable}
  def decode_glns_response({:error, :unconfigured}), do: {:error, :unavailable}
  def decode_glns_response({:error, _reason}), do: {:error, :unavailable}

  defp normalize_product(product) do
    %{
      "gtin" => product["gtin"],
      "name" => product["name"],
      "description" => product["description"],
      "status" => if(product["status"] == "true", do: "active", else: "inactive"),
      "serial_count" => product["serial_count"],
      "sscc_count" => product["sscc_count"]
    }
  end

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

  defp get(opts, path) do
    with {:ok, base_url, token} <- credentials(opts) do
      options = [
        base_url: origin(base_url),
        url: path,
        headers: [{"authorization", "Bearer " <> token}],
        receive_timeout: 15_000,
        retry: false
      ]

      options =
        case Keyword.get(config(), :plug) do
          nil -> options
          plug -> Keyword.put(options, :plug, plug)
        end

      case Req.get(Req.new(options)) do
        {:ok, %Req.Response{status: status, body: body}} ->
          {:ok, status, normalize_body(body)}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  # `/HBS/products` is a sibling of `/activate` on the same host, not an
  # `/activate` path itself, so it's requested against the host the
  # configured base URL points at, dropping whatever path (`/activate`) is
  # configured onto it.
  defp origin(base_url) do
    uri = URI.parse(base_url)
    URI.to_string(%{uri | path: nil, query: nil, fragment: nil})
  end

  defp credentials(opts) do
    cfg = config()
    base_url = cfg |> Keyword.get(:base_url) |> normalize_base()
    token = opts |> Keyword.get(:api_token) |> blank_to_nil()

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
