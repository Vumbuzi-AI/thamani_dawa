defmodule ThamaniDawaWeb.ManufacturerProductLive.SerialWizard do
  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.SerialGeneration

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:mode, fn -> nil end)
     |> assign_new(:step, fn -> 1 end)
     |> assign_new(:submitting, fn -> false end)
     |> assign_new(:to_gln_check, fn -> :idle end)
     |> assign_new(:form_params, fn -> default_params(assigns.site) end)
     |> assign_new(:form, fn -> to_form(default_params(assigns.site), as: :serial_generation) end)}
  end

  defp default_params(site) do
    %{
      "batch_no" => "",
      "production_date" => "",
      "expiry_date" => "",
      "primary_quantity" => "",
      "shipper_quantity" => "",
      "from_gln" => site.gln || "",
      "from_company_name" => site.name || "",
      "from_address" => site.address || "",
      "to_gln" => "",
      "to_company_name" => "",
      "to_address" => ""
    }
  end

  def handle_event("choose_mode", %{"mode" => mode}, socket) when mode in ["order", "stock"] do
    {:noreply, socket |> assign(:mode, mode) |> assign(:step, 2)}
  end

  def handle_event("next_step", _params, socket) do
    {:noreply, assign(socket, :step, 3)}
  end

  def handle_event("prev_step", _params, socket) do
    case socket.assigns.step do
      3 -> {:noreply, assign(socket, :step, 2)}
      2 -> {:noreply, socket |> assign(:step, 1) |> assign(:mode, nil)}
      step -> {:noreply, assign(socket, :step, step)}
    end
  end

  def handle_event("validate", %{"serial_generation" => params}, socket) do
    params = sync_from_facility(params, socket.assigns.facilities)
    errors = validation_errors(params, socket.assigns.mode)

    socket =
      socket
      |> assign(:form_params, params)
      |> assign(:form, generation_form(params, errors))
      |> maybe_check_to_gln(params)

    {:noreply, socket}
  end

  def handle_event("save", %{"serial_generation" => params}, socket) do
    params = sync_from_facility(params, socket.assigns.facilities)

    case resolve_to_party(params, socket.assigns.mode) do
      {:ok, params} ->
        errors = validation_errors(params, socket.assigns.mode)

        if errors == [] do
          generate(socket, socket.assigns.mode, params)
        else
          {:noreply, assign_form(socket, params, errors)}
        end

      {:error, params} ->
        errors = [{:to_gln, {"could not be verified", []}} | validation_errors(params, "order")]
        {:noreply, socket |> assign(:to_gln_check, :not_found) |> assign_form(params, errors)}
    end
  end

  defp maybe_check_to_gln(socket, params) do
    gln = params |> Map.get("to_gln", "") |> String.trim()

    if Regex.match?(~r/^\d{13}$/, gln) do
      socket
      |> assign(:to_gln_check, :checking)
      |> start_async(:to_gln_lookup, fn -> {gln, GlnLookup.resolve_party(gln)} end)
    else
      assign(socket, :to_gln_check, :idle)
    end
  end

  def handle_async(:to_gln_lookup, {:ok, {gln, {:ok, party}}}, socket) do
    if socket.assigns.form_params["to_gln"] == gln do
      params = put_to_party(socket.assigns.form_params, party)
      errors = validation_errors(params, socket.assigns.mode)

      {:noreply,
       socket
       |> assign(:to_gln_check, :matched)
       |> assign_form(params, errors)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:to_gln_lookup, {:ok, {_gln, {:error, :not_found}}}, socket),
    do: {:noreply, assign(socket, :to_gln_check, :not_found)}

  def handle_async(:to_gln_lookup, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :to_gln_check, :unavailable)}

  defp resolve_to_party(params, "order") do
    case GlnLookup.resolve_party(params["to_gln"]) do
      {:ok, party} -> {:ok, put_to_party(params, party)}
      {:error, :not_found} -> {:error, params}
    end
  end

  defp resolve_to_party(params, _mode), do: {:ok, params}

  defp put_to_party(params, party), do: SerialGeneration.put_to_party(params, party)

  defp assign_form(socket, params, errors) do
    socket
    |> assign(:form_params, params)
    |> assign(:form, generation_form(params, errors))
  end

  defp generate(socket, "stock", params) do
    quantity = String.to_integer(params["primary_quantity"])
    batch_attrs = SerialGeneration.batch_attrs(params)

    case Manufacturing.generate_primary_serials(
           socket.assigns.organization_id,
           socket.assigns.product,
           batch_attrs,
           quantity,
           socket.assigns.site.gln
         ) do
      {:ok, %{serials: serials}} ->
        send(self(), {:serial_generation_complete, length(serials)})
        {:noreply, assign(socket, :submitting, false)}

      {:error, reason} ->
        send(self(), {:serial_generation_failed, reason})
        {:noreply, assign(socket, :submitting, false)}
    end
  end

  defp generate(socket, "order", params) do
    primary_quantity = String.to_integer(params["primary_quantity"])
    shipper_quantity = String.to_integer(params["shipper_quantity"])
    batch_attrs = SerialGeneration.batch_attrs(params)
    parties = SerialGeneration.parties(params)

    case Manufacturing.generate_order_serials(
           socket.assigns.organization_id,
           socket.assigns.product,
           batch_attrs,
           primary_quantity,
           shipper_quantity,
           socket.assigns.site.gln,
           parties
         ) do
      {:ok, %{serials: serials, shippers: shippers}} ->
        send(self(), {:serial_generation_complete, length(serials), length(shippers)})
        {:noreply, assign(socket, :submitting, false)}

      {:error, reason} ->
        send(self(), {:serial_generation_failed, reason})
        {:noreply, assign(socket, :submitting, false)}
    end
  end

  defp sync_from_facility(params, facilities),
    do: SerialGeneration.fill_from_facility(params, facilities)

  defp facility_options(facilities) do
    Enum.map(facilities, fn facility ->
      {"#{facility.name} · #{facility.gln}", facility.gln}
    end)
  end

  defp destination_facility_options(facilities, from_gln) do
    facilities
    |> Enum.reject(&(&1.gln == from_gln))
    |> facility_options()
  end

  defp generation_form(params, errors) do
    to_form(params, as: :serial_generation, errors: errors)
  end

  defp validation_errors(params, mode), do: SerialGeneration.errors(params, mode)

  defp step_label(1), do: "Mode"
  defp step_label(2), do: "Batch & quantity"
  defp step_label(3), do: "From / To"

  defp total_steps("order"), do: 3
  defp total_steps(_mode), do: 2

  def render(assigns) do
    ~H"""
    <div id="manufacturer-serial-wizard">
      <div class="mb-8 flex items-center gap-3" aria-label="Serial generation progress">
        <div :for={n <- 1..total_steps(@mode)} class="flex flex-1 items-center gap-2">
          <span class={[
            "flex size-8 shrink-0 items-center justify-center rounded-full text-sm font-bold",
            if(@step >= n,
              do: "bg-thamani-forest text-white",
              else: "bg-thamani-mist text-thamani-pewter"
            )
          ]}>{n}</span>
          <span class={[
            "text-sm font-semibold",
            if(@step >= n, do: "text-thamani-forest", else: "text-thamani-pewter")
          ]}>{step_label(n)}</span>
          <div :if={n < total_steps(@mode)} class="h-px flex-1 bg-thamani-stone"></div>
        </div>
      </div>

      <%= if @step == 1 do %>
        <section
          id="serial-wizard-product"
          class="rounded-2xl border border-thamani-stone bg-thamani-snow p-6"
        >
          <p class="text-xs font-bold uppercase tracking-[0.18em] text-thamani-pewter">
            Selected product
          </p>
          <p class="mt-3 text-xl font-semibold text-thamani-forest">{@product.name}</p>
          <p class="mt-1 font-mono text-sm text-thamani-pewter">GTIN {@product.gtin}</p>
        </section>

        <div class="mt-6 grid gap-4 sm:grid-cols-2">
          <button
            id="serial-wizard-mode-order"
            type="button"
            phx-click="choose_mode"
            phx-value-mode="order"
            phx-target={@myself}
            class="rounded-2xl border border-thamani-stone bg-white p-5 text-left transition hover:border-thamani-forest hover:bg-thamani-mist"
          >
            <p class="text-sm font-semibold text-thamani-forest">Make to order</p>
            <p class="mt-1 text-xs text-thamani-pewter">
              Create the shipper SSCCs now, with a From/To party for the labels.
            </p>
          </button>
          <button
            id="serial-wizard-mode-stock"
            type="button"
            phx-click="choose_mode"
            phx-value-mode="stock"
            phx-target={@myself}
            class="rounded-2xl border border-thamani-stone bg-white p-5 text-left transition hover:border-thamani-forest hover:bg-thamani-mist"
          >
            <p class="text-sm font-semibold text-thamani-forest">Make to stock</p>
            <p class="mt-1 text-xs text-thamani-pewter">
              Store as groups of batches — no SSCC is created yet.
            </p>
          </button>
        </div>
      <% else %>
        <.form
          for={@form}
          id="manufacturer-serial-generation-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <%= if @step == 2 do %>
            <div class="grid gap-5 sm:grid-cols-2">
              <.input field={@form[:batch_no]} label="Batch #" required />
              <.input
                field={@form[:primary_quantity]}
                type="number"
                min="1"
                max="100"
                label="Primary quantity"
                required
              />
              <.input field={@form[:production_date]} type="date" label="Production date" required />
              <.input field={@form[:expiry_date]} type="date" label="Expiry date" required />
              <.input
                :if={@mode == "order"}
                field={@form[:shipper_quantity]}
                type="number"
                min="1"
                label="Shipper quantity (boxes to split primaries across)"
                required
              />
            </div>
            <div class="mt-8 flex items-center justify-between gap-3">
              <.button
                id="serial-wizard-prev"
                type="button"
                phx-click="prev_step"
                phx-target={@myself}
              >
                <.icon name="hero-arrow-left" class="size-4" /> Prev
              </.button>
              <%= if @mode == "order" do %>
                <.button
                  id="serial-wizard-next"
                  type="button"
                  variant="primary"
                  phx-click="next_step"
                  phx-target={@myself}
                >
                  Next <.icon name="hero-arrow-right" class="size-4" />
                </.button>
              <% else %>
                <.button id="serial-wizard-submit" variant="primary" phx-disable-with="Generating…">
                  <.icon name="hero-qr-code" class="size-4" /> Generate serials
                </.button>
              <% end %>
            </div>
          <% else %>
            <input type="hidden" name="serial_generation[batch_no]" value={@form[:batch_no].value} />
            <input
              type="hidden"
              name="serial_generation[production_date]"
              value={@form[:production_date].value}
            />
            <input
              type="hidden"
              name="serial_generation[expiry_date]"
              value={@form[:expiry_date].value}
            />
            <input
              type="hidden"
              name="serial_generation[primary_quantity]"
              value={@form[:primary_quantity].value}
            />
            <input
              type="hidden"
              name="serial_generation[shipper_quantity]"
              value={@form[:shipper_quantity].value}
            />
            <div class="grid gap-5 sm:grid-cols-2">
              <div class="space-y-4 rounded-2xl border border-thamani-stone p-4">
                <p class="text-xs font-bold uppercase tracking-[0.18em] text-thamani-pewter">From</p>
                <.input
                  field={@form[:from_gln]}
                  type="combobox"
                  label="From facility"
                  options={facility_options(@facilities)}
                  placeholder="Search your facilities"
                  required
                />
                <.input field={@form[:from_company_name]} label="From company name" required />
                <.input field={@form[:from_address]} label="From address" required />
              </div>
              <div class="space-y-4 rounded-2xl border border-thamani-stone p-4">
                <p class="text-xs font-bold uppercase tracking-[0.18em] text-thamani-pewter">To</p>
                <.input
                  field={@form[:to_gln]}
                  type="combobox"
                  label="To GLN"
                  options={destination_facility_options(@facilities, @form[:from_gln].value)}
                  placeholder="Search other facilities"
                  phx-debounce="500"
                  required
                />
                <p :if={@to_gln_check == :checking} class="text-xs text-thamani-pewter">
                  <.icon name="hero-arrow-path" class="inline size-3.5 motion-safe:animate-spin" />
                  Looking up company…
                </p>
                <p
                  :if={@to_gln_check == :not_found}
                  class="rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800"
                >
                  We couldn't verify this GLN.
                </p>
                <.input field={@form[:to_company_name]} label="To company name" readonly required />
                <.input field={@form[:to_address]} label="To address" readonly required />
              </div>
            </div>
            <div class="mt-8 flex items-center justify-between gap-3">
              <.button
                id="serial-wizard-prev"
                type="button"
                phx-click="prev_step"
                phx-target={@myself}
              >
                <.icon name="hero-arrow-left" class="size-4" /> Prev
              </.button>
              <.button id="serial-wizard-submit" variant="primary" phx-disable-with="Generating…">
                <.icon name="hero-qr-code" class="size-4" /> Generate serials & SSCCs
              </.button>
            </div>
          <% end %>
        </.form>
      <% end %>
    </div>
    """
  end
end
