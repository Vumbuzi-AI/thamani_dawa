defmodule ThamaniDawa.EpcisClientStub do
  @moduledoc """
  Test double for `ThamaniDawa.Epcis.Client.submit_document/3`. The test
  process queues responses with `expect/1`; each submission consumes one and
  records the submitted document, tier, and any org-specific API key
  override so assertions can inspect order and content.
  """

  @behaviour ThamaniDawa.Epcis.Client

  def expect(responses) when is_list(responses) do
    Process.put({__MODULE__, :responses}, responses)
    Process.put({__MODULE__, :documents}, [])
    Process.put({__MODULE__, :tiers}, [])
    Process.put({__MODULE__, :api_key_overrides}, [])
  end

  def submitted_documents do
    {__MODULE__, :documents}
    |> Process.get([])
    |> Enum.reverse()
  end

  def submitted_tiers do
    {__MODULE__, :tiers}
    |> Process.get([])
    |> Enum.reverse()
  end

  def submitted_api_key_overrides do
    {__MODULE__, :api_key_overrides}
    |> Process.get([])
    |> Enum.reverse()
  end

  @impl true
  def submit_document(document, tier, api_key_override) do
    Process.put({__MODULE__, :documents}, [document | Process.get({__MODULE__, :documents}, [])])
    Process.put({__MODULE__, :tiers}, [tier | Process.get({__MODULE__, :tiers}, [])])

    Process.put(
      {__MODULE__, :api_key_overrides},
      [api_key_override | Process.get({__MODULE__, :api_key_overrides}, [])]
    )

    case Process.get({__MODULE__, :responses}, []) do
      [response | rest] ->
        Process.put({__MODULE__, :responses}, rest)
        response

      [] ->
        {:ok, 202, %{"status" => "ACCEPTED"}}
    end
  end
end
