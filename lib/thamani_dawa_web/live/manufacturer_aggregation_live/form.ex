defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Form do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    ssccs = Manufacturing.available_ssccs_for_aggregation(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "New aggregation")
     |> assign(:ssccs, ssccs)
     |> assign(:selected_sscc, nil)
     |> assign(:serials, [])
     |> assign(:sscc_form, to_form(%{"manufacturer_shipper_sscc_id" => ""}, as: :aggregation))
     |> assign(:serial_form, to_form(%{"serial" => ""}, as: :scan))}
  end

  def handle_event(
        "select_sscc",
        %{"aggregation" => %{"manufacturer_shipper_sscc_id" => id}},
        socket
      ) do
    selected = Enum.find(socket.assigns.ssccs, fn sscc -> to_string(sscc.id) == id end)

    {:noreply,
     socket
     |> assign(:selected_sscc, selected)
     |> assign(:serials, [])
     |> assign(:sscc_form, to_form(%{"manufacturer_shipper_sscc_id" => id}, as: :aggregation))}
  end

  def handle_event("add_serial", %{"scan" => %{"serial" => serial}}, socket) do
    serial = String.trim(serial)
    sscc = socket.assigns.selected_sscc
    serials = socket.assigns.serials

    cond do
      is_nil(sscc) ->
        {:noreply, put_flash(socket, :error, "Choose a target SSCC first.")}

      serial == "" ->
        {:noreply, socket}

      Enum.any?(serials, &(&1.serial == serial)) ->
        {:noreply, put_flash(socket, :error, "That serial has already been added.")}

      true ->
        {status, _record} = Manufacturing.classify_serial(socket.assigns.current_scope.organization_id, sscc, serial)

        {:noreply,
         socket
         |> assign(:serials, serials ++ [%{serial: serial, status: status}])
         |> assign(:serial_form, to_form(%{"serial" => ""}, as: :scan))}
    end
  end

  def handle_event("submit", _params, socket) do
    scope = socket.assigns.current_scope
    sscc = socket.assigns.selected_sscc
    serials = socket.assigns.serials

    cond do
      is_nil(sscc) ->
        {:noreply, put_flash(socket, :error, "Choose a target SSCC first.")}

      serials == [] ->
        {:noreply, put_flash(socket, :error, "Add at least one serial before submitting.")}

      not ready?(serials) ->
        {:noreply, put_flash(socket, :error, "Only valid serials can be submitted.")}

      true ->
        case Manufacturing.create_submitted_aggregation(
               scope.organization_id,
               scope.user,
               sscc.id,
               Enum.map(serials, & &1.serial)
             ) do
          {:ok, aggregation} ->
            {:noreply,
             socket
             |> put_flash(:info, "Aggregation submitted for review.")
             |> push_navigate(to: ~p"/manufacturer/aggregations/#{aggregation.id}")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Aggregation could not be submitted.")}
        end
    end
  end

  defp ready?(serials), do: serials != [] and Enum.all?(serials, &(&1.status == "ok"))

  defp sscc_options(ssccs),
    do:
      Enum.map(ssccs, fn sscc ->
        {"#{sscc.code} · #{sscc.gtin || "—"} · #{sscc.count_of_trade_items || 0}", sscc.id}
      end)

  defp batch_label(%{batches: batches}) do
    case Enum.map(batches, & &1.batch_no) do
      [] -> "—"
      batch_numbers -> Enum.join(batch_numbers, ", ")
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
      crumb="Aggregation"
    >
      <.td_page_header
        title="New aggregation"
        subtitle="Pick an existing shipper SSCC, then scan the serials that belong inside it."
      />

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <section class="rounded-2xl ff-surface-card p-5 sm:p-6">
          <div class="space-y-6">
            <div class="space-y-3">
              <.form for={@sscc_form} id="manufacturer-aggregation-sscc-form" phx-change="select_sscc">
                <.td_select
                  field={@sscc_form[:manufacturer_shipper_sscc_id]}
                  label="Target SSCC"
                  prompt="Choose a shipper SSCC"
                  options={sscc_options(@ssccs)}
                  required
                />
              </.form>
            </div>

            <div class="space-y-3 border-t border-thamani-stone pt-5">
              <p class="text-sm font-medium text-thamani-forest">Scan serials</p>
              <.form
                for={@serial_form}
                id="manufacturer-aggregation-scan-form"
                phx-submit="add_serial"
                class="flex flex-col gap-3 sm:flex-row sm:items-end"
              >
                <.td_input
                  field={@serial_form[:serial]}
                  label="Serial"
                  placeholder="Scan or type a serial number"
                  autocomplete="off"
                  required
                />
                <.td_button
                  id="add-manufacturer-aggregation-serial"
                  type="submit"
                  variant="primary"
                  label="Add"
                />
              </.form>
              <p :if={is_nil(@selected_sscc)} class="text-xs text-thamani-pewter">
                Choose a target SSCC before scanning serials.
              </p>
            </div>

            <div :if={@serials != []} class="space-y-3 border-t border-thamani-stone pt-5">
              <ul id="manufacturer-aggregation-serial-list" class="grid gap-3 sm:grid-cols-2">
                <li
                  :for={entry <- @serials}
                  id={"manufacturer-aggregation-serial-#{entry.serial}"}
                  class="rounded-xl border border-thamani-stone bg-td-surface p-3 text-sm"
                >
                  <p class="font-mono text-xs text-thamani-pewter">{entry.serial}</p>
                  <div class="mt-2">
                    <.aggregation_validation_badge status={entry.status} />
                  </div>
                </li>
              </ul>
            </div>

            <div class="td-header-actions">
              <.td_button
                id="cancel-manufacturer-aggregation"
                variant="secondary"
                label="Cancel"
                navigate={~p"/manufacturer/aggregations"}
              />
              <.td_button
                id="submit-manufacturer-aggregation"
                type="button"
                variant="primary"
                label="Submit for review"
                phx-click="submit"
                disabled={!ready?(@serials)}
              />
            </div>
          </div>
        </section>

        <aside class="space-y-4">
          <.sscc_card sscc={@selected_sscc} packed={length(@serials)} />
          <div class="rounded-2xl ff-surface-card p-4">
            <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
              <.icon name="hero-cube" class="size-4" /> Packed
            </div>
            <p class="mt-2 text-2xl font-semibold text-thamani-forest">
              {length(@serials)}<span class="text-sm font-normal text-thamani-pewter">
                / {(@selected_sscc && @selected_sscc.count_of_trade_items) || 0}
              </span>
            </p>
            <p class="text-xs text-thamani-pewter">serials in this aggregation</p>
          </div>
        </aside>
      </div>
    </Layouts.manufacturer_shell>
    """
  end

  attr :sscc, :any, required: true
  attr :packed, :integer, required: true

  defp sscc_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border p-4",
      if(@sscc,
        do: "border-thamani-forest/30 bg-td-accent-tint",
        else: "border-dashed border-thamani-stone bg-thamani-canvas"
      )
    ]}>
      <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
        <.icon name="hero-qr-code" class="size-4" /> Target SSCC
      </div>
      <%= if @sscc do %>
        <p class="mt-2 font-mono text-sm font-semibold text-thamani-forest">{@sscc.code}</p>
        <p class="text-sm">GTIN <span class="font-mono text-xs">{@sscc.gtin || "—"}</span></p>
        <p class="text-sm">Batch {batch_label(@sscc)}</p>
        <p class="mt-1 text-xs text-thamani-pewter">
          {@packed} / {@sscc.count_of_trade_items || 0} packed
        </p>
      <% else %>
        <p class="mt-2 text-sm text-thamani-pewter">Not selected yet.</p>
      <% end %>
    </div>
    """
  end
end
