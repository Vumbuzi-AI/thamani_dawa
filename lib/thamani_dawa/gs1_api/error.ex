defmodule ThamaniDawa.Gs1Api.Error do
  @moduledoc """
  A failed GS1 (`gs1_admin`) API call.

  The GS1 API answers non-2xx with `{"result": "<human message>"}`, and that
  copy has already been through member support — see serialisation.md §7
  ("keep the existing copy"). So the `:message` is passed through verbatim for
  display, while `:reason` is the machine-readable classification callers
  should branch on. `:fallback_message` is only used when the API gave us
  nothing to show (a timeout, or an unparseable body).
  """

  @type reason ::
          :missing_params
          | :unauthorized
          | :forbidden
          | :not_found
          | :no_prefix
          | :unprocessable
          | :provider_error
          | :timeout
          | :not_configured
          | :unexpected_response

  @type t :: %__MODULE__{
          reason: reason(),
          message: String.t(),
          status: pos_integer() | nil,
          body: term()
        }

  defexception [:reason, :message, :status, :body]

  @doc """
  Builds an error from an HTTP status and decoded body.

  422 is split from the other 4xx codes because it is the "member has no GS1
  company prefix" case (§4.1), which the UI guards against up front (§2.4.1) —
  seeing it here means the local guard and GS1 disagree.
  """
  @spec from_response(pos_integer(), term()) :: t()
  def from_response(status, body) do
    %__MODULE__{
      reason: reason_for_status(status),
      message: message_from_body(body) || fallback_message(reason_for_status(status)),
      status: status,
      body: body
    }
  end

  @spec transport(term()) :: t()
  def transport(reason) do
    %__MODULE__{
      reason: :timeout,
      message: fallback_message(:timeout),
      status: nil,
      body: reason
    }
  end

  @spec not_configured() :: t()
  def not_configured do
    %__MODULE__{
      reason: :not_configured,
      message: fallback_message(:not_configured),
      status: nil,
      body: nil
    }
  end

  @doc """
  A 2xx whose body carried no identifier.

  Treated as a failure rather than a partial success: the call may well have
  minted a code on the GS1 side, so it needs the same operator-visible
  reconciliation as a stranded `pending` request (§4.5).
  """
  @spec unexpected_response() :: t()
  def unexpected_response do
    %__MODULE__{
      reason: :unexpected_response,
      message: fallback_message(:unexpected_response),
      status: nil,
      body: nil
    }
  end

  defp reason_for_status(400), do: :missing_params
  defp reason_for_status(401), do: :unauthorized
  defp reason_for_status(403), do: :forbidden
  defp reason_for_status(404), do: :not_found
  defp reason_for_status(422), do: :no_prefix
  defp reason_for_status(status) when status in 400..499, do: :unprocessable
  defp reason_for_status(_status), do: :provider_error

  defp message_from_body(%{"result" => result}) when is_binary(result) and result != "",
    do: result

  defp message_from_body(%{"message" => message}) when is_binary(message) and message != "",
    do: message

  defp message_from_body(_body), do: nil

  defp fallback_message(:timeout), do: "Couldn't reach the GS1 service. Please try again."
  defp fallback_message(:unauthorized), do: "This organization isn't authorized with GS1."
  defp fallback_message(:forbidden), do: "This organization isn't licensed for this GS1 standard."
  defp fallback_message(:not_found), do: "GS1 has no record for this organization."
  defp fallback_message(:no_prefix), do: "No GS1 company prefix is configured for this organization."
  defp fallback_message(:missing_params), do: "The request to GS1 was missing required details."

  defp fallback_message(:not_configured),
    do: "The GS1 connection isn't configured on this deployment."

  defp fallback_message(:unexpected_response),
    do:
      "GS1 accepted the request but didn't return a code. Check with GS1 before generating again."

  defp fallback_message(_reason), do: "The GS1 service returned an unexpected error."
end
