defmodule ThamaniDawa.Ppb do
  @moduledoc """
  Thin HTTP client for the Pharmacy and Poisons Board's public facilities
  register (`practice.pharmacyboardkenya.org`), used to verify a facility's
  PPB license during signup — the same "verify against a real registry"
  pattern `ThamaniDawa.Grp` uses for GS1.

  This is an undocumented internal AJAX endpoint of a government site, not a
  published API: searching returns JSON, but the per-facility detail view
  returns an HTML fragment, and the license number it shows back is always
  masked (e.g. `"BU2****1499"` — only the first and last few characters are
  visible). "Verification" therefore means searching by facility name, then
  checking whether the entered license number's visible prefix/suffix match
  the mask the registry returns, rather than an exact-value comparison.

  Endpoint and the HTTP adapter can be overridden via
  `config :thamani_dawa, ThamaniDawa.Ppb`, the same way `ThamaniDawa.Grp` is
  configured for tests.

  `verify_license/3`'s definitive results are cached briefly via
  `ThamaniDawa.RegistryCache` (disabled in tests) to absorb near-duplicate
  lookups for the same facility/license in quick succession.
  """

  alias ThamaniDawa.RegistryCache

  @default_base_url "https://practice.pharmacyboardkenya.org"

  @type facility :: %{name: String.t(), type: String.t(), status_text: String.t(), id: String.t()}
  @type detail :: %{
          name: String.t() | nil,
          masked_license: String.t() | nil,
          ownership: String.t() | nil,
          license_type: String.t() | nil,
          county: String.t() | nil,
          street: String.t() | nil,
          status: String.t() | nil,
          valid_till: String.t() | nil
        }
  @type verify_error :: {:error, :provider_error | :timeout}

  @doc """
  Searches the facilities register by name, optionally narrowed by `ftype`
  (`"retail"`, `"wholesale"`, `"hospital"`, `"manufacturer"`).

  PPB's own search does a literal, non-tokenized substring match against
  the full registered name — e.g. searching "Pharmaplus Kilifi" against a
  facility actually registered as "PHARMAPLUS PHARMACEUTICAL-KILIFI"
  returns nothing, because "Pharmaplus Kilifi" never appears contiguously
  in that string (confirmed directly against the live endpoint). Since
  users naturally type a shortened trading name rather than PPB's exact
  bureaucratic one, a multi-word query that comes back empty is retried
  with just its first word — trading names conventionally lead with the
  distinctive brand word, and `license_number` (checked afterward by
  `verify_license/3`) is what actually disambiguates the real match from
  the broader result set, not the name.
  """
  @spec search_facilities(String.t(), String.t() | nil) :: {:ok, [facility()]} | verify_error()
  def search_facilities(name, ftype \\ nil) do
    case do_search_facilities(name, ftype) do
      {:ok, []} -> search_facilities_by_first_word(name, ftype)
      other -> other
    end
  end

  defp search_facilities_by_first_word(name, ftype) do
    case String.split(name, ~r/\s+/, trim: true) do
      [first_word | [_ | _]] -> do_search_facilities(first_word, ftype)
      _ -> {:ok, []}
    end
  end

  defp do_search_facilities(name, ftype) do
    case Req.get(ajax_url(), search_req_options(name, ftype)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        case decode_search_body(body) do
          {:ok, %{"data" => rows}} when is_list(rows) ->
            {:ok, Enum.map(rows, &parse_row/1)}

          _other ->
            {:error, :provider_error}
        end

      {:ok, %Req.Response{}} ->
        {:error, :provider_error}

      {:error, _reason} ->
        {:error, :timeout}
    end
  end

  @doc "Fetches the detail fragment for a facility id returned by `search_facilities/2`."
  @spec fetch_detail(String.t()) :: {:ok, detail()} | verify_error()
  def fetch_detail(id) do
    case Req.get(ajax_url(), detail_req_options(id)) do
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
  Searches for `facility_name` (scoped to `ftype`) and checks
  `license_number` against the masked license of each candidate. Exactly
  one match is `:verified` if PPB's own `Licence Status` for it is
  `"VALID"`, or `:license_inactive` if it's anything else (including
  status strings we haven't catalogued yet — only `"VALID"` is confirmed
  from a real response, so unrecognized values are treated conservatively
  as not currently valid, same principle as `ThamaniDawa.Grp`'s
  `licenceStatus` handling). More than one mask match (the mask alone can't
  disambiguate them) is `:ambiguous`.

  The two failure reasons are deliberately distinct, since they call for
  different user-facing guidance: `:name_not_found` means the search
  itself returned nothing — either the name is wrong, or it's registered
  under a different `ftype` than the one searched (e.g. a retail-only
  facility searched with `ftype: "wholesale"`). `:license_mismatch` means
  the name matched at least one real facility, but none of their masked
  licenses match the number entered — the name is right, the number isn't.
  """
  @spec verify_license(String.t(), String.t(), String.t() | nil) :: verify_result()
  def verify_license(facility_name, license_number, ftype \\ nil) do
    RegistryCache.fetch(
      {:ppb, facility_name, license_number, ftype},
      fn -> do_verify_license(facility_name, license_number, ftype) end,
      &cacheable_verify_result?/1
    )
  end

  defp do_verify_license(facility_name, license_number, ftype) do
    with {:ok, facilities} <- search_facilities(facility_name, ftype) do
      if facilities == [] do
        {:error, :name_not_found}
      else
        case fetch_details(facilities) do
          {:ok, details} ->
            case Enum.filter(details, &license_match?(license_number, &1.masked_license)) do
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

  # Only "VALID" is a confirmed status value from a real response; every
  # other string (including ones we haven't seen yet) is treated as
  # inactive rather than assumed valid, until the full vocabulary is
  # confirmed with PPB — same principle as `ThamaniDawa.Grp.active?/1`.
  defp active?(%{status: status}) when is_binary(status) do
    String.upcase(String.trim(status)) == "VALID"
  end

  defp active?(_detail), do: false

  # Definitive answers only — `:name_not_found`/`:license_mismatch` are real
  # results worth remembering, but a transient `:provider_error`/`:timeout`
  # must never be cached, or an outage would get "remembered" past its
  # actual duration.
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

  @doc """
  Compares an entered license number against a masked value like
  `"BU2****1499"` — same length, same visible prefix, same visible suffix.
  """
  @spec license_match?(String.t(), String.t() | nil) :: boolean()
  def license_match?(entered, masked) when is_binary(entered) and is_binary(masked) do
    entered = normalize(entered)
    masked = normalize(masked)

    case String.split(masked, "*", trim: false) |> Enum.reject(&(&1 == "")) do
      [prefix, suffix] ->
        String.length(entered) == String.length(masked) and
          String.starts_with?(entered, prefix) and String.ends_with?(entered, suffix)

      _ ->
        false
    end
  end

  def license_match?(_entered, _masked), do: false

  defp normalize(value),
    do: value |> to_string() |> String.replace(~r/\s+/, "") |> String.upcase()

  defp parse_row([name, type, status_html, detail_html]) do
    %{
      name: name |> to_string() |> String.trim(),
      type: type |> to_string() |> String.trim(),
      status_text: strip_tags(status_html),
      id: extract_id(detail_html)
    }
  end

  defp parse_row(_row), do: %{name: nil, type: nil, status_text: nil, id: nil}

  defp extract_id(html) do
    case Regex.run(~r/rel='([^']*)'/, to_string(html)) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp strip_tags(html),
    do: html |> to_string() |> String.replace(~r/<[^>]*>/, "") |> String.trim()

  defp decode_search_body(body) when is_map(body), do: {:ok, body}

  defp decode_search_body(body) when is_binary(body) do
    body
    |> String.trim()
    |> Jason.decode()
  end

  defp decode_search_body(_body), do: {:error, :invalid_response}

  defp parse_detail(html) do
    %{
      name: extract(html, ~r/<b[^>]*>\s*([^<]+?)\s*<\/b>/),
      masked_license: extract_field(html, "License Number"),
      ownership: extract_field(html, "Ownership"),
      license_type: extract_field(html, "License Type"),
      county: extract_field(html, "County"),
      street: extract_field(html, "Street"),
      status: extract(html, ~r/Licence Status:\s*([A-Za-z]+)/),
      valid_till: extract(html, ~r/Valid Till:\s*([\d-]+)/)
    }
  end

  defp extract_field(html, label) do
    extract(html, ~r/#{Regex.escape(label)}\s*:\s*([^<]+?)\s*<\/a>/)
  end

  defp extract(html, regex) do
    case Regex.run(regex, html) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp ajax_url, do: base_url() <> "/ajax/public"
  defp base_url, do: Keyword.get(config(), :base_url, @default_base_url)

  defp search_req_options(name, ftype) do
    req_options(
      params: [
        fetch: "facilities",
        ftype: ftype || "",
        draw: 1,
        start: 0,
        length: 15,
        "search[value]": name,
        "search[regex]": false,
        "columns[0][data]": 0,
        "columns[0][name]": "",
        "columns[0][searchable]": true,
        "columns[0][orderable]": true,
        "columns[0][search][value]": "",
        "columns[0][search][regex]": false,
        "columns[1][data]": 1,
        "columns[1][name]": "",
        "columns[1][searchable]": true,
        "columns[1][orderable]": true,
        "columns[1][search][value]": "",
        "columns[1][search][regex]": false,
        "columns[2][data]": 2,
        "columns[2][name]": "",
        "columns[2][searchable]": true,
        "columns[2][orderable]": true,
        "columns[2][search][value]": "",
        "columns[2][search][regex]": false,
        "columns[3][data]": 3,
        "columns[3][name]": "",
        "columns[3][searchable]": true,
        "columns[3][orderable]": true,
        "columns[3][search][value]": "",
        "columns[3][search][regex]": false,
        "order[0][column]": 0,
        "order[0][dir]": "asc"
      ]
    )
  end

  defp detail_req_options(id) do
    req_options(params: [search_details: "facility", id: id])
  end

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
