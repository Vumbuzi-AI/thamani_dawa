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

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{next: 1, contents: %{}, lookups: []} end, name: __MODULE__)
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

  @impl true
  def post_create_sscc(params) when is_map(params) do
    Process.put({__MODULE__, :creates}, [params | Process.get({__MODULE__, :creates}, [])])

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
