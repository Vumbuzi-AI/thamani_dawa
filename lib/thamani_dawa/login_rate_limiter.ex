defmodule ThamaniDawa.LoginRateLimiter do
  @moduledoc false

  use GenServer

  @window_ms :timer.minutes(15)
  @max_attempts 20

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Allows a login attempt only while every supplied key is below the limit."
  def allow?(keys) when is_list(keys), do: GenServer.call(__MODULE__, {:allow, keys})

  @doc "Clears counters after a successful login."
  def reset(keys) when is_list(keys), do: GenServer.cast(__MODULE__, {:reset, keys})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:allow, keys}, _from, state) do
    now = System.monotonic_time(:millisecond)
    state = prune(state, now)

    if Enum.any?(keys, fn key -> length(Map.get(state, key, [])) >= @max_attempts end) do
      {:reply, {:error, :rate_limited}, state}
    else
      state =
        Enum.reduce(keys, state, &Map.update(&2, &1, [now], fn attempts -> [now | attempts] end))

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:reset, keys}, state), do: {:noreply, Map.drop(state, keys)}

  defp prune(state, now) do
    Enum.reduce(state, %{}, fn {key, attempts}, acc ->
      attempts = Enum.filter(attempts, &(now - &1 < @window_ms))
      if attempts == [], do: acc, else: Map.put(acc, key, attempts)
    end)
  end
end
