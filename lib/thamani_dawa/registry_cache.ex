defmodule ThamaniDawa.RegistryCache do
  @moduledoc """
  Short-lived cache for external registry lookups (GS1 GRP, PPB facilities
  register) — mirrors `ThamaniDawa.LoginRateLimiter`'s shape (a plain map in
  GenServer state, no ETS or external dependency).

  This exists to absorb near-duplicate lookups for the same identifier in
  quick succession: a user correcting a typo and re-triggering the debounced
  check, and the background verification workers (`Grp.PrefixVerificationWorker`,
  `Grp.GlnVerificationWorker`, `Ppb.VerificationWorker`) re-checking the same
  identifier moments after the live signup check already resolved it.
  Licences are typically renewed annually, so a short TTL here carries
  negligible risk of ever serving a stale answer.

  Only definitive answers are cached — transient failures (`:provider_error`,
  `:timeout`, `:unauthorized`) are never cached, so an outage doesn't get
  "remembered" past its actual duration. Disable entirely via
  `config :thamani_dawa, #{inspect(__MODULE__)}, enabled: false` (set in
  `config/test.exs`, so the test suite's per-test registry stubs are never
  shadowed by a result cached from a different test).
  """

  use GenServer

  @ttl_ms :timer.minutes(10)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Returns the cached value for `key` if present and still fresh; otherwise
  calls `fun.()`, caches the result if `cacheable?.(result)` is true, and
  returns it. Caching is skipped entirely when disabled via config.
  """
  def fetch(key, fun, cacheable? \\ &default_cacheable?/1)
      when is_function(fun, 0) and is_function(cacheable?, 1) do
    if enabled?() do
      case get(key) do
        {:ok, value} ->
          value

        :miss ->
          value = fun.()
          if cacheable?.(value), do: put(key, value)
          value
      end
    else
      fun.()
    end
  end

  # The cache is a convenience, not a dependency a registry lookup should
  # ever fail because of — if the GenServer is momentarily unavailable
  # (e.g. a deploy rollover), treat it as a cache miss rather than crashing
  # the caller.
  defp get(key) do
    GenServer.call(__MODULE__, {:get, key})
  catch
    :exit, _reason -> :miss
  end

  defp put(key, value) do
    GenServer.cast(__MODULE__, {:put, key, value})
  catch
    :exit, _reason -> :ok
  end

  @doc false
  def default_cacheable?({:ok, _}), do: true
  def default_cacheable?({:ok, _, _}), do: true
  def default_cacheable?(_result), do: false

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:get, key}, _from, state) do
    state = prune(state)

    case Map.fetch(state, key) do
      {:ok, {value, _inserted_at}} -> {:reply, {:ok, value}, state}
      :error -> {:reply, :miss, state}
    end
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, Map.put(state, key, {value, System.monotonic_time(:millisecond)})}
  end

  defp prune(state) do
    now = System.monotonic_time(:millisecond)

    state
    |> Enum.filter(fn {_key, {_value, inserted_at}} -> now - inserted_at < @ttl_ms end)
    |> Map.new()
  end

  defp enabled?, do: Application.get_env(:thamani_dawa, __MODULE__, [])[:enabled] != false
end
