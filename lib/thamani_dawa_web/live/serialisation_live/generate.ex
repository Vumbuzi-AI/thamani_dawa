defmodule ThamaniDawaWeb.SerialisationLive.Generate do
  @moduledoc """
  The two generation flows of ui.md §11, entered from `+ SSCC` and `+ Serial`
  on the product list: one form module, two shapes, chosen by `live_action`.

  The submit runs in `start_async` so the LiveView stays responsive while GS1
  works (a serialised run of a hundred thousand serials is slow), and the
  button is disabled for the duration — a second submit would mint a second set
  of codes. A call that times out is *not* retried: the shipment it already
  wrote stays `:submitted` and the member is told to reconcile rather than
  generate again (§4.5, ui.md §11.7).

  Entering the flow is where allowance and configuration problems surface; GS1
  remains the only enforcer, so nothing is blocked locally beyond obviously
  incomplete input (§6).
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Gs1Api.Error
  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.Serialisation
  alias ThamaniDawa.Serialisation.SerialisedRequest
  alias ThamaniDawa.Serialisation.SsccRequest

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    item = SerialCatalog.get_item_by_gtin(organization_id, gtin)

    {:ok,
     socket
     |> assign(:gtin, gtin)
     |> assign(:item, item)
     |> assign(:submitting, false)
     |> assign(:pending, false)
     |> assign(:error, nil)
     |> assign_form(%{"gtin" => gtin})}
  end

  defp module(:sscc), do: SsccRequest
  defp module(:serialised), do: SerialisedRequest

  defp assign_form(socket, params) do
    module = module(socket.assigns.live_action)
    changeset = module.changeset(struct(module), params)

    socket
    |> assign(:params, params)
    |> assign(:form, to_form(changeset, as: :request))
  end

  def handle_event("validate", %{"request" => params}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign_form(params)}
  end

  def handle_event("submit", %{"request" => params}, socket) do
    module = module(socket.assigns.live_action)
    changeset = module.changeset(struct(module), params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, request} ->
        scope = socket.assigns.current_scope
        action = socket.assigns.live_action

        {:noreply,
         socket
         |> assign(:submitting, true)
         |> assign(:error, nil)
         |> assign(:params, params)
         |> start_async(:generate, fn -> generate(scope, action, request) end)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:params, params)
         |> assign(:form, to_form(changeset, as: :request))}
    end
  end

  defp generate(scope, :sscc, request), do: Serialisation.generate_sscc(scope, request)
  defp generate(scope, :serialised, request), do: Serialisation.generate_serialised(scope, request)

  def handle_async(:generate, {:ok, {:ok, _shipment, sscc}}, socket) do
    {:noreply,
     socket
     |> assign(:submitting, false)
     |> put_flash(:info, success_message(socket.assigns.live_action, sscc))
     |> push_navigate(to: results_path(socket.assigns))}
  end

  def handle_async(:generate, {:ok, {:error, %Error{reason: :timeout} = error}}, socket) do
    {:noreply,
     socket
     |> assign(:submitting, false)
     |> assign(:pending, true)
     |> assign(:error, error.message)}
  end

  def handle_async(:generate, {:ok, {:error, %Error{} = error}}, socket) do
    {:noreply, socket |> assign(:submitting, false) |> assign(:error, error.message)}
  end

  def handle_async(:generate, {:ok, {:error, %Ecto.Changeset{} = changeset}}, socket) do
    {:noreply,
     socket
     |> assign(:submitting, false)
     |> assign(:form, to_form(changeset, as: :request))
     |> assign(:error, "Those details could not be saved. Check the form and try again.")}
  end

  def handle_async(:generate, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:submitting, false) |> assign(:error, error_text(reason))}
  end

  # The process died mid-call, so whether GS1 issued anything is unknown. That
  # is the reconciliation case, not a retry case.
  def handle_async(:generate, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:submitting, false)
     |> assign(:pending, true)
     |> assign(
       :error,
       "We lost contact while GS1 was generating. Codes may still have been issued — " <>
         "check the results for this GTIN before generating again."
     )}
  end

  defp error_text(:invalid_gtin),
    do: "This GTIN can't be sent to GS1 — it must have a 13-digit form."

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(_reason), do: "Generation failed. Please try again."

  defp success_message(:sscc, sscc), do: "GS1 issued SSCC #{sscc.code}."

  defp success_message(:serialised, sscc),
    do: "GS1 issued the serials for pallet SSCC #{sscc.code}."

  defp results_path(%{live_action: :sscc, gtin: gtin}),
    do: ~p"/org/serialisation/#{gtin}/batches"

  defp results_path(%{live_action: :serialised, gtin: gtin}),
    do: ~p"/org/serialisation/#{gtin}/groups"

  defp product_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp product_name(_item), do: nil

  defp authorized_serials(params) do
    trade = integer_or_nil(params["trade_item_qty"])
    shipper = integer_or_nil(params["shipper_qty"])

    if trade && shipper && shipper > 0 do
      trade + trunc(trade / shipper)
    end
  end

  defp integer_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} when parsed > 0 -> parsed
      _other -> nil
    end
  end

  defp integer_or_nil(_value), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/serialisation"}
    >
      <.header icon={if @live_action == :sscc, do: "hero-archive-box", else: "hero-qr-code"} back={~p"/org/serialisation"}>
        {if @live_action == :sscc, do: "Generate an SSCC", else: "Generate serialised codes"}
        <:subtitle>
          {product_name(@item) || "GTIN"} · every code on this run is issued by GS1.
        </:subtitle>
        <:actions>
          <span class="inline-flex items-center rounded-full bg-indigo-50 px-3 py-1.5 font-mono text-sm font-semibold text-thamani-forest">
            GTIN {@gtin}
          </span>
        </:actions>
      </.header>

      <div
        :if={@error}
        class={[
          "mb-5 rounded-xl border p-4 text-sm",
          @pending && "border-amber-200 bg-amber-50 text-amber-900",
          !@pending && "border-rose-200 bg-rose-50 text-rose-900"
        ]}
        role="alert"
      >
        <p class="font-semibold">
          {if @pending, do: "This run needs checking", else: "GS1 could not complete this run"}
        </p>
        <p class="mt-1">{@error}</p>
        <p :if={@pending} class="mt-2">
          <.link navigate={results_path(assigns)} class="font-semibold underline">
            View what was generated for this GTIN
          </.link>
        </p>
      </div>

      <.form
        for={@form}
        id="generation-form"
        phx-change="validate"
        phx-submit="submit"
        class="space-y-6 rounded-2xl border border-thamani-stone bg-white p-5 shadow-sm"
      >
        <input type="hidden" name="request[gtin]" value={@gtin} />

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input field={@form[:batch]} type="text" label="Batch / lot" required />
          <.input field={@form[:order_number]} type="text" label="Order number" />
          <.input field={@form[:production_date]} type="date" label="Production date" required />
          <.input field={@form[:expiry_date]} type="date" label="Expiry date" required />
        </div>

        <div :if={@live_action == :sscc} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:count_of_trade_items]}
            type="number"
            min="1"
            label="Trade items on the pallet"
            required
          />
          <.input field={@form[:customer_part_number]} type="text" label="Customer part number" />
          <.input field={@form[:material_description]} type="text" label="Material description" required />
          <.input field={@form[:facility_gln]} type="text" label="Facility GLN" />
        </div>

        <div :if={@live_action == :serialised} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:trade_item_qty]}
            type="number"
            min="1"
            label="Trade items to serialise"
            required
          />
          <.input
            field={@form[:shipper_qty]}
            type="number"
            min="1"
            label="Trade items per shipper"
            required
          />
          <.input field={@form[:customer_part_number]} type="text" label="Customer part number" />
          <.input field={@form[:material_description]} type="text" label="Material description" />
        </div>

        <p
          :if={@live_action == :serialised && authorized_serials(@params)}
          class="rounded-lg bg-slate-50 px-3 py-2 text-sm text-slate-700"
        >
          GS1 will authorize
          <strong>{authorized_serials(@params)}</strong>
          serials for this run — the trade items plus one per shipper.
        </p>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input field={@form[:from_company_name]} type="text" label="From company" />
          <.input field={@form[:to_company_name]} type="text" label="To company" />
          <.input
            field={@form[:from_address]}
            type="text"
            label="From address"
            required={@live_action == :sscc}
          />
          <.input
            field={@form[:to_address]}
            type="text"
            label="To address"
            required={@live_action == :sscc}
          />
        </div>

        <div class="flex flex-wrap items-center gap-3 border-t border-slate-100 pt-4">
          <.button type="submit" variant="primary" disabled={@submitting}>
            {if @submitting, do: "Generating…", else: "Generate with GS1"}
          </.button>
          <.link
            navigate={~p"/org/serialisation"}
            class="text-sm font-semibold text-slate-600 hover:text-slate-900"
          >
            Cancel
          </.link>
          <p :if={@submitting} class="flex items-center gap-2 text-sm text-sky-700">
            <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
            GS1 is issuing the codes. Leaving this page won't cancel the run.
          </p>
        </div>
      </.form>
    </Layouts.org_shell>
    """
  end
end
