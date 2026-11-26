defmodule ThamaniDawa.Manufacturing.PalletLine do
  @moduledoc false

  import Ecto.Query

  require Logger

  alias ThamaniDawa.Manufacturing.AggregationSession
  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawa.Repo

  @open_stages ~w(scanning awaiting_sscc awaiting_label_verification)

  def current(organization_id) do
    case find_open(organization_id) do
      %AggregationSession{id: id} -> {:ok, payload(organization_id, id)}
      nil -> {:ok, nil}
    end
  end

  def open(organization_id) do
    result =
      case find_open(organization_id) do
        %AggregationSession{id: id} ->
          {:ok, payload(organization_id, id)}

        nil ->
          case Operations.start_pallet_session(organization_id, nil) do
            {:ok, session} -> {:ok, payload(organization_id, session.id)}
            {:error, :active_session_exists} -> resume(organization_id)
            other -> other
          end
      end

    Logger.info("pallet-line open org=#{organization_id} #{note(result)}")
    result
  end

  def get(organization_id, id) do
    with {:ok, id} <- parse_id(id),
         %AggregationSession{} <- Operations.get_session(organization_id, id) do
      {:ok, payload(organization_id, id)}
    else
      nil -> {:error, :pallet_not_found}
      other -> other
    end
  end

  def scan(organization_id, id, raw) do
    with {:ok, id} <- parse_id(id),
         {:ok, _} <- Operations.capture_shipper_scan(organization_id, id, raw) do
      {:ok, payload(organization_id, id)}
    end
  end

  def mint(organization_id, id, order_number \\ nil) do
    result =
      with {:ok, id} <- parse_id(id),
           :ok <- finish_if_scanning(organization_id, id),
           {:ok, _} <- allocate(organization_id, id, order_number) do
        {:ok, payload(organization_id, id)}
      end

    Logger.info("pallet-line mint org=#{organization_id} id=#{id} #{note(result)}")
    result
  end

  def verify(organization_id, id, raw) do
    with {:ok, id} <- parse_id(id),
         {:ok, _} <- Operations.verify_pallet_parent(organization_id, id, raw) do
      {:ok, payload(organization_id, id)}
    end
  end

  defp resume(organization_id) do
    case find_open(organization_id) do
      %AggregationSession{id: id} -> {:ok, payload(organization_id, id)}
      nil -> {:error, :active_session_exists}
    end
  end

  defp finish_if_scanning(organization_id, id) do
    case Operations.get_session(organization_id, id) do
      %{status: "scanning"} ->
        case Operations.finish_pallet_loading(organization_id, id) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      %{status: "awaiting_sscc"} ->
        :ok

      nil ->
        {:error, :pallet_not_found}

      _ ->
        {:error, :not_actionable}
    end
  end

  defp allocate(organization_id, id, order_number) do
    case Operations.allocate_pallet_sscc(organization_id, id, order_number) do
      {:ok, pallet} ->
        {:ok, pallet}

      {:error, {:invalid, message}} ->
        Logger.warning(
          "pallet-line mint org=#{organization_id} id=#{id} gs1=#{inspect(message)}"
        )

        reopen_scanning(organization_id, id)
        {:error, {:invalid, message}}

      other ->
        other
    end
  end

  defp reopen_scanning(organization_id, id) do
    Repo.update_all(
      from(s in AggregationSession,
        where:
          s.id == ^id and s.organization_id == ^organization_id and s.status == "awaiting_sscc" and
            is_nil(s.manufacturer_pallet_id)
      ),
      set: [status: "scanning", finished_loading_at: nil]
    )
  end

  defp find_open(organization_id) do
    Repo.one(
      from s in AggregationSession,
        where:
          s.organization_id == ^organization_id and s.session_type == "pallet" and
            s.status in ^@open_stages,
        order_by: [desc: s.id],
        limit: 1
    )
  end

  defp payload(organization_id, id) do
    session = Operations.get_session(organization_id, id)
    pallet = session.pallet
    party = pallet || first_shipper(session)

    %{
      id: to_string(session.id),
      stage: session.status,
      sscc: pallet && pallet.code,
      from_name: field(party, :from_company_name),
      from_gln: field(party, :from_gln),
      to_name: field(party, :to_company_name),
      to_gln: field(party, :to_gln),
      order_number: order_number(session),
      shippers: shipper_rows(session)
    }
  end

  defp order_number(session) do
    Enum.find_value(session.items, fn item ->
      case item.shipper_sscc do
        %{order_number: number} when is_binary(number) and number != "" -> number
        _ -> nil
      end
    end)
  end

  defp first_shipper(session) do
    Enum.find_value(session.items, fn item -> item.shipper_sscc end)
  end

  defp shipper_rows(session) do
    Enum.flat_map(session.items, fn item ->
      case item.shipper_sscc do
        %{code: code} = shipper when is_binary(code) ->
          [%{sscc: code, to_name: shipper.to_company_name, to_gln: shipper.to_gln}]

        _ ->
          []
      end
    end)
  end

  defp note({:ok, %{id: id, stage: stage, shippers: shippers, sscc: sscc}}) do
    "id=#{id} stage=#{stage} shippers=#{length(shippers)} sscc=#{sscc || "none"}"
  end

  defp note({:error, reason}), do: "failed #{inspect(reason)}"
  defp note(other), do: "failed #{inspect(other)}"

  defp field(nil, _key), do: nil
  defp field(party, key), do: Map.get(party, key)

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :pallet_not_found}
    end
  end

  defp parse_id(_id), do: {:error, :pallet_not_found}
end
