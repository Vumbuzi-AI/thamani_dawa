defmodule ThamaniDawaWeb.DistributorCaseLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    unit = Batches.get_logistic_unit!(organization_id, id)
    lines = Batches.list_case_lines(organization_id, unit.id)

    {:ok,
     socket
     |> assign(:unit, unit)
     |> assign(:lines, lines)
     |> assign(:allocations, initial_allocations(lines))
     |> assign(:minted, [])}
  end

  def handle_event("sync", params, socket) do
    {:noreply,
     assign(socket, :allocations, allocations_from_params(params, socket.assigns.allocations))}
  end

  def handle_event("add_shipper", %{"batch_id" => batch_id}, socket) do
    batch_id = parse_quantity(batch_id)
    rows = Map.get(socket.assigns.allocations, batch_id, [])
    next_id = rows |> Enum.map(& &1.id) |> Enum.max(fn -> 0 end) |> Kernel.+(1)

    {:noreply,
     assign(
       socket,
       :allocations,
       Map.put(
         socket.assigns.allocations,
         batch_id,
         rows ++ [%{id: next_id, quantity: "", serials: []}]
       )
     )}
  end

  def handle_event("remove_shipper", %{"batch_id" => batch_id, "row_id" => row_id}, socket) do
    batch_id = parse_quantity(batch_id)
    row_id = parse_quantity(row_id)
    rows = Map.get(socket.assigns.allocations, batch_id, []) |> Enum.reject(&(&1.id == row_id))
    {:noreply, assign(socket, :allocations, Map.put(socket.assigns.allocations, batch_id, rows))}
  end

  def handle_event("break_case", params, socket) do
    lines = socket.assigns.lines
    allocations = allocations_from_params(params, socket.assigns.allocations)
    user_id = socket.assigns.current_scope.user.id

    line_plans =
      Enum.map(lines, fn line ->
        %{batch_id: line.id, groups: allocation_groups(Map.get(allocations, line.id, []))}
      end)

    with :ok <- validate_allocations(lines, allocations),
         {:ok, results} <- Batches.break_logistic_unit(socket.assigns.unit, line_plans, user_id) do
      children = Enum.flat_map(results, & &1.children)
      organization_id = socket.assigns.current_scope.organization_id
      unit = Batches.get_logistic_unit!(organization_id, socket.assigns.unit.id)

      {:noreply,
       socket
       |> assign(:unit, unit)
       |> assign(:lines, Batches.list_case_lines(organization_id, unit.id))
       |> assign(:minted, Enum.map(children, &minted_summary/1))
       |> put_flash(:info, minted_flash(length(children)))}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:allocations, allocations)
         |> put_flash(:error, break_error_message(reason))}
    end
  end

  defp initial_allocations(lines) do
    Map.new(lines, fn line ->
      {line.id, [%{id: 1, quantity: to_string(line.remaining_quantity), serials: line.serials}]}
    end)
  end

  defp allocations_from_params(params, fallback) do
    case Map.get(params, "allocations") do
      allocations when is_map(allocations) ->
        Map.new(allocations, fn {batch_id, rows} ->
          parsed_rows =
            rows
            |> Enum.map(fn {row_id, attrs} ->
              %{
                id: parse_quantity(row_id),
                quantity: Map.get(attrs, "quantity", ""),
                serials: List.wrap(Map.get(attrs, "serials", []))
              }
            end)
            |> Enum.sort_by(& &1.id)

          {parse_quantity(batch_id), parsed_rows}
        end)

      _other ->
        fallback
    end
  end

  defp allocation_groups(rows) do
    Enum.map(rows, &%{quantity: parse_quantity(&1.quantity), serials: &1.serials})
  end

  defp validate_allocations(lines, allocations) do
    if Enum.all?(lines, &line_fully_allocated?(&1, Map.get(allocations, &1.id, []))) do
      :ok
    else
      {:error, :allocation_mismatch}
    end
  end

  defp line_fully_allocated?(line, rows) do
    quantities = Enum.map(rows, &parse_quantity(&1.quantity))

    quantity_matches? =
      rows != [] and Enum.all?(quantities, &(&1 > 0)) and
        Enum.sum(quantities) == line.remaining_quantity

    serials = Enum.flat_map(rows, & &1.serials)

    serials_match? =
      line.serials == [] or
        (Enum.sort(serials) == Enum.sort(line.serials) and
           length(serials) == length(Enum.uniq(serials)) and
           Enum.all?(Enum.zip(rows, quantities), fn {row, quantity} ->
             length(row.serials) == quantity
           end))

    quantity_matches? and serials_match?
  end

  defp parse_quantity(quantity) when is_integer(quantity), do: quantity

  defp parse_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(String.trim(quantity)) do
      {number, ""} -> number
      _other -> 0
    end
  end

  defp parse_quantity(_quantity), do: 0

  defp minted_summary(child) do
    %{id: child.id, sscc: child.sscc, batch_no: child.batch_no, quantity: child.quantity}
  end

  defp minted_flash(1), do: "Broke the case into 1 mini-SSCC. Print its SSCC on the carton."

  defp minted_flash(count),
    do: "Broke the case into #{count} mini-SSCCs. Print each SSCC on its carton."

  defp break_error_message(:not_breakable),
    do: "This case can't be broken — it has already been disaggregated."

  defp break_error_message(:no_lines), do: "This case has no stock to break."

  defp break_error_message(:allocation_mismatch),
    do: "Allocate every unit and serial exactly once before breaking the case."

  defp break_error_message(:insufficient_quantity), do: "A carton size exceeds a line's stock."
  defp break_error_message(_reason), do: "Couldn't break this case into mini-SSCCs."

  defp product_name(product), do: product.generic_name || product.brand_name || "Unknown product"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/receiving"}
    >
      <.header icon="hero-cube" back={true}>
        Break case
        <:subtitle>
          {@unit.sscc} · {@unit.site && @unit.site.name}
        </:subtitle>
      </.header>

      <section
        :if={@minted != []}
        id="minted-mini-ssccs"
        class="mt-5 rounded-2xl border border-thamani-forest/20 bg-thamani-canvas p-5 sm:p-6"
      >
        <h2 class="text-sm font-semibold text-thamani-forest">
          {count_phrase(length(@minted), "new carton")} — print and label each one
        </h2>
        <ul class="mt-4 grid gap-3 sm:grid-cols-2">
          <li :for={child <- @minted} class="rounded-xl border border-thamani-stone bg-td-surface p-4">
            <p class="font-mono text-sm font-semibold tracking-wide text-thamani-ink">{child.sscc}</p>
            <p class="mt-1 text-sm text-thamani-subtle">
              {child.batch_no} · {Products.format_unit_count(child.quantity)}
            </p>
            <.link
              navigate={~p"/distributor/batches/#{child.id}"}
              class="mt-3 inline-flex text-sm font-semibold text-thamani-forest hover:underline"
            >
              Open carton
            </.link>
          </li>
        </ul>
      </section>

      <section
        :if={@unit.status == :disaggregated}
        id="case-retired"
        class="mt-5 flex items-center gap-2 rounded-2xl border border-thamani-stone bg-td-surface px-5 py-4 text-sm text-thamani-subtle sm:px-6"
      >
        <.icon name="hero-check-circle" class="size-4 text-thamani-forest" />
        This case is now closed — its stock lives in the cartons above.
      </section>

      <section
        :if={@unit.status == :active and @lines != []}
        id="sscc-contents"
        class="mt-5 overflow-hidden rounded-2xl border border-thamani-stone bg-td-surface"
      >
        <div class="border-b border-thamani-stone px-5 py-5 sm:px-6">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-td-accent">
            Inside SSCC {@unit.sscc}
          </p>
          <h2 class="mt-1 text-base font-semibold text-thamani-forest">Batches and serials</h2>
          <p class="mt-1 max-w-2xl text-sm leading-6 text-thamani-pewter">
            Review the case contents, then assign every unit to a sub-shipper below.
          </p>
        </div>
        <ul class="divide-y divide-thamani-stone">
          <li :for={line <- @lines} id={"case-line-#{line.id}"} class="px-5 py-4 sm:px-6">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p class="text-sm font-semibold text-thamani-ink">{product_name(line.product)}</p>
                <p class="mt-0.5 text-xs text-thamani-subtle">Batch {line.batch_no}</p>
              </div>
              <span class="rounded-full bg-thamani-canvas px-2.5 py-1 text-xs font-semibold text-thamani-forest">
                {Products.format_unit_count(line.remaining_quantity)}
              </span>
            </div>
            <div
              :if={line.serials != []}
              id={"case-line-serials-#{line.id}"}
              class="mt-3 flex flex-wrap gap-1.5"
            >
              <span
                :for={serial <- line.serials}
                class="rounded-md border border-thamani-stone bg-thamani-canvas/60 px-2 py-1 font-mono text-[11px] text-thamani-pewter"
              >
                {serial}
              </span>
            </div>
            <p :if={line.serials == []} class="mt-2 text-xs text-thamani-subtle">
              Quantity-tracked · no individual serials
            </p>
          </li>
        </ul>
      </section>

      <section
        :if={@unit.status == :active and @lines != []}
        id="break-case-panel"
        class="mt-5 overflow-hidden rounded-2xl border border-thamani-stone bg-td-surface"
      >
        <div class="border-b border-thamani-stone px-5 py-5 sm:px-6">
          <h2 class="text-base font-semibold text-thamani-forest">Build sub-shippers</h2>
          <p class="mt-1 max-w-2xl text-sm leading-6 text-thamani-pewter">
            Add the sub-shippers you actually need. Quantities can differ; for serialized stock,
            select the exact serials packed into each one.
          </p>
        </div>
        <.form
          for={to_form(%{}, as: :break)}
          id="break-case-form"
          phx-change="sync"
          phx-submit="break_case"
        >
          <ul class="divide-y divide-thamani-stone">
            <li :for={line <- @lines} class="px-5 py-5 sm:px-6">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p class="text-sm font-semibold text-thamani-ink">{product_name(line.product)}</p>
                  <p class="mt-0.5 text-xs text-thamani-subtle">
                    Batch {line.batch_no} · {Products.format_unit_count(line.remaining_quantity)}
                  </p>
                </div>
                <button
                  type="button"
                  id={"add-sub-shipper-#{line.id}"}
                  phx-click="add_shipper"
                  phx-value-batch_id={line.id}
                  class="inline-flex items-center gap-1.5 rounded-lg border border-thamani-forest/30 px-3 py-2 text-xs font-semibold text-thamani-forest transition hover:border-thamani-forest hover:bg-thamani-canvas"
                >
                  <.icon name="hero-plus" class="size-3.5" /> Add sub-shipper
                </button>
              </div>

              <div class="mt-4 grid gap-3 lg:grid-cols-2">
                <article
                  :for={row <- Map.get(@allocations, line.id, [])}
                  id={"sub-shipper-#{line.id}-#{row.id}"}
                  class="rounded-xl border border-thamani-stone bg-thamani-canvas/35 p-4"
                >
                  <div class="mb-3 flex items-center justify-between gap-3">
                    <h3 class="text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
                      Sub-shipper {row.id}
                    </h3>
                    <button
                      :if={length(Map.get(@allocations, line.id, [])) > 1}
                      type="button"
                      id={"remove-sub-shipper-#{line.id}-#{row.id}"}
                      phx-click="remove_shipper"
                      phx-value-batch_id={line.id}
                      phx-value-row_id={row.id}
                      class="rounded-md p-1 text-thamani-subtle transition hover:bg-red-50 hover:text-red-700"
                      aria-label={"Remove sub-shipper #{row.id}"}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                  <.input
                    type="number"
                    name={"allocations[#{line.id}][#{row.id}][quantity]"}
                    id={"sub-shipper-quantity-#{line.id}-#{row.id}"}
                    label="Quantity in this sub-shipper"
                    value={row.quantity}
                    min="1"
                  />
                  <fieldset :if={line.serials != []} class="mt-4">
                    <legend class="text-xs font-semibold text-thamani-pewter">
                      Select exact serials
                    </legend>
                    <div class="mt-2 max-h-44 space-y-1.5 overflow-y-auto pr-1">
                      <label
                        :for={serial <- line.serials}
                        class="flex cursor-pointer items-center gap-2 rounded-lg border border-thamani-stone bg-td-surface px-3 py-2 text-xs text-thamani-ink transition hover:border-thamani-forest/40"
                      >
                        <input
                          type="checkbox"
                          name={"allocations[#{line.id}][#{row.id}][serials][]"}
                          value={serial}
                          checked={serial in row.serials}
                          class="size-4 rounded border-thamani-stone text-thamani-forest focus:ring-td-focus"
                        />
                        <span class="font-mono">{serial}</span>
                      </label>
                    </div>
                  </fieldset>
                </article>
              </div>
            </li>
          </ul>
          <div class="flex flex-wrap items-center justify-between gap-3 border-t border-thamani-stone bg-thamani-canvas/40 px-5 py-4 sm:px-6">
            <p class="text-sm text-thamani-pewter">
              Makes {count_phrase(total_shippers(@allocations), "sub-shipper")}, then closes this case.
            </p>
            <.button id="confirm-break-case" variant="primary" type="submit">
              <.icon name="hero-squares-2x2" class="size-4" /> Break case
            </.button>
          </div>
        </.form>
      </section>
    </Layouts.distributor_shell>
    """
  end

  defp total_shippers(allocations) do
    allocations |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
  end

  defp count_phrase(1, word), do: "1 #{word}"
  defp count_phrase(count, word), do: "#{count} #{word}s"
end
