defmodule ThamaniDawaWeb.LabReportComponent do
  @moduledoc """
  Printable laboratory report: site header, patient/order info, and a table
  of completed test results for a lab order.
  """
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.Patients.Patient

  @doc """
  Renders a modal dialog containing the printable lab report and print
  controls.
  """
  attr :lab_order, :map, required: true
  attr :patient, Patient, required: true
  attr :site, :map, required: true
  attr :results, :list, required: true
  attr :on_close, :any, required: true

  def lab_report_modal(assigns) do
    assigns =
      assigns
      |> assign(:rows, report_rows(assigns.results))
      |> assign(:reported_at, reported_at(assigns.results))
      |> assign(:performers, performers(assigns.results))

    ~H"""
    <.modal
      id="lab-report-modal"
      show
      title="Print results"
      subtitle={"Preview of the report for #{@patient.full_name}."}
      on_cancel={@on_close}
    >
      <div id={"lab-report-#{@lab_order.id}"} class="td-report printable-lab-report">
        <div class="td-report-head">
          <img src="/images/logo.png" alt="Thamani Dawa" />
          <span class="td-report-site">{@site.name}</span>
        </div>
        <dl class="td-report-kv">
          <div class="td-kv">
            <dt class="td-kv-label">Patient</dt>
            <dd class="td-kv-value">{@patient.full_name}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Order</dt>
            <dd class="td-kv-value is-mono">{ThamaniDawa.LabOrders.reference(@lab_order)}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Reported</dt>
            <dd class="td-kv-value">{ThamaniDawaWeb.TimeFormat.datetime(@reported_at)}</dd>
          </div>
        </dl>
        <table class="td-report-table">
          <thead>
            <tr>
              <th>Test</th>
              <th>Result</th>
              <th>Reference</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows}>
              <td>{row.label}</td>
              <td>{row.value}</td>
              <td>{row.reference}</td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan="3">No results recorded yet.</td>
            </tr>
          </tbody>
        </table>
        <dl class="td-report-kv is-2">
          <div class="td-kv">
            <dt class="td-kv-label">Performed by</dt>
            <dd class="td-kv-value">{@performers}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Prescriber</dt>
            <dd class="td-kv-value">{@lab_order.prescriber_name || "—"}</dd>
          </div>
        </dl>
      </div>
      <:footer>
        <.td_button type="button" phx-click={@on_close}>Close</.td_button>
        <.td_button
          id="print-lab-report"
          type="button"
          variant="primary"
          glyph="printer"
          onclick="window.print()"
        >
          Print
        </.td_button>
      </:footer>
    </.modal>
    """
  end

  defp report_rows(results) do
    Enum.flat_map(results, fn result ->
      values = result.results || %{}
      defs = field_definitions(result)

      case Map.to_list(values) do
        [] ->
          []

        [{key, entry}] ->
          [row(test_name(result), entry, defs[key])]

        entries ->
          Enum.map(entries, fn {key, entry} ->
            row(Phoenix.Naming.humanize(key), entry, defs[key])
          end)
      end
    end)
  end

  defp row(label, entry, definition) do
    definition = definition || %{}
    unit = definition["unit"] || ""
    value = entry |> entry_value() |> format_value()
    value = if unit != "" and value != "", do: "#{value} #{unit}", else: value

    %{label: label, value: value, reference: definition["reference"] || "—"}
  end

  defp entry_value(%{"value" => value}), do: value
  defp entry_value(value), do: value

  defp field_definitions(%{lab_test: %{field_definitions: defs}}) when is_map(defs), do: defs
  defp field_definitions(_), do: %{}

  defp reported_at(results) do
    results
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  defp performers(results) do
    results
    |> Enum.map(&user_name(&1.performed_by))
    |> Enum.reject(&(&1 == "—"))
    |> Enum.uniq()
    |> case do
      [] -> "—"
      names -> Enum.join(names, ", ")
    end
  end

  defp test_name(%{lab_test: %{name: name}}), do: name
  defp test_name(_), do: "(unknown test)"

  defp user_name(%{name: name}), do: name
  defp user_name(_), do: "—"

  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(value), do: to_string(value)
end
