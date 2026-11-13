defmodule ThamaniDawaWeb.ProductLive.Import do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Products.Importer

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:step, :upload)
     |> assign(:filename, nil)
     |> assign(:headers, nil)
     |> assign(:rows, nil)
     |> assign(:mapping, nil)
     |> assign(:preview, nil)
     |> assign(:summary, nil)
     |> assign(:upload_error, nil)
     |> allow_upload(:csv_file, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    case socket.assigns.uploads.csv_file.entries do
      [] ->
        {:noreply, assign(socket, :upload_error, "Choose a CSV file first.")}

      [entry | _] ->
        filename = entry.client_name

        [content] =
          consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
            {:ok, File.read!(path)}
          end)

        socket |> assign(:filename, filename) |> handle_parsed(Importer.parse(content))
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv_file, ref)}
  end

  def handle_event("confirm_mapping", %{"mapping" => mapping_params}, socket) do
    mapping =
      Map.new(mapping_params, fn {key, header} ->
        {String.to_existing_atom(key), if(header == "", do: nil, else: header)}
      end)

    missing_required =
      Importer.fields()
      |> Enum.filter(&(&1.required and is_nil(Map.get(mapping, &1.key))))

    socket = assign(socket, :mapping, mapping)

    if missing_required == [] do
      organization_id = socket.assigns.current_scope.organization_id

      preview =
        Importer.build_preview_rows(
          organization_id,
          socket.assigns.headers,
          socket.assigns.rows,
          mapping
        )

      {:noreply, socket |> assign(:preview, preview) |> assign(:step, :preview)}
    else
      labels = Enum.map_join(missing_required, ", ", & &1.label)

      {:noreply,
       put_flash(socket, :error, "Map these required fields before continuing: #{labels}.")}
    end
  end

  def handle_event("back_to_map", _params, socket) do
    {:noreply, socket |> assign(:preview, nil) |> assign(:step, :map)}
  end

  def handle_event("start_over", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :upload)
     |> assign(:filename, nil)
     |> assign(:headers, nil)
     |> assign(:rows, nil)
     |> assign(:mapping, nil)
     |> assign(:preview, nil)
     |> assign(:upload_error, nil)}
  end

  def handle_event("confirm_import", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Importer.import_rows(organization_id, socket.assigns.preview) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:step, :done)
         |> assign(:summary, %{created: count, total: length(socket.assigns.preview)})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Import failed partway through — please retry.")}
    end
  end

  defp handle_parsed(socket, {:ok, {headers, rows}}) do
    {:noreply,
     socket
     |> assign(:headers, headers)
     |> assign(:rows, rows)
     |> assign(:mapping, Importer.auto_map_columns(headers))
     |> assign(:step, :map)
     |> assign(:upload_error, nil)}
  end

  defp handle_parsed(socket, {:error, :empty_file}) do
    {:noreply, assign(socket, :upload_error, "That file doesn't have any product rows in it.")}
  end

  defp handle_parsed(socket, {:error, :malformed_csv}) do
    {:noreply, assign(socket, :upload_error, "Couldn't read that file as CSV.")}
  end

  defp status_label(:valid), do: "Ready to import"
  defp status_label(:invalid), do: "Needs fixing"
  defp status_label(:duplicate_in_file), do: "Duplicate in file"
  defp status_label(:exists_in_catalogue), do: "Already in catalogue — skipped"

  defp status_classes(:valid), do: "bg-green-50 text-green-700 border-green-200"
  defp status_classes(:invalid), do: "bg-red-50 text-red-700 border-red-200"

  defp status_classes(status) when status in [:duplicate_in_file, :exists_in_catalogue],
    do: "bg-amber-50 text-amber-700 border-amber-200"

  defp row_name(attrs), do: attrs["generic_name"] || attrs["brand_name"] || "(unnamed)"

  defp row_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp valid_count(preview), do: Enum.count(preview, &(&1.status == :valid))

  defp step_number(:upload), do: 1
  defp step_number(:map), do: 2
  defp step_number(step) when step in [:preview, :done], do: 3

  defp step_state(current_step, index) do
    cond do
      index < step_number(current_step) -> :done
      index == step_number(current_step) -> :current
      true -> :upcoming
    end
  end

  attr :step, :atom, required: true

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center gap-3 border-b border-thamani-stone pb-5">
      <.step_item index={1} label="Upload file" state={step_state(@step, 1)} />
      <div class="h-px flex-1 bg-thamani-stone" />
      <.step_item index={2} label="Map columns" state={step_state(@step, 2)} />
      <div class="h-px flex-1 bg-thamani-stone" />
      <.step_item index={3} label="Review & import" state={step_state(@step, 3)} />
    </div>
    """
  end

  attr :index, :integer, required: true
  attr :label, :string, required: true
  attr :state, :atom, required: true

  defp step_item(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5">
      <span class={[
        "flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
        @state == :done && "bg-thamani-forest text-thamani-snow",
        @state == :current && "bg-thamani-forest text-thamani-snow",
        @state == :upcoming && "bg-thamani-stone text-thamani-pewter"
      ]}>
        <.icon :if={@state == :done} name="hero-check" class="size-4" />
        <span :if={@state != :done}>{@index}</span>
      </span>
      <span class={[
        "text-sm font-medium whitespace-nowrap",
        @state == :upcoming && "text-thamani-pewter",
        @state != :upcoming && "text-thamani-forest"
      ]}>
        {@label}
      </span>
    </div>
    """
  end

  defp import_checklist_item(assigns) do
    ~H"""
    <li class="flex items-start gap-2 text-sm text-thamani-forest">
      <.icon name="hero-check-circle" class="mt-0.5 size-4 shrink-0 text-thamani-forest/70" />
      {render_slot(@inner_block)}
    </li>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/products"}>
      <.header icon="hero-arrow-up-tray">
        Import products
        <:subtitle>Bring in your product catalogue from a spreadsheet.</:subtitle>
        <:actions>
          <.button variant="ghost" navigate={~p"/org/products"}>Cancel</.button>
        </:actions>
      </.header>

      <div class="rounded-2xl ff-surface-card p-5 sm:p-6">
        <.step_indicator step={@step} />

        <div :if={@step == :upload} class="mt-6 grid grid-cols-1 gap-6 xl:grid-cols-[1fr_360px]">
          <div class="flex h-full flex-col gap-4">
            <form
              id="upload-form"
              phx-submit="upload"
              phx-change="validate"
              class="flex flex-1 flex-col gap-4"
            >
              <div
                class="group relative flex flex-1 flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-thamani-stone bg-thamani-snow px-8 py-12 text-center transition-colors hover:border-thamani-forest/40 hover:bg-thamani-canvas"
                phx-drop-target={@uploads.csv_file.ref}
              >
                <span class="flex size-12 items-center justify-center rounded-full bg-thamani-lime/30 text-thamani-forest">
                  <.icon name="hero-arrow-up-tray" class="size-6" />
                </span>
                <div>
                  <p class="text-sm font-medium text-thamani-forest">
                    <span class="font-semibold text-thamani-forest underline">Click to upload</span>
                    or drag and drop
                  </p>
                  <p class="mt-1 text-xs text-thamani-pewter">CSV only, up to 5MB.</p>
                </div>
                <.live_file_input
                  upload={@uploads.csv_file}
                  class="absolute inset-0 size-full cursor-pointer opacity-0"
                  aria-label="Choose a CSV file"
                />

                <div :for={entry <- @uploads.csv_file.entries} class="w-full text-left">
                  <div class="flex items-center justify-between rounded-lg border border-thamani-stone bg-white px-3 py-2">
                    <span class="flex items-center gap-2 truncate text-sm text-thamani-forest">
                      <.icon
                        name="hero-document-text"
                        class="size-4 shrink-0 text-thamani-forest/70"
                      />
                      {entry.client_name}
                    </span>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="relative z-10 shrink-0 text-xs font-medium text-red-600"
                    >
                      Remove
                    </button>
                  </div>
                  <p
                    :for={err <- upload_errors(@uploads.csv_file, entry)}
                    class="mt-1 text-xs text-red-700"
                  >
                    {error_to_string(err)}
                  </p>
                </div>
              </div>

              <p :if={@upload_error} class="text-sm text-red-700">{@upload_error}</p>

              <.button
                :if={@uploads.csv_file.entries != []}
                type="submit"
                variant="primary"
              >
                Continue
              </.button>
            </form>

            <div class="mt-auto flex items-center justify-between gap-4 rounded-xl bg-thamani-stone/40 p-4">
              <div class="flex items-center gap-3">
                <span class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-white text-thamani-forest ring-1 ring-thamani-stone">
                  <.icon name="hero-table-cells" class="size-5" />
                </span>
                <div>
                  <p class="text-sm font-medium text-thamani-forest">Need a starting point?</p>
                  <p class="text-xs text-thamani-pewter">
                    Download our template with the columns we recognise.
                  </p>
                </div>
              </div>
              <.button variant="ghost" href={~p"/org/products/import/template"}>
                <.icon name="hero-arrow-down-tray" class="size-4" /> Download template
              </.button>
            </div>
          </div>

          <div class="space-y-4">
            <div class="rounded-xl bg-thamani-stone/40 p-4">
              <p class="flex items-center gap-2 text-sm font-semibold text-thamani-forest">
                <.icon name="hero-information-circle" class="size-4.5 text-thamani-forest/70" />
                Before you import
              </p>
              <p class="mt-1 text-xs text-thamani-pewter">
                Your file's columns don't need to match these names — you'll map them on the next step. These are the fields we can bring in:
              </p>
              <ul class="mt-3 space-y-2">
                <.import_checklist_item>Generic or brand name</.import_checklist_item>
                <.import_checklist_item>GTIN</.import_checklist_item>
                <.import_checklist_item>Price</.import_checklist_item>
                <.import_checklist_item>Unit of measure</.import_checklist_item>
                <.import_checklist_item>
                  Category, manufacturer, reorder level (optional)
                </.import_checklist_item>
                <.import_checklist_item>
                  Over-the-counter / dangerous drug flags (optional)
                </.import_checklist_item>
              </ul>
            </div>

            <div class="rounded-xl bg-thamani-lime/15 p-4">
              <p class="flex items-center gap-2 text-sm font-semibold text-thamani-forest">
                <.icon name="hero-light-bulb" class="size-4.5 text-thamani-forest/70" /> Tip
              </p>
              <p class="mt-1 text-xs text-thamani-forest">
                This brings in your product catalogue only — not stock quantities or batches. Add opening stock afterwards from each product's page.
              </p>
            </div>
          </div>
        </div>

        <div :if={@step == :map} class="mt-6 space-y-4">
          <div>
            <p class="text-base font-semibold text-thamani-forest">Map your columns</p>
            <p class="text-sm text-thamani-pewter">
              Match each of our fields to a column from your file. Fields marked required must be mapped to continue.
            </p>
          </div>

          <div class="grid grid-cols-1 gap-6 xl:grid-cols-2">
            <div class="rounded-xl bg-thamani-stone/40 p-4">
              <p class="flex items-center gap-2 text-sm font-semibold text-thamani-forest">
                <.icon name="hero-table-cells" class="size-4.5 text-thamani-forest/70" /> File preview
              </p>
              <p class="mt-1 truncate text-xs text-thamani-pewter" title={@filename}>
                {@filename}
              </p>
              <p class="text-xs text-thamani-pewter">
                {length(@rows)} rows &bull; {length(@headers)} columns
              </p>

              <div class="mt-3 overflow-x-auto rounded-lg border border-thamani-stone bg-white">
                <table class="text-xs">
                  <thead class="bg-thamani-stone/40 text-left font-medium text-thamani-forest">
                    <tr>
                      <th :for={header <- @headers} class="whitespace-nowrap px-2.5 py-1.5">
                        {header}
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-thamani-stone">
                    <tr :for={row <- Enum.take(@rows, 10)}>
                      <td
                        :for={cell <- row}
                        class="max-w-32 truncate px-2.5 py-1.5 text-thamani-pewter"
                      >
                        {cell}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p :if={length(@rows) > 10} class="mt-1.5 text-xs text-thamani-pewter">
                + {length(@rows) - 10} more rows
              </p>
            </div>

            <form id="mapping-form" phx-submit="confirm_mapping">
              <div class="overflow-hidden rounded-xl border border-thamani-stone">
                <table class="w-full text-sm">
                  <thead class="bg-thamani-stone/40 text-left text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                    <tr>
                      <th class="px-4 py-2.5">Product field (in system)</th>
                      <th class="px-4 py-2.5">Column from your file</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-thamani-stone bg-white">
                    <tr :for={field <- Importer.fields()}>
                      <td class="px-4 py-2.5 text-sm font-medium text-thamani-forest">
                        {field.label}
                        <span :if={field.required} class="text-red-600">&nbsp;*</span>
                      </td>
                      <td class="px-4 py-2.5">
                        <select
                          name={"mapping[#{field.key}]"}
                          class="thamani-input w-full"
                          required={field.required}
                        >
                          <option value="" selected={is_nil(Map.get(@mapping, field.key))}>
                            — not in file —
                          </option>
                          <option
                            :for={header <- @headers}
                            value={header}
                            selected={Map.get(@mapping, field.key) == header}
                          >
                            {header}
                          </option>
                        </select>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div class="flex gap-3 pt-4">
                <.button type="submit" variant="primary">Preview import</.button>
                <.button type="button" variant="ghost" phx-click="start_over">Start over</.button>
              </div>
            </form>
          </div>
        </div>

        <div :if={@step == :preview} class="mt-6 space-y-4">
          <p class="text-sm text-thamani-pewter">
            {valid_count(@preview)} of {length(@preview)} rows are ready to import.
            Rows marked "Needs fixing" or already in your catalogue will be skipped —
            re-upload a corrected file for those if needed.
          </p>

          <div class="overflow-x-auto rounded-xl border border-thamani-stone">
            <table class="w-full text-sm">
              <thead class="bg-thamani-canvas text-left text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                <tr>
                  <th class="px-3 py-2">Row</th>
                  <th class="px-3 py-2">Name</th>
                  <th class="px-3 py-2">GTIN</th>
                  <th class="px-3 py-2">Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-thamani-stone">
                <tr :for={row <- @preview}>
                  <td class="px-3 py-2 tabular-nums text-thamani-pewter">{row.index}</td>
                  <td class="px-3 py-2 text-thamani-forest">{row_name(row.attrs)}</td>
                  <td class="px-3 py-2 tabular-nums text-thamani-forest">{row.attrs["gtin"]}</td>
                  <td class="px-3 py-2">
                    <span class={[
                      "inline-flex rounded-full border px-2 py-0.5 text-xs font-medium",
                      status_classes(row.status)
                    ]}>
                      {status_label(row.status)}
                    </span>
                    <p :if={row.status == :invalid} class="mt-1 text-xs text-red-700">
                      {row_errors(row.changeset)}
                    </p>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="flex gap-3">
            <.button
              type="button"
              variant="primary"
              phx-click="confirm_import"
              disabled={valid_count(@preview) == 0}
            >
              Import {valid_count(@preview)} products
            </.button>
            <.button type="button" variant="ghost" phx-click="back_to_map">Back</.button>
          </div>
        </div>

        <div :if={@step == :done} class="mt-6 max-w-3xl space-y-4">
          <div class="rounded-xl border border-green-200 bg-green-50 p-4">
            <p class="text-sm font-medium text-green-800">
              Imported {@summary.created} of {@summary.total} rows.
            </p>
          </div>
          <.button variant="primary" navigate={~p"/org/products"}>Back to products</.button>
        </div>
      </div>
    </Layouts.org_shell>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp error_to_string(:too_many_files), do: "Choose only one file."
  defp error_to_string(:not_accepted), do: "Must be a CSV file."
  defp error_to_string(_), do: "Couldn't accept this file."
end
