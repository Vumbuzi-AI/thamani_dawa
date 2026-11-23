defmodule ThamaniDawaWeb.SpecimenLabelComponent do
  @moduledoc """
  Components for displaying and printing GS1 Data Matrix labels for lab
  specimens (patient GSRN + specimen SRIN).
  """
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.GS1Encoder
  alias ThamaniDawa.Patients.Patient

  @doc """
  Renders a printable GS1 Data Matrix specimen label card.
  """
  attr :specimen, :map, required: true
  attr :patient, Patient, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: ""

  def specimen_label_card(assigns) do
    assigns = assign_new(assigns, :id, fn -> "specimen-label-#{assigns.specimen.id}" end)

    assigns =
      assign(
        assigns,
        :gs1_text,
        GS1Encoder.specimen_label_text(assigns.patient, assigns.specimen)
      )

    ~H"""
    <div
      id={@id}
      class={[
        "printable-batch-label border border-thamani-stone rounded-2xl p-5 bg-thamani-surface shadow-none",
        @class
      ]}
    >
      <div class="flex flex-col sm:flex-row items-center gap-6">
        <div class="flex flex-col items-center shrink-0">
          <canvas
            id={"datamatrix-canvas-specimen-#{@specimen.id}"}
            phx-hook="DataMatrix"
            data-text={@gs1_text}
            class="w-32 h-32 bg-td-surface p-1 rounded-xl border border-thamani-stone"
          ></canvas>
          <span class="text-[10px] text-thamani-pewter font-mono mt-1">DataMatrix</span>
        </div>

        <div class="flex-1 min-w-0 space-y-2 w-full">
          <div>
            <div class="text-xs uppercase tracking-wider text-thamani-pewter font-semibold">
              Patient
            </div>
            <div class="font-semibold text-base text-thamani-forest truncate">
              {@patient.full_name}
            </div>
          </div>

          <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
            <div>
              <span class="text-thamani-pewter">DOB:</span>
              <span class="font-medium ml-1">{@patient.date_of_birth}</span>
            </div>
            <div>
              <span class="text-thamani-pewter">Age / Gender:</span>
              <span class="font-medium ml-1">{Patient.age(@patient)} · {@patient.gender}</span>
            </div>
            <div class="col-span-2">
              <span class="text-thamani-pewter">Specimen:</span>
              <span class="code-pill ml-1">{@specimen.specimen_number}</span>
              <span class="ml-1">({Phoenix.Naming.humanize(@specimen.specimen_type)})</span>
            </div>
            <div class="col-span-2">
              <span class="text-thamani-pewter">Tests:</span>
              <span class="font-medium ml-1">{specimen_test_names(@specimen)}</span>
            </div>
          </div>

          <div class="border-t-2 border-black pt-1.5 mt-2">
            <span class="text-[11px] font-bold">
              (8018) {@patient.gsrn} · (8019) {@specimen.specimen_number}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the Print specimen label dialog (Doop 5O8udg27kd): a label preview
  with the GS1 Data Matrix, label size and copies, and Cancel / Print label.
  """
  attr :specimen, :map, required: true
  attr :patient, Patient, required: true
  attr :lab_order, :map, default: nil
  attr :on_close, :any, required: true

  def specimen_label_modal(assigns) do
    assigns =
      assign(
        assigns,
        :gs1_text,
        GS1Encoder.specimen_label_text(assigns.patient, assigns.specimen)
      )

    ~H"""
    <.modal
      id="specimen-label-modal"
      show
      title="Print specimen label"
      subtitle="A GS1 label for this tube, ready for your label printer."
      on_cancel={@on_close}
    >
      <div class="td-modal-form">
        <div id={"specimen-label-#{@specimen.id}"} class="td-label-preview printable-batch-label">
          <canvas
            id={"datamatrix-canvas-specimen-#{@specimen.id}"}
            phx-hook="DataMatrix"
            data-text={@gs1_text}
          ></canvas>
          <div class="td-label-preview-body">
            <span class="td-label-preview-title">
              {@patient.full_name} · {Phoenix.Naming.humanize(@specimen.specimen_type)}
            </span>
            <span class="td-mono">
              (8018){@patient.gsrn}(21){@specimen.specimen_number}
            </span>
            <span>
              <span :if={@lab_order}>{ThamaniDawa.LabOrders.reference(@lab_order)} · </span>collected {collected_text(
                @specimen
              )}
            </span>
          </div>
        </div>
        <div class="td-fgrid is-2 no-print">
          <.input
            type="select"
            id="specimen-label-size"
            name="label_size"
            label="Label size"
            value="38x19"
            options={[{"38 × 19 mm tube label", "38x19"}]}
          />
          <.input
            type="number"
            id="specimen-label-copies"
            name="copies"
            label="Copies"
            value="1"
            min="1"
          />
        </div>
      </div>
      <:footer>
        <.td_button type="button" phx-click={@on_close}>Cancel</.td_button>
        <.td_button
          id="print-specimen-label"
          type="button"
          variant="primary"
          glyph="printer"
          onclick="window.print()"
        >
          Print label
        </.td_button>
      </:footer>
    </.modal>
    """
  end

  defp collected_text(%{collected_at: %DateTime{} = at}),
    do: ThamaniDawaWeb.TimeFormat.date(at)

  defp collected_text(_), do: "—"

  defp specimen_test_names(specimen) do
    Enum.map_join(specimen.lab_order_results, ", ", fn result ->
      case result.lab_test do
        %{name: name} -> name
        _ -> "(unknown test)"
      end
    end)
  end
end
