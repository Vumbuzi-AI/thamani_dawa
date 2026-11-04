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
    ~H"""
    <.modal id="lab-report-modal" show on_cancel={@on_close}>
      <div class="no-print mb-4">
        <h2 class="text-lg font-semibold text-base-content">Laboratory Report</h2>
        <p class="text-xs text-base-content/60">
          Ready to print for {@patient.full_name} — lab order #{@lab_order.id}
        </p>
      </div>

      <div id={"lab-report-#{@lab_order.id}"} class="printable-lab-report">
        <header class="text-center mb-5">
          <img src="/images/logo.png" alt="Thamani Dawa" class="mx-auto mb-2 size-12 object-contain" />
          <p class="font-semibold text-thamani-forest">{@site.name}</p>
          <h1 class="mt-1 text-base font-bold uppercase tracking-wide text-thamani-forest">
            Laboratory Report
          </h1>
        </header>

        <table class="w-full border-collapse border-2 border-black text-xs mb-5">
          <tbody>
            <tr>
              <td class="border border-black px-3 py-1.5 font-semibold w-1/4">Patient</td>
              <td class="border border-black px-3 py-1.5 w-1/4">{@patient.full_name}</td>
              <td class="border border-black px-3 py-1.5 font-semibold w-1/4">Lab order #</td>
              <td class="border border-black px-3 py-1.5 w-1/4">{@lab_order.id}</td>
            </tr>
            <tr>
              <td class="border border-black px-3 py-1.5 font-semibold">Gender / Age</td>
              <td class="border border-black px-3 py-1.5">
                {@patient.gender} · {Patient.age(@patient)}
              </td>
              <td class="border border-black px-3 py-1.5 font-semibold">Requested on</td>
              <td class="border border-black px-3 py-1.5">
                {Calendar.strftime(@lab_order.inserted_at, "%d %b %Y")}
              </td>
            </tr>
            <tr>
              <td class="border border-black px-3 py-1.5 font-semibold">Prescriber</td>
              <td class="border border-black px-3 py-1.5">{@lab_order.prescriber_name || "—"}</td>
              <td class="border border-black px-3 py-1.5 font-semibold">Urgency</td>
              <td class="border border-black px-3 py-1.5">
                {Phoenix.Naming.humanize(@lab_order.urgency || "routine")}
              </td>
            </tr>
          </tbody>
        </table>

        <table class="w-full border-collapse border-2 border-black text-xs">
          <thead>
            <tr>
              <th class="border border-black px-3 py-1.5 text-left">Test</th>
              <th class="border border-black px-3 py-1.5 text-left">Result</th>
              <th class="border border-black px-3 py-1.5 text-left">Performed by</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={result <- @results}>
              <td class="border border-black px-3 py-1.5 align-top font-medium">
                {test_name(result)}
              </td>
              <td class="border border-black px-3 py-1.5 align-top">
                {result_summary(result)}
              </td>
              <td class="border border-black px-3 py-1.5 align-top">
                {user_name(result.performed_by)}
              </td>
            </tr>
          </tbody>
        </table>

        <div class="mt-10 text-xs">
          <p class="font-semibold text-thamani-forest">Lab Technologist</p>
          <p class="mt-6 border-t border-black w-48"></p>
        </div>
      </div>

      <div class="no-print mt-6 pt-4">
        <.button
          type="button"
          variant="primary"
          onclick="window.print()"
          class="w-full flex items-center justify-center gap-1.5"
        >
          <.icon name="hero-printer" class="w-4 h-4" /> Print Report
        </.button>
      </div>
    </.modal>
    """
  end

  defp test_name(%{lab_test: %{name: name}}), do: name
  defp test_name(_), do: "(unknown test)"

  defp user_name(%{name: name}), do: name
  defp user_name(_), do: "—"

  defp result_summary(%{results: results}) when results == %{}, do: "No results recorded yet."

  defp result_summary(%{results: results}) do
    Enum.map_join(results, "; ", fn {key, %{"value" => value}} ->
      "#{Phoenix.Naming.humanize(key)}: #{format_value(value)}"
    end)
  end

  defp format_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(value), do: to_string(value)
end
