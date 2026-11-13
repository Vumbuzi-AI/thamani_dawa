defmodule ThamaniDawa.Epcis.Event do
  @moduledoc """
  Builders for the EPCIS 2.0 JSON-LD events v1 submits to the PPB Hub
  (docs/PPB_TNT_INTEGRATION.md §5): distributor Receiving, Packing and
  Shipping. Builders are pure — they take plain maps and return
  `{:ok, event_map}` or `{:error, {field, reason}}`; persistence and
  submission live in `ThamaniDawa.Epcis.Outbox` / `SubmissionWorker`.

  Per the platform profile, JSON-LD events carry plain CBV tokens
  (`"receiving"`, `"in_transit"`, `"desadv"`) — never full CBV URNs.
  """

  alias ThamaniDawa.Epcis.Urn

  @time_zone_offset "+03:00"

  @error_reasons ~w(did_not_occur incorrect_data)

  @doc """
  Distributor inbound receiving (D1). The PPB Hub spec (§3.2.1/§3.3.1) lists
  `epcList` as mandatory for Receiving with no `quantityList` alternative
  (unlike Dispensing/Regulator Approval, which explicitly allow either) —
  so `ssccs` (the inbound case/pallet SSCCs) must be non-empty; there is no
  class-level fallback.
  """
  def receiving(args) do
    with {:ok, biz_location} <- sgln(args, :biz_location_gln),
         {:ok, source_party} <- sgln(args, :source_party_gln),
         {:ok, destination_party} <- sgln(args, :destination_party_gln),
         {:ok, epcs} <- sscc_urns(args),
         :ok <- require_content(epcs, []) do
      event = %{
        "type" => "ObjectEvent",
        "eventID" => event_id(args),
        "eventTime" => event_time(args),
        "eventTimeZoneOffset" => @time_zone_offset,
        "epcList" => epcs,
        "action" => "OBSERVE",
        "bizStep" => "receiving",
        "disposition" => "active",
        "readPoint" => %{"id" => biz_location},
        "bizLocation" => %{"id" => biz_location},
        "bizTransactionList" => [
          biz_transaction("recadv", args.org_prefix, args.grn_number)
        ],
        "sourceList" => [%{"type" => "owning_party", "source" => source_party}],
        "destinationList" => [
          %{"type" => "owning_party", "destination" => destination_party}
        ]
      }

      {:ok, event}
    end
  end

  @doc """
  Distributor packing (D2) — one AggregationEvent per shipper, emitted when
  the shipper's SSCC is assigned at approval.
  """
  def packing(args) do
    with {:ok, biz_location} <- sgln(args, :biz_location_gln),
         {:ok, parent} <- Urn.sscc(args.parent_sscc, String.length(args.org_prefix)),
         {:ok, children} <- child_sgtins(args) do
      {:ok,
       %{
         "type" => "AggregationEvent",
         "eventID" => event_id(args),
         "eventTime" => event_time(args),
         "eventTimeZoneOffset" => @time_zone_offset,
         "parentID" => parent,
         "childEPCs" => children,
         "action" => "ADD",
         "bizStep" => "packing",
         "disposition" => "active",
         "readPoint" => %{"id" => biz_location},
         "bizLocation" => %{"id" => biz_location}
       }}
    end
  end

  @doc """
  Distributor outbound shipping (D3). `ssccs` are the approved shipment's
  shipper SSCCs — child SGTINs must never appear here.
  """
  def shipping(args) do
    with {:ok, biz_location} <- sgln(args, :biz_location_gln),
         {:ok, destination} <- sgln(args, :destination_gln),
         {:ok, epcs} <- sscc_urns(args),
         :ok <- require_content(epcs, []) do
      {:ok,
       %{
         "type" => "ObjectEvent",
         "eventID" => event_id(args),
         "eventTime" => event_time(args),
         "eventTimeZoneOffset" => @time_zone_offset,
         "epcList" => epcs,
         "action" => "OBSERVE",
         "bizStep" => "shipping",
         "disposition" => "in_transit",
         "readPoint" => %{"id" => biz_location},
         "bizLocation" => %{"id" => biz_location},
         "bizTransactionList" => [
           biz_transaction("desadv", args.org_prefix, args.order_number)
         ],
         "sourceList" => [%{"type" => "owning_party", "source" => biz_location}],
         "destinationList" => [
           %{"type" => "owning_party", "destination" => destination},
           %{"type" => "location", "destination" => destination}
         ]
       }}
    end
  end

  @doc """
  Facility dispensing (F2) — synchronous-capable ObjectEvent for stock handed
  over a pharmacy counter (docs/PPB_TNT_INTEGRATION.md §5.2). `epcs` holds
  allocations with a known unit serial (one SGTIN per physically dispensed
  unit — only valid when exactly one unit was taken under that serial);
  `quantities` holds the class-level GTIN + lot + quantity remainder. At
  least one of the two must be non-empty; both together is a mixed dispense.
  Never SSCCs — only SGTINs are allowed in `epcList` at dispensing.
  """
  def dispensing(args) do
    with {:ok, biz_location} <- sgln(args, :biz_location_gln),
         {:ok, epcs} <- sgtin_urns(args, :epcs, :epc),
         {:ok, quantity_list} <- quantity_elements(args),
         :ok <- require_content(epcs, quantity_list) do
      event =
        %{
          "type" => "ObjectEvent",
          "eventID" => event_id(args),
          "eventTime" => event_time(args),
          "eventTimeZoneOffset" => @time_zone_offset,
          "action" => "OBSERVE",
          "bizStep" => "dispensing",
          "disposition" => "dispensed",
          "readPoint" => %{"id" => biz_location},
          "bizLocation" => %{"id" => biz_location}
        }
        |> put_if_present("epcList", epcs)
        |> put_if_present("quantityList", quantity_list)

      {:ok, event}
    end
  end

  defp event_id(%{event_id: uuid}), do: "urn:uuid:" <> uuid

  @doc """
  Builds the EPCIS 2.0 error-declaration form of an already-stored event
  (docs/PPB_TNT_INTEGRATION.md §7, manual test T7): the same payload — same
  `eventID`, same body — with an `errorDeclaration` injected. Since the Hub
  treats accepted events as immutable, re-declaring the same event with the
  declaration attached is the only legal same-eventID resubmission and the
  only way to void or correct something already stored.

  `args`:

    * `:declaration_time` — must be strictly after the payload's `eventTime`
    * `:reason` — a CBV error reason token, `"did_not_occur"` or
      `"incorrect_data"`
    * `:corrective_event_ids` — optional list of `urn:uuid:` references to
      the events that fix a declared-incorrect event; only included when
      non-empty
  """
  def error_declaration(payload, args) when is_map(payload) and is_map(args) do
    with {:ok, reason} <- error_reason(args),
         {:ok, declaration_time} <- declaration_time(args, payload),
         :ok <- require_event_id(payload) do
      declaration =
        %{"declarationTime" => iso8601(declaration_time), "reason" => reason}
        |> maybe_put_corrective_ids(args)

      {:ok, Map.put(payload, "errorDeclaration", declaration)}
    end
  end

  defp error_reason(%{reason: reason}) when reason in [:did_not_occur, :incorrect_data],
    do: {:ok, Atom.to_string(reason)}

  defp error_reason(%{reason: reason}) when reason in @error_reasons, do: {:ok, reason}

  defp error_reason(%{reason: _reason}), do: {:error, {:reason, :invalid}}

  defp declaration_time(%{declaration_time: %DateTime{} = time}, payload) do
    with {:ok, event_time, _offset} <- parse_event_time(payload),
         :ok <- check_declared_later(time, event_time) do
      {:ok, time}
    end
  end

  defp declaration_time(_args, _payload), do: {:error, {:declaration_time, :missing}}

  defp parse_event_time(%{"eventTime" => iso}) when is_binary(iso) do
    DateTime.from_iso8601(iso)
  end

  defp parse_event_time(_payload), do: {:error, {:event_time, :missing}}

  defp check_declared_later(declaration_time, event_time) do
    if DateTime.compare(declaration_time, event_time) == :gt do
      :ok
    else
      {:error, {:declaration_time, :not_after_event_time}}
    end
  end

  defp require_event_id(%{"eventID" => event_id}) when is_binary(event_id) and event_id != "",
    do: :ok

  defp require_event_id(_payload), do: {:error, {:event_id, :missing}}

  defp maybe_put_corrective_ids(declaration, %{corrective_event_ids: [_ | _] = ids}) do
    Map.put(declaration, "correctiveEventIDs", ids)
  end

  defp maybe_put_corrective_ids(declaration, _args), do: declaration

  defp iso8601(time) do
    time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp event_time(%{event_time: %DateTime{} = time}) do
    time
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp sgln(args, key) do
    case Map.fetch!(args, key) do
      gln when is_binary(gln) and gln != "" ->
        case Urn.sgln(gln, Urn.prefix_length_for(gln, args.org_prefix)) do
          {:ok, urn} -> {:ok, urn}
          {:error, reason} -> {:error, {key, reason}}
        end

      _missing ->
        {:error, {key, :missing}}
    end
  end

  defp sscc_urns(args) do
    args
    |> Map.get(:ssccs, [])
    |> map_while_ok(fn sscc ->
      case Urn.sscc(sscc, Urn.prefix_length_for(sscc, args.org_prefix)) do
        {:ok, urn} -> {:ok, urn}
        {:error, reason} -> {:error, {:sscc, sscc, reason}}
      end
    end)
  end

  defp child_sgtins(args), do: sgtin_urns(args, :children, :child)

  defp sgtin_urns(args, key, error_tag) do
    args
    |> Map.get(key, [])
    |> map_while_ok(fn %{gtin: gtin, serial: serial} ->
      case Urn.sgtin(gtin, serial, Urn.prefix_length_for(gtin, args.org_prefix)) do
        {:ok, urn} -> {:ok, urn}
        {:error, reason} -> {:error, {error_tag, gtin, reason}}
      end
    end)
  end

  defp quantity_elements(args) do
    args
    |> Map.get(:quantities, [])
    |> map_while_ok(fn %{gtin: gtin, lot: lot, quantity: quantity} = line ->
      case Urn.lgtin(gtin, lot, Urn.prefix_length_for(gtin, args.org_prefix)) do
        {:ok, urn} ->
          {:ok,
           %{
             "epcClass" => urn,
             "quantity" => quantity,
             "uom" => Map.get(line, :uom, "EA")
           }}

        {:error, reason} ->
          {:error, {:quantity, gtin, reason}}
      end
    end)
  end

  defp require_content([], []), do: {:error, :empty_event}
  defp require_content(_epcs, _quantities), do: :ok

  defp put_if_present(event, _key, []), do: event
  defp put_if_present(event, key, value), do: Map.put(event, key, value)

  defp biz_transaction(type, org_prefix, reference) do
    %{
      "type" => type,
      "bizTransaction" => "urn:epcglobal:cbv:bt:#{org_prefix}:#{reference}"
    }
  end

  defp map_while_ok(items, fun) do
    result =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case fun.(item) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
