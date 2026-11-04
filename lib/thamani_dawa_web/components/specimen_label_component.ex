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
        "printable-batch-label border border-thamani-stone rounded-2xl p-5 bg-thamani-snow shadow-none",
        @class
      ]}
    >
      <div class="flex flex-col sm:flex-row items-center gap-6">
        <div class="flex flex-col items-center shrink-0">
          <canvas
            id={"datamatrix-canvas-specimen-#{@specimen.id}"}
            phx-hook="DataMatrix"
            data-text={@gs1_text}
            class="w-32 h-32 bg-white p-1 rounded-xl border border-thamani-stone"
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
  Renders a modal dialog containing the GS1 Data Matrix specimen label and
  print controls.
  """
  attr :specimen, :map, required: true
  attr :patient, Patient, required: true
  attr :on_close, :any, required: true

  def specimen_label_modal(assigns) do
    ~H"""
    <.modal id="specimen-label-modal" show on_cancel={@on_close}>
      <div class="no-print mb-4">
        <h2 class="text-lg font-semibold text-base-content">Specimen GS1 Data Matrix Label</h2>
        <p class="text-xs text-base-content/60">
          Ready to scan & print for specimen {@specimen.specimen_number}
        </p>
      </div>

      <.specimen_label_card specimen={@specimen} patient={@patient} />

      <div class="no-print mt-6 pt-4">
        <.button
          type="button"
          variant="primary"
          onclick="window.print()"
          class="w-full flex items-center justify-center gap-1.5"
        >
          <.icon name="hero-printer" class="w-4 h-4" /> Print Label
        </.button>
      </div>
    </.modal>
    """
  end

  defp specimen_test_names(specimen) do
    Enum.map_join(specimen.lab_order_results, ", ", fn result ->
      case result.lab_test do
        %{name: name} -> name
        _ -> "(unknown test)"
      end
    end)
  end
end
