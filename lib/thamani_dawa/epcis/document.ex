defmodule ThamaniDawa.Epcis.Document do
  @moduledoc """
  Wraps EPCIS event maps into an EPCIS 2.0 JSON-LD capture document. The
  submission worker sends one event per document, so chronological order is
  enforced by submission order rather than within the envelope.
  """

  @context "https://ref.gs1.org/standards/epcis/epcis-context.jsonld"

  def wrap(events, creation_date \\ DateTime.utc_now())

  def wrap(events, %DateTime{} = creation_date) when is_list(events) do
    %{
      "@context" => [@context],
      "type" => "EPCISDocument",
      "schemaVersion" => "2.0",
      "creationDate" => creation_date |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "epcisBody" => %{"eventList" => events}
    }
  end

  def wrap(%{} = event, creation_date), do: wrap([event], creation_date)
end
