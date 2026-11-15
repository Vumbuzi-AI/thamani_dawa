defmodule ThamaniDawa.RegistryCacheTest do
  use ExUnit.Case, async: false

  alias ThamaniDawa.RegistryCache

  setup do
    original = Application.get_env(:thamani_dawa, RegistryCache, [])
    Application.put_env(:thamani_dawa, RegistryCache, enabled: true)
    on_exit(fn -> Application.put_env(:thamani_dawa, RegistryCache, original) end)
  end

  test "caches a cacheable result and does not call fun again for the same key" do
    key = {:test, System.unique_integer()}
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(agent, &(&1 + 1))
      {:ok, :verified, %{}}
    end

    assert {:ok, :verified, %{}} = RegistryCache.fetch(key, fun)
    assert {:ok, :verified, %{}} = RegistryCache.fetch(key, fun)
    assert Agent.get(agent, & &1) == 1
  end

  test "does not cache a result the cacheable? predicate rejects" do
    key = {:test, System.unique_integer()}
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(agent, &(&1 + 1))
      {:error, :timeout}
    end

    cacheable? = fn _result -> false end

    assert {:error, :timeout} = RegistryCache.fetch(key, fun, cacheable?)
    assert {:error, :timeout} = RegistryCache.fetch(key, fun, cacheable?)
    assert Agent.get(agent, & &1) == 2
  end

  test "different keys are cached independently" do
    assert {:ok, :verified} =
             RegistryCache.fetch({:test, :a, System.unique_integer()}, fn -> {:ok, :verified} end)

    assert {:ok, :not_verified} =
             RegistryCache.fetch({:test, :b, System.unique_integer()}, fn ->
               {:ok, :not_verified}
             end)
  end

  test "bypasses the cache entirely when disabled" do
    Application.put_env(:thamani_dawa, RegistryCache, enabled: false)
    key = {:test, System.unique_integer()}
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fun = fn ->
      Agent.update(agent, &(&1 + 1))
      {:ok, :verified}
    end

    RegistryCache.fetch(key, fun)
    RegistryCache.fetch(key, fun)
    assert Agent.get(agent, & &1) == 2
  end
end
