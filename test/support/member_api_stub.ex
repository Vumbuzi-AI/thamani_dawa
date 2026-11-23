defmodule ThamaniDawa.GS1.MemberApiStub do
  @moduledoc """
  Test double for `ThamaniDawa.GS1.MemberApi`.

  `create_sscc` mints a unique, check-digit-valid SSCC without touching the
  network. `sscc_contents` returns whatever `put_contents/2` stored for that
  SSCC, or `:not_found`. A failure queued with `fail_next/1` applies only to
  the calling process, so one test can force an error without affecting
  others.
  """

  @behaviour ThamaniDawa.GS1.MemberApi

  use Agent

  @default_prefixes ["6160001"]

  @default_glns [
    %{
      "gln" => "0614141000784",
      "description" => "Test Licensee",
      "address" => "Nairobi, Kenya",
      "location" => "Nairobi",
      "status" => "active",
      "company" => "Afya Test Org"
    },
    %{
      "gln" => "0614141000456",
      "description" => "Test Licensee Annex",
      "address" => "Mombasa, Kenya",
      "location" => "Mombasa",
      "status" => "active",
      "company" => "Afya Test Org"
    }
  ]

  def start_link(_opts \\ []) do
    Agent.start_link(&default_state/0, name: __MODULE__)
  end

  def reset do
    ensure_started()
    Agent.update(__MODULE__, fn _state -> default_state() end)
  end

  def put_prefixes(prefixes) when is_list(prefixes) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :prefixes, prefixes))
  end

  def put_glns(glns) when is_list(glns) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :glns, glns))
  end

  def fail_next(reason) do
    Process.put({__MODULE__, :fail}, reason)
    :ok
  end

  def create_requests do
    {__MODULE__, :creates}
    |> Process.get([])
    |> Enum.reverse()
  end

  def shipper_sscc_requests do
    ensure_started()
    Agent.get(__MODULE__, fn state -> Enum.reverse(state.shipper_sscc_creates) end)
  end

  def serial_requests do
    ensure_started()
    Agent.get(__MODULE__, fn state -> Enum.reverse(state.serial_creates) end)
  end

  def put_contents(sscc, products) when is_binary(sscc) and is_list(products) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      put_in(state, [:contents, sscc], products)
    end)
  end

  def requested_contents do
    ensure_started()
    Agent.get(__MODULE__, fn state -> Enum.reverse(state.lookups) end)
  end

  @doc "Sets what `list_products/2` returns next, in the live client's normalized shape."
  def put_products(products) when is_list(products) do
    ensure_started()
    Agent.update(__MODULE__, &Map.put(&1, :products, products))
  end

  @impl true
  def post_create_sscc(params) when is_map(params) do
    Process.put({__MODULE__, :creates}, [params | Process.get({__MODULE__, :creates}, [])])

    case Process.delete({__MODULE__, :fail}) do
      nil -> {:ok, mint_sscc()}
      reason -> {:error, reason}
    end
  end

  @impl true
  def post_create_shipper_sscc(params) when is_map(params) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | shipper_sscc_creates: [params | state.shipper_sscc_creates]}
    end)

    case Process.delete({__MODULE__, :fail}) do
      nil -> {:ok, mint_sscc()}
      reason -> {:error, reason}
    end
  end

  @impl true
  def post_sscc_contents(sscc) when is_binary(sscc) do
    ensure_started()

    Agent.get_and_update(__MODULE__, fn state ->
      state = %{state | lookups: [sscc | state.lookups]}

      result =
        case state.contents[sscc] do
          nil -> {:error, :not_found}
          products -> {:ok, %{"result" => "success", "sscc" => sscc, "products" => products}}
        end

      {result, state}
    end)
  end

  @impl true
  def post_create_serials(params) when is_map(params) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | serial_creates: [params | state.serial_creates]}
    end)

    case Process.delete({__MODULE__, :fail}) do
      nil -> {:ok, build_serialisation(params)}
      reason -> {:error, reason}
    end
  end

  # Batches and serials are derived from the `create_serialised_datamatrix`
  # calls this stub has seen, so anything generated in a test reads back.
  @impl true
  def post_barcode_batches(gtin) when is_binary(gtin) do
    ensure_started()

    rows =
      for params <- created_for(gtin),
          serial <- created_serials(params) do
        %{
          "barcode" => gtin,
          "batch" => params["batch"],
          "production" => params["production"],
          "expiry" => params["expiry"],
          "serial" => serial
        }
      end

    {:ok, rows}
  end

  @impl true
  def post_batch_serials(gtin, batch) when is_binary(gtin) and is_binary(batch) do
    ensure_started()

    results =
      for params <- created_for(gtin),
          params["batch"] == batch,
          serial <- created_serials(params) do
        %{
          "serial" => serial,
          "payload" => "https://gs1.ke/01/#{gtin}/21/#{serial}",
          "human_readable" => "(01)#{gtin} (10)#{batch} (21)#{serial}",
          "exists" => true
        }
      end

    {:ok, results}
  end

  # Unpacked = generated without shippers and not yet in a later
  # `create_shipper_sscc` call.
  @impl true
  def post_unpacked_serials(gtin, batch) when is_binary(gtin) do
    ensure_started()

    packed =
      __MODULE__
      |> Agent.get(& &1.shipper_sscc_creates)
      |> Enum.filter(&(&1["barcode"] == gtin))
      |> Enum.flat_map(&List.wrap(&1["serials"]))
      |> MapSet.new()

    serials =
      for params <- created_for(gtin),
          !Map.get(params, "create_shippers"),
          is_nil(batch) or params["batch"] == batch,
          serial <- created_serials(params),
          not MapSet.member?(packed, serial) do
        %{
          "serial" => serial,
          "batch" => params["batch"],
          "production" => params["production"],
          "expiry" => params["expiry"]
        }
      end

    {:ok, serials}
  end

  defp created_for(gtin) do
    __MODULE__
    |> Agent.get(& &1.serial_creates)
    |> Enum.reverse()
    |> Enum.filter(&(&1["barcode"] == gtin))
  end

  defp created_serials(params) do
    # Mirrors the serials `build_serialisation/1` hands back.
    for n <- 1..Map.get(params, "trade_item_qty", 1),
        do: n |> Integer.to_string() |> String.pad_leading(4, "0")
  end

  @impl true
  def post_list_products(_params) do
    ensure_started()
    {:ok, Agent.get(__MODULE__, & &1.products)}
  end

  @impl true
  def post_get_company_prefixes(_params) do
    ensure_started()
    {:ok, Agent.get(__MODULE__, & &1.prefixes)}
  end

  @impl true
  def post_list_glns(_params) do
    ensure_started()
    {:ok, Agent.get(__MODULE__, & &1.glns)}
  end

  @impl true
  def post_search_glns(%{"query" => query}) do
    ensure_started()
    term = query |> String.trim() |> String.downcase()

    glns =
      Agent.get(__MODULE__, & &1.glns)
      |> Enum.filter(fn gln ->
        Enum.any?(["gln", "description", "address", "location", "company"], fn field ->
          gln
          |> Map.get(field, "")
          |> to_string()
          |> String.downcase()
          |> String.contains?(term)
        end)
      end)

    {:ok, glns}
  end

  defp default_state do
    %{
      next: 1,
      contents: %{},
      lookups: [],
      products: [],
      serial_creates: [],
      shipper_sscc_creates: [],
      prefixes: @default_prefixes,
      glns: @default_glns
    }
  end

  defp build_serialisation(params) do
    quantity = Map.get(params, "trade_item_qty", 1)

    primary_datamatrices =
      for n <- 1..quantity do
        serial = n |> Integer.to_string() |> String.pad_leading(4, "0")

        %{
          "serial" => serial,
          "payload" => "https://gs1.ke/01/#{params["barcode"]}/21/#{serial}",
          "human_readable" => "(01)#{params["barcode"]} (21)#{serial}"
        }
      end

    shippers =
      if Map.get(params, "create_shippers") do
        shipper_quantity = Map.fetch!(params, "shipper_qty")

        primary_datamatrices
        |> Enum.map(& &1["serial"])
        |> Enum.chunk_every(shipper_quantity)
        |> Enum.with_index(1)
        |> Enum.map(fn {primary_serials, index} ->
          %{
            "sscc" => mint_sscc(),
            "serial" => "shipper-#{index}",
            "primary_serials" => primary_serials
          }
        end)
      else
        []
      end

    %{
      "result" => "success",
      "gtin" => params["barcode"],
      "batch" => params["batch"],
      "production_date" => params["production"],
      "expiry_date" => params["expiry"],
      "primary_count" => quantity,
      "primary_datamatrices" => primary_datamatrices,
      "shippers" => shippers
    }
  end

  defp mint_sscc do
    ensure_started()

    serial =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.next, %{state | next: state.next + 1}}
      end)

    body = "06160000" <> (serial |> Integer.to_string() |> String.pad_leading(9, "0"))
    body <> Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(body))
  end

  defp ensure_started do
    case start_link() do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
end
