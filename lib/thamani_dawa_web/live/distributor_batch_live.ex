defmodule ThamaniDawaWeb.DistributorBatchLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Products
  alias ThamaniDawa.Repo

  def mount(%{"id" => id}, _session, socket) do
    batch = load_batch(socket, id)

    {:ok,
     socket
     |> assign(:batch, batch)
     |> assign(:serials_expanded, false)
     |> assign(:split_open, false)
     |> assign(:split_groups, [])
     |> assign(:minted_mini_ssccs, [])
     |> assign_case_lines(batch)
     |> load_trail(batch)}
  end

  def handle_event("toggle_batch_serials", _params, socket) do
    {:noreply, assign(socket, :serials_expanded, not socket.assigns.serials_expanded)}
  end

  def handle_event("open_split", _params, socket) do
    socket =
      if socket.assigns.split_open do
        assign(socket, :split_open, false)
      else
        socket
        |> assign(:split_open, true)
        |> assign(:split_groups, [%{key: 1, quantity: "", serials: []}])
      end

    {:noreply, socket}
  end

  def handle_event("add_group", _params, socket) do
    groups = socket.assigns.split_groups

    next_key =
      case Enum.map(groups, & &1.key) do
        [] -> 1
        keys -> Enum.max(keys) + 1
      end

    {:noreply,
     assign(socket, :split_groups, groups ++ [%{key: next_key, quantity: "", serials: []}])}
  end

  def handle_event("remove_group", %{"key" => key}, socket) do
    key = parse_key(key)
    groups = Enum.reject(socket.assigns.split_groups, &(&1.key == key))
    {:noreply, assign(socket, :split_groups, groups)}
  end

  def handle_event("sync_split_groups", %{"groups" => groups}, socket) do
    {:noreply, assign(socket, :split_groups, form_groups(groups))}
  end

  def handle_event("sync_split_groups", _params, socket), do: {:noreply, socket}

  def handle_event("split_evenly", params, socket) do
    batch = socket.assigns.batch
    size = parse_quantity(Map.get(params, "carton_size", ""))

    cond do
      size <= 0 ->
        {:noreply, put_flash(socket, :error, "Enter a carton size greater than zero.")}

      batch.remaining_quantity <= 0 ->
        {:noreply, put_flash(socket, :error, "This batch has no stock left to break.")}

      true ->
        {:noreply, assign(socket, :split_groups, even_groups(batch, size))}
    end
  end

  def handle_event("break_into_mini_ssccs", params, socket) do
    batch = socket.assigns.batch
    form_groups = form_groups(Map.get(params, "groups", %{}))
    groups = context_groups(form_groups, batch)
    user_id = socket.assigns.current_scope.user.id

    socket = assign(socket, :split_groups, form_groups)

    case break_batch(batch, groups, user_id) do
      {:ok, children} ->
        reloaded = load_batch(socket, batch.id)

        {:noreply,
         socket
         |> assign(:batch, reloaded)
         |> assign_case_lines(reloaded)
         |> assign(:split_open, false)
         |> assign(:split_groups, [])
         |> assign(:minted_mini_ssccs, Enum.map(children, &minted_summary/1))
         |> put_flash(:info, minted_flash(length(children)))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, split_error_message(reason))}
    end
  end

  # Cased stock breaks through its logistic unit (one line at a time — the
  # case SSCC is retired only when its last line is broken). Loose stock
  # breaks the batch directly.
  defp break_batch(%{logistic_unit_id: nil} = batch, groups, user_id) do
    Batches.break_into_mini_ssccs(batch, groups, user_id)
  end

  defp break_batch(batch, groups, user_id) do
    case Batches.break_logistic_unit(
           batch.logistic_unit,
           [%{batch_id: batch.id, groups: groups}],
           user_id
         ) do
      {:ok, results} -> {:ok, Enum.flat_map(results, & &1.children)}
      other -> other
    end
  end

  defp load_batch(socket, id) do
    socket.assigns.current_scope.organization_id
    |> Batches.get_batch_with_details!(id)
    |> Repo.preload(:logistic_unit)
  end

  defp assign_case_lines(socket, %{logistic_unit_id: nil}) do
    assign(socket, :case_lines, [])
  end

  defp assign_case_lines(socket, batch) do
    organization_id = socket.assigns.current_scope.organization_id
    lines = Batches.list_case_lines(organization_id, batch.logistic_unit_id)
    assign(socket, :case_lines, lines)
  end

  defp load_trail(socket, batch) do
    organization_id = socket.assigns.current_scope.organization_id

    socket
    |> assign(:batch, batch)
    |> assign(:trail_shipments, Batches.list_shipments_from_batch(batch))
    |> assign(:trail_events, Outbox.list_events_for_source(organization_id, "batch", batch.id))
  end

  defp status_label(:inactive), do: "Lost"
  defp status_label(:non_sellable_other), do: "Exported"
  defp status_label(status), do: Phoenix.Naming.humanize(status)

  defp count_phrase(1, word), do: "1 #{word}"
  defp count_phrase(count, word), do: "#{count} #{word}s"

  defp humanize_step(nil), do: "—"

  defp humanize_step(step) when is_binary(step) do
    step
    |> String.replace_prefix("urn:epcglobal:cbv:bizstep:", "")
    |> String.replace_prefix("urn:epcglobal:cbv:disp:", "")
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_step(step), do: Phoenix.Naming.humanize(step)

  defp minted_summary(child) do
    %{
      id: child.id,
      sscc: child.sscc,
      batch_no: child.batch_no,
      quantity: child.quantity,
      serials: child.serials
    }
  end

  defp minted_flash(1), do: "Broke out 1 mini-SSCC. Print its SSCC on the carton."
  defp minted_flash(count), do: "Broke out #{count} mini-SSCCs. Print each SSCC on its carton."

  defp form_groups(params) when params == %{}, do: []

  defp form_groups(params) when is_map(params) do
    params
    |> Enum.map(fn {key, row} ->
      row = if is_map(row), do: row, else: %{}

      %{
        key: parse_key(key),
        quantity: Map.get(row, "quantity", ""),
        serials: normalize_serials(Map.get(row, "serials", []))
      }
    end)
    |> Enum.sort_by(& &1.key)
  end

  defp form_groups(_params), do: []

  # Pre-fills the split form with cartons of `size`. A serialized batch chunks
  # its serials so each carton's count matches; a quantity-only batch chunks
  # the count. The final carton holds the smaller remainder.
  defp even_groups(batch, size) do
    if batch.serials == [] do
      batch.remaining_quantity
      |> chunk_counts(size)
      |> Enum.with_index(1)
      |> Enum.map(fn {quantity, key} ->
        %{key: key, quantity: Integer.to_string(quantity), serials: []}
      end)
    else
      batch.serials
      |> Enum.chunk_every(size)
      |> Enum.with_index(1)
      |> Enum.map(fn {serials, key} ->
        %{key: key, quantity: Integer.to_string(length(serials)), serials: serials}
      end)
    end
  end

  defp chunk_counts(total, size) do
    full = div(total, size)
    rest = rem(total, size)
    List.duplicate(size, full) ++ if(rest > 0, do: [rest], else: [])
  end

  defp context_groups(groups, batch) do
    Enum.map(groups, fn group ->
      serials = if batch.serials == [], do: [], else: group.serials
      %{quantity: parse_quantity(group.quantity), serials: serials}
    end)
  end

  defp normalize_serials(serials) when is_list(serials),
    do: Enum.reject(serials, &(&1 in [nil, ""]))

  defp normalize_serials(serial) when is_binary(serial) and serial != "", do: [serial]
  defp normalize_serials(_serials), do: []

  defp parse_quantity(quantity) when is_integer(quantity), do: quantity

  defp parse_quantity(quantity) when is_binary(quantity) do
    case Integer.parse(String.trim(quantity)) do
      {number, ""} -> number
      _other -> 0
    end
  end

  defp parse_quantity(_quantity), do: 0

  defp claimed_units(groups) do
    Enum.reduce(groups, 0, fn group, sum -> sum + parse_quantity(group.quantity) end)
  end

  defp parse_key(key) do
    case Integer.parse(to_string(key)) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  defp split_error_message(:not_found), do: "That batch could not be found."
  defp split_error_message(:no_groups), do: "Add at least one mini-SSCC group."

  defp split_error_message(:invalid_group_quantity),
    do: "Each group needs a quantity greater than zero."

  defp split_error_message(:insufficient_quantity),
    do: "The split quantity exceeds the stock on hand."

  defp split_error_message(:not_breakable),
    do: "This batch can't be broken — it has no stock on hand or is already disaggregated."

  defp split_error_message(:invalid_serials),
    do:
      "Each group's serials must match its quantity and come from this batch's remaining serials, with no duplicates."

  defp split_error_message(:missing_gs1_company_prefix),
    do: "Set a GS1 company prefix before minting SSCCs."

  defp split_error_message({:gs1, :unconfigured}),
    do: "SSCC issuing is not configured. Contact your platform administrator."

  defp split_error_message({:gs1, :unauthorized}),
    do: "GS1 rejected the API credentials. Contact your platform administrator."

  defp split_error_message({:gs1, :forbidden}),
    do: "This account is not allowed to issue SSCCs at GS1."

  defp split_error_message({:gs1, :unavailable}),
    do: "GS1 could not issue an SSCC just now. Try again in a moment."

  defp split_error_message({:gs1, {:invalid, message}}) when is_binary(message),
    do: "GS1 rejected the SSCC: #{message}"

  defp split_error_message({:gs1, _reason}),
    do: "GS1 could not issue an SSCC just now. Try again in a moment."

  defp split_error_message(%Ecto.Changeset{} = changeset) do
    summary =
      changeset
      |> Ecto.Changeset.traverse_errors(&translate_error/1)
      |> Enum.map_join("; ", fn {field, messages} ->
        "#{field} #{Enum.join(messages, ", ")}"
      end)

    "Couldn't break that batch: #{summary}"
  end

  defp split_error_message(_reason), do: "Couldn't break that batch into mini-SSCCs."

  defp product_name(product), do: product.generic_name || product.brand_name || "Unknown product"
  defp date_or_dash(nil), do: "—"
  defp date_or_dash(date), do: Calendar.strftime(date, "%d %b %Y")

  attr :group, :map, required: true
  attr :groups, :list, required: true
  attr :batch, :map, required: true

  def split_group(assigns) do
    taken_elsewhere =
      assigns.groups
      |> Enum.reject(&(&1.key == assigns.group.key))
      |> Enum.flat_map(& &1.serials)
      |> MapSet.new()

    assigns = assign(assigns, :taken_elsewhere, taken_elsewhere)

    ~H"""
    <div
      id={"split-group-#{@group.key}"}
      class="rounded-xl border border-thamani-stone bg-thamani-canvas p-4"
    >
      <div class="mb-3 flex items-center justify-between gap-3">
        <p class="text-sm font-semibold text-thamani-forest">Carton {@group.key}</p>
        <button
          type="button"
          id={"remove-split-group-#{@group.key}"}
          phx-click="remove_group"
          phx-value-key={@group.key}
          class="inline-flex items-center gap-1 text-sm font-medium text-thamani-pewter transition hover:text-thamani-error"
        >
          <.icon name="hero-x-mark" class="size-4" /> Remove
        </button>
      </div>
      <.input
        type="number"
        name={"groups[#{@group.key}][quantity]"}
        id={"split-quantity-#{@group.key}"}
        label="Units in this carton"
        value={@group.quantity}
        min="1"
        required
      />
      <fieldset :if={@batch.serials != []} class="mt-1">
        <legend class="text-sm font-medium text-thamani-forest">
          Serials in this carton
          <span class="font-normal text-thamani-pewter">
            — select exactly as many as the quantity
          </span>
        </legend>
        <div class="mt-2 grid gap-1.5 sm:grid-cols-2 lg:grid-cols-3">
          <label
            :for={serial <- @batch.serials}
            class={[
              "flex items-center gap-2 rounded-lg border px-2.5 py-1.5 font-mono text-xs transition",
              serial in @group.serials && "border-thamani-forest bg-td-surface text-thamani-forest",
              serial not in @group.serials && serial not in @taken_elsewhere &&
                "border-thamani-stone bg-td-surface text-thamani-ink hover:border-thamani-forest/40",
              serial in @taken_elsewhere &&
                "cursor-not-allowed border-thamani-stone bg-td-surface/40 text-thamani-subtle"
            ]}
          >
            <input
              type="checkbox"
              id={"split-serial-#{@group.key}-#{serial}"}
              name={"groups[#{@group.key}][serials][]"}
              value={serial}
              checked={serial in @group.serials}
              disabled={serial in @taken_elsewhere}
              class="size-3.5 rounded border-thamani-stone text-thamani-forest focus:ring-thamani-forest/30"
            />
            <span class="truncate" title={serial}>{serial}</span>
          </label>
        </div>
      </fieldset>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :last?, :boolean, default: false
  slot :inner_block, required: true

  defp trail_step(assigns) do
    ~H"""
    <li class="flex gap-3">
      <div class="flex w-8 shrink-0 flex-col items-center">
        <span class="flex size-8 items-center justify-center rounded-full bg-td-accent-tint text-thamani-forest">
          <.icon name={@icon} class="size-4" />
        </span>
        <span :if={!@last?} class="mt-1 w-px flex-1 bg-thamani-stone"></span>
      </div>
      <div class={["min-w-0 pt-1", !@last? && "pb-5"]}>
        <p class="text-sm font-medium text-thamani-forest">{@title}</p>
        <div class="mt-1 text-sm text-thamani-pewter">
          {render_slot(@inner_block)}
        </div>
      </div>
    </li>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/products"}
    >
      <.header icon="hero-archive-box">
        {@batch.batch_no}
        <:subtitle>{product_name(@batch.product)} batch details and receiving record.</:subtitle>
        <:actions>
          <.button
            :if={@batch.remaining_quantity > 0 and is_nil(@batch.logistic_unit_id)}
            id="break-bulk-button"
            variant="primary"
            type="button"
            phx-click="open_split"
          >
            <.icon name="hero-square-2-stack" class="size-4" />
            <%= if @split_open do %>
              Close split
            <% else %>
              Break into mini-SSCCs
            <% end %>
          </.button>
          <.button variant="ghost" navigate={~p"/distributor/products?view=batches"}>
            <.icon name="hero-arrow-left" class="size-4" /> All batches
          </.button>
        </:actions>
      </.header>

      <section
        :if={@batch.logistic_unit && length(@case_lines) > 1}
        id="case-contents"
        class="mt-5 rounded-2xl border border-thamani-stone bg-td-surface p-5 sm:p-6"
      >
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 class="text-sm font-semibold text-thamani-forest">Case contents</h2>
          <p class="font-mono text-xs text-thamani-subtle">SSCC {@batch.logistic_unit.sscc}</p>
        </div>
        <p class="mt-1 text-sm text-thamani-subtle">
          This case holds {count_phrase(length(@case_lines), "product")}.
          <.link
            navigate={~p"/distributor/cases/#{@batch.logistic_unit_id}"}
            class="font-semibold text-thamani-forest hover:underline"
          >
            Break the whole case
          </.link>
          to split every line into mini-SSCCs at once and retire its SSCC.
        </p>
        <ul class="mt-4 divide-y divide-thamani-stone">
          <li
            :for={line <- @case_lines}
            class="flex items-center justify-between gap-3 py-2.5 text-sm"
          >
            <span class={[line.id == @batch.id && "font-semibold text-thamani-forest"]}>
              {product_name(line.product)}
              <span class="text-thamani-subtle">· {line.batch_no}</span>
            </span>
            <.link
              :if={line.id != @batch.id}
              navigate={~p"/distributor/batches/#{line.id}"}
              class="shrink-0 font-semibold text-thamani-forest hover:underline"
            >
              Open
            </.link>
            <span :if={line.id == @batch.id} class="shrink-0 text-xs text-thamani-subtle">
              Viewing
            </span>
          </li>
        </ul>
      </section>

      <section
        :if={@minted_mini_ssccs != []}
        id="minted-mini-ssccs"
        class="mt-5 rounded-2xl border border-thamani-forest/20 bg-thamani-canvas p-5 sm:p-6"
      >
        <h2 class="text-sm font-semibold text-thamani-forest">New mini-SSCCs</h2>
        <p class="mt-1 text-sm text-thamani-subtle">
          Print each code on the physical carton. These units are in storage and can be shipped or split again.
        </p>
        <ul class="mt-4 grid gap-3 sm:grid-cols-2">
          <li
            :for={child <- @minted_mini_ssccs}
            class="rounded-xl border border-thamani-stone bg-td-surface p-4"
          >
            <p class="font-mono text-sm font-semibold tracking-wide text-thamani-ink">{child.sscc}</p>
            <p class="mt-1 text-sm text-thamani-subtle">
              {child.batch_no} · {Products.format_unit_count(child.quantity)}
            </p>
            <.link
              navigate={~p"/distributor/batches/#{child.id}"}
              class="mt-3 inline-flex text-sm font-semibold text-thamani-forest hover:underline"
            >
              Open mini-SSCC
            </.link>
          </li>
        </ul>
      </section>

      <section
        :if={@split_open}
        id="mini-sscc-panel"
        class="mt-5 overflow-hidden rounded-2xl border border-thamani-stone bg-td-surface"
      >
        <% claimed = claimed_units(@split_groups) %>
        <div class="border-b border-thamani-stone px-5 py-5 sm:px-6">
          <h2 class="text-base font-semibold text-thamani-forest">
            Break this case into mini-SSCCs
          </h2>
          <p class="mt-2 max-w-2xl text-sm leading-6 text-thamani-pewter">
            Choose how many units go in each carton.
            <%= if @batch.serials != [] do %>
              Then pick that many serials for the carton.
            <% end %>
            Units you do not place become their own remainder carton.
          </p>
          <p class="mt-1 max-w-2xl text-sm leading-6 text-thamani-pewter">
            This retires
            <span class="font-semibold tracking-tight text-thamani-forest tabular-nums">{@batch.batch_no}</span>
            and its inbound SSCC. The case can no longer ship as one carton.
          </p>
          <p
            id="split-tally"
            class="mt-4 flex flex-wrap items-baseline gap-x-4 gap-y-1 text-sm text-thamani-pewter"
          >
            <span>
              <span class="font-semibold tabular-nums text-thamani-forest">{@batch.remaining_quantity}</span>
              on hand
            </span>
            <span>
              <span class="font-semibold tabular-nums text-thamani-forest">{claimed}</span> in cartons
            </span>
            <%= if claimed > @batch.remaining_quantity do %>
              <span class="font-semibold text-thamani-error">
                {claimed - @batch.remaining_quantity} over the case
              </span>
            <% else %>
              <span>
                <span class="font-semibold tabular-nums text-thamani-forest">
                  {@batch.remaining_quantity - claimed}
                </span>
                left over
              </span>
            <% end %>
          </p>
        </div>
        <.form
          for={to_form(%{}, as: :even)}
          id="even-split-form"
          phx-submit="split_evenly"
          class="flex flex-col gap-3 border-b border-thamani-stone bg-thamani-canvas/50 px-5 py-4 sm:flex-row sm:items-end sm:px-6"
        >
          <div class="min-w-0 sm:w-56">
            <.input
              type="number"
              name="carton_size"
              id="even-carton-size"
              label="Units per carton"
              value=""
              min="1"
            />
          </div>
          <.button id="even-split-apply" variant="ghost" type="submit">
            <.icon name="hero-squares-plus" class="size-4" /> Fill cartons evenly
          </.button>
        </.form>
        <.form
          for={to_form(%{}, as: :split)}
          id="mini-sscc-form"
          phx-change="sync_split_groups"
          phx-submit="break_into_mini_ssccs"
          class="space-y-3 px-5 py-4 sm:px-6"
        >
          <.split_group
            :for={group <- @split_groups}
            group={group}
            groups={@split_groups}
            batch={@batch}
          />
          <p :if={@split_groups == []} id="split-groups-empty" class="text-sm text-thamani-pewter">
            Add a carton to start the split.
          </p>
          <div class="flex flex-wrap items-center gap-2 pt-1">
            <button
              type="button"
              id="add-split-group"
              phx-click="add_group"
              class="td-btn is-secondary is-md"
            >
              <.icon name="hero-plus" class="size-4" /> Add carton
            </button>
            <.button id="confirm-mini-sscc-split" variant="primary" type="submit">
              Mint mini-SSCCs
            </.button>
          </div>
        </.form>
      </section>

      <section class="mt-5 rounded-2xl border border-thamani-stone bg-td-surface p-5 sm:p-6">
        <dl class="grid gap-x-8 gap-y-5 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">GTIN</dt>
            <dd class="mt-1 text-sm text-thamani-ink">{@batch.gtin}</dd>
          </div>
          <div :if={@batch.sscc}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">SSCC</dt>
            <dd id="batch-sscc" class="mt-1 text-sm text-thamani-ink">{@batch.sscc}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufacturer
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {@batch.manufacturer || @batch.product.manufacturer || "—"}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufactured
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">{date_or_dash(@batch.manufacture_date)}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Expiry</dt>
            <dd class="mt-1 text-sm text-thamani-ink">{date_or_dash(@batch.expiry_date)}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Warehouse</dt>
            <dd class="mt-1 text-sm text-thamani-ink">{@batch.site.name}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Received</dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              {Products.format_unit_count(@batch.quantity)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">On hand</dt>
            <dd id="batch-on-hand" class="mt-1 text-sm text-thamani-ink">
              {Products.format_unit_count(@batch.remaining_quantity)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Goods receipt
            </dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              <.link
                :if={@batch.goods_receipt}
                navigate={~p"/distributor/receiving/#{@batch.goods_receipt.id}"}
                class="font-mono font-semibold text-thamani-forest hover:underline"
              >
                {@batch.goods_receipt.number}
              </.link>
              <span :if={is_nil(@batch.goods_receipt)}>Legacy receipt</span>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Serials</dt>
            <dd class="mt-1 text-sm text-thamani-ink">
              <button
                type="button"
                phx-click={@batch.serials != [] && "toggle_batch_serials"}
                disabled={@batch.serials == []}
                class="flex items-center gap-1 text-sm font-semibold text-thamani-forest disabled:cursor-default"
                aria-expanded={to_string(@serials_expanded)}
              >
                {if @batch.serials == [], do: "—", else: length(@batch.serials)}
                <.icon
                  :if={@batch.serials != []}
                  name="hero-chevron-down"
                  class={[
                    "size-3.5 transition-transform duration-200",
                    @serials_expanded && "rotate-180"
                  ]}
                />
              </button>
            </dd>
          </div>
        </dl>

        <div id="batch-status" class="mt-5 border-t border-thamani-stone pt-4">
          <div class="flex flex-wrap items-center gap-3">
            <span class="text-xs font-medium text-thamani-pewter">Status</span>
            <.status_badge status={@batch.status} label={status_label(@batch.status)} />
          </div>
        </div>

        <div
          :if={@batch.serials != [] and @serials_expanded}
          class="mt-5 grid gap-1.5 border-t border-thamani-stone pt-4 sm:grid-cols-3 lg:grid-cols-4"
        >
          <span
            :for={serial <- @batch.serials}
            class="truncate rounded border border-thamani-stone bg-td-surface px-2 py-1 font-mono text-xs font-medium text-thamani-forest"
            title={serial}
          >
            {serial}
          </span>
        </div>
      </section>

      <section
        id="batch-trail"
        class="mt-5 rounded-2xl border border-thamani-stone bg-td-surface p-5 sm:p-6"
      >
        <h2 class="text-base font-medium tracking-tight text-thamani-forest">Trail</h2>
        <ol class="mt-4">
          <.trail_step icon="hero-arrow-down-tray" title="Received">
            <%= if receipt = @batch.goods_receipt do %>
              <p class="font-medium text-thamani-evergreen">
                {receipt.origin_company || "Unknown origin"}
              </p>
              <p :if={receipt.origin_gln} class="mt-0.5 tracking-tight tabular-nums">
                GLN {receipt.origin_gln}
              </p>
              <p class="mt-0.5">{Calendar.strftime(receipt.received_at, "%d %b %Y")}</p>
              <.link
                navigate={~p"/distributor/receiving/#{receipt.id}"}
                class="mt-1 inline-flex font-medium text-thamani-forest hover:underline"
              >
                {receipt.number}
              </.link>
            <% else %>
              No goods receipt on record for this batch.
            <% end %>
          </.trail_step>
          <.trail_step icon="hero-truck" title="Shipped">
            <p :if={@trail_shipments == []}>This batch hasn't been shipped onward.</p>
            <ul :if={@trail_shipments != []} class="space-y-3">
              <li :for={%{shipment: shipment, unit_count: unit_count} <- @trail_shipments}>
                <.link
                  navigate={~p"/distributor/shipments/#{shipment.id}"}
                  class="font-medium text-thamani-forest hover:underline"
                >
                  {shipment.destination_company || "Unknown destination"}
                </.link>
                <p class="mt-0.5">
                  {count_phrase(unit_count, "unit")} · {Phoenix.Naming.humanize(shipment.status)}
                </p>
                <p :if={shipment.destination_gln} class="mt-0.5 tracking-tight tabular-nums">
                  GLN {shipment.destination_gln}
                </p>
              </li>
            </ul>
          </.trail_step>
          <.trail_step icon="hero-clock" title="Status" last?={true}>
            <p :if={@trail_events == []}>No status changes recorded yet.</p>
            <ul :if={@trail_events != []} class="space-y-3">
              <li :for={event <- @trail_events}>
                <p class="font-medium text-thamani-evergreen">
                  {humanize_step(event.payload["bizStep"])}
                </p>
                <p class="mt-0.5">
                  {humanize_step(event.payload["disposition"])} · {Calendar.strftime(
                    event.occurred_at,
                    "%d %b %Y"
                  )}
                </p>
              </li>
            </ul>
          </.trail_step>
        </ol>
      </section>
    </Layouts.distributor_shell>
    """
  end
end
