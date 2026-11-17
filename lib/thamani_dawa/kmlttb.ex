defmodule ThamaniDawa.Kmlttb do
  @moduledoc """
  Thin HTTP client for KMLTTB's (Kenya Medical Laboratory Technicians and
  Technologists Board) public facilities register (`kmlttb.org`) — the body
  that licenses diagnostic labs, not PPB. Same "verify against a real
  registry" pattern as `ThamaniDawa.Ppb` and `ThamaniDawa.Grp`.

  Like PPB, this is an undocumented internal endpoint of a government site,
  not a published API: searching returns a real HTML table (not JSON, unlike
  PPB), and each result links to a per-facility detail page. Unlike PPB,
  KMLTTB's detail page shows the **full, unmasked** Licence No (e.g.
  `"L 01710/26"`), so verification here is an exact match rather than PPB's
  masked prefix/suffix comparison.

  Endpoint and the HTTP adapter can be overridden via
  `config :thamani_dawa, ThamaniDawa.Kmlttb`, the same way `ThamaniDawa.Ppb`
  is configured for tests.

  `verify_license/2`'s definitive results are cached briefly via
  `ThamaniDawa.RegistryCache` (disabled in tests) to absorb near-duplicate
  lookups for the same facility/license in quick succession.
  """

  alias ThamaniDawa.RegistryCache

  @default_base_url "https://kmlttb.org"

  @type facility :: %{name: String.t(), id: String.t(), county: String.t() | nil}
  @type detail :: %{
          name: String.t() | nil,
          file_no: String.t() | nil,
          type: String.t() | nil,
          class: String.t() | nil,
          county: String.t() | nil,
          license_no: String.t() | nil,
          status: String.t() | nil,
          valid_until: String.t() | nil
        }
  @type verify_error :: {:error, :provider_error | :timeout}

  @doc "Searches the facilities register by name."
  @spec search_facilities(String.t()) :: {:ok, [facility()]} | verify_error()
  def search_facilities(name) do
    case Req.get(
           search_url(),
           req_options(
             params: [search: name, filter: "", value: "", sort: "Name", order: "ASC", page: 1]
           )
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, parse_rows(to_string(body))}

      {:ok, %Req.Response{}} ->
        {:error, :provider_error}

      {:error, _reason} ->
        {:error, :timeout}
    end
  end

  @doc "Fetches the detail page for a facility id returned by `search_facilities/1`."
  @spec fetch_detail(String.t()) :: {:ok, detail()} | verify_error()
  def fetch_detail(id) do
    case Req.get(detail_url(), req_options(params: [id: id])) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, parse_detail(to_string(body))}

      {:ok, %Req.Response{}} ->
        {:error, :provider_error}

      {:error, _reason} ->
        {:error, :timeout}
    end
  end

  @type verify_result ::
          {:ok, :verified, detail()}
          | {:ok, :license_inactive, detail()}
          | {:ok, :ambiguous, [detail()]}
          | {:error, :name_not_found}
          | {:error, :license_mismatch}
          | verify_error()

  @doc """
  Searches for `facility_name` and checks `license_number` against the exact
  Licence No of each candidate's detail page. Exactly one match is
  `:verified` if KMLTTB's own `Status` for it is `"ACTIVE"`, or
  `:license_inactive` otherwise (same conservative-unless-confirmed
  principle as `ThamaniDawa.Ppb.active?/1` — only `"ACTIVE"` is confirmed
  from a real response). More than one match is `:ambiguous`;
  `:name_not_found` means the search itself returned nothing;
  `:license_mismatch` means the name matched but no candidate's licence
  number matched.
  """
  @spec verify_license(String.t(), String.t()) :: verify_result()
  def verify_license(facility_name, license_number) do
    RegistryCache.fetch(
      {:kmlttb, facility_name, license_number},
      fn -> do_verify_license(facility_name, license_number) end,
      &cacheable_verify_result?/1
    )
  end

  defp do_verify_license(facility_name, license_number) do
    with {:ok, facilities} <- search_facilities(facility_name) do
      if facilities == [] do
        {:error, :name_not_found}
      else
        case fetch_details(facilities) do
          {:ok, details} ->
            case Enum.filter(details, &license_match?(license_number, &1.license_no)) do
              [one] ->
                if active?(one), do: {:ok, :verified, one}, else: {:ok, :license_inactive, one}

              [] ->
                {:error, :license_mismatch}

              many ->
                {:ok, :ambiguous, many}
            end

          error ->
            error
        end
      end
    end
  end

  defp active?(%{status: status}) when is_binary(status) do
    String.upcase(String.trim(status)) == "ACTIVE"
  end

  defp active?(_detail), do: false

  defp cacheable_verify_result?({:ok, _, _}), do: true
  defp cacheable_verify_result?({:error, :name_not_found}), do: true
  defp cacheable_verify_result?({:error, :license_mismatch}), do: true
  defp cacheable_verify_result?(_result), do: false

  defp fetch_details(facilities) do
    Enum.reduce_while(facilities, {:ok, []}, fn facility, {:ok, acc} ->
      case fetch_detail(facility.id) do
        {:ok, detail} -> {:cont, {:ok, [detail | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Exact, whitespace/case-insensitive comparison of two license numbers."
  @spec license_match?(String.t(), String.t() | nil) :: boolean()
  def license_match?(entered, actual) when is_binary(entered) and is_binary(actual) do
    normalize(entered) == normalize(actual)
  end

  def license_match?(_entered, _actual), do: false

  defp normalize(value),
    do: value |> to_string() |> String.replace(~r/\s+/, "") |> String.upcase()

  defp parse_rows(html) do
    ~r/<td class="name-column">\s*<a href="view_record\.php\?id=(\d+)"[^>]*>(.*?)<\/a>\s*<\/td>\s*<td[^>]*>.*?<\/td>\s*<td[^>]*>(.*?)<\/td>/s
    |> Regex.scan(html)
    |> Enum.map(fn [_match, id, name_html, county] ->
      %{id: id, name: strip_tags(name_html), county: strip_tags(county)}
    end)
  end

  defp parse_detail(html) do
    %{
      name: extract_row(html, "Name"),
      file_no: extract_row(html, "File No"),
      type: extract_row(html, "Type"),
      class: extract_row(html, "Class"),
      county: extract_row(html, "County"),
      license_no: extract_row(html, "Licence No"),
      valid_until: extract_row(html, "Valid Until"),
      status: extract_row(html, "Status")
    }
  end

  defp extract_row(html, label) do
    case Regex.run(~r/<th>#{Regex.escape(label)}<\/th>\s*<td>(.*?)<\/td>/s, html) do
      [_, value] -> value |> strip_tags() |> String.trim()
      _ -> nil
    end
  end

  defp strip_tags(html),
    do: html |> to_string() |> String.replace(~r/<[^>]*>/, "") |> String.trim()

  defp search_url, do: base_url() <> "/labsverification/licence_records.php"
  defp detail_url, do: base_url() <> "/labsverification/view_record.php"
  defp base_url, do: Keyword.get(config(), :base_url, @default_base_url)

  defp req_options(opts) do
    opts
    |> Keyword.merge(
      retry: Keyword.get(config(), :retry, :transient),
      max_retries: 3,
      receive_timeout: 30_000
    )
    |> put_plug()
  end

  defp put_plug(options) do
    case Keyword.get(config(), :plug) do
      nil -> options
      plug -> Keyword.put(options, :plug, plug)
    end
  end

  defp config, do: Application.get_env(:thamani_dawa, __MODULE__, [])
end
