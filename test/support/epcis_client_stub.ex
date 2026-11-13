defmodule ThamaniDawa.EpcisClientStub do
  @moduledoc """
  Test double for `ThamaniDawa.Epcis.Client.submit_document/1`. The test
  process queues responses with `expect/1`; each submission consumes one and
  records the submitted document so assertions can inspect order and content.
  """

  @behaviour ThamaniDawa.Epcis.Client

  def expect(responses) when is_list(responses) do
    Process.put({__MODULE__, :responses}, responses)
    Process.put({__MODULE__, :documents}, [])
  end

  def submitted_documents do
    {__MODULE__, :documents}
    |> Process.get([])
    |> Enum.reverse()
  end

  @impl true
  def submit_document(document) do
    Process.put({__MODULE__, :documents}, [document | Process.get({__MODULE__, :documents}, [])])

    case Process.get({__MODULE__, :responses}, []) do
      [response | rest] ->
        Process.put({__MODULE__, :responses}, rest)
        response

      [] ->
        {:ok, 202, %{"status" => "ACCEPTED"}}
    end
  end
end
