defmodule ThamaniDawa.Gs1RegistryStub do
  @moduledoc """
  Stands in for the GS1 Global Registry Platform licences API during tests.

  `ThamaniDawa.Grp` posts a JSON array holding the identifier to look up and
  expects a JSON array of licence records back. This stub answers with one
  licence for every identifier it is asked about, except for the identifiers
  listed under the `:unknown_identifiers` key of the
  `:thamani_dawa` application environment — those come back as an empty list,
  which is how the registry answers for an identifier it does not know.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    licences = conn |> identifiers() |> Enum.flat_map(&licences_for/1)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(licences))
  end

  defp identifiers(conn) do
    case conn.body_params do
      %{"_json" => identifiers} when is_list(identifiers) ->
        Enum.map(identifiers, &to_string/1)

      params when is_map(params) ->
        params
        |> Map.values()
        |> Enum.flat_map(&List.wrap/1)
        |> Enum.map(&to_string/1)

      _ ->
        []
    end
  end

  defp licences_for(identifier) do
    if unknown?(identifier) do
      []
    else
      [%{"licenseeName" => "Test Licensee", "licenseeGLN" => identifier}]
    end
  end

  # Identifiers starting with a run of zeros stand for identifiers the
  # registry has never heard of; tests use them to exercise the
  # "not registered" paths.
  defp unknown?(identifier) do
    String.starts_with?(identifier, "000") or identifier in unknown_identifiers()
  end

  defp unknown_identifiers do
    Application.get_env(:thamani_dawa, :gs1_unknown_identifiers, [])
  end
end
