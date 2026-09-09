defmodule ThamaniDawaWeb.SerialLabelComponents do
  @moduledoc """
  The label artwork of ui.md §10, as function components.

  Every label — on screen, downloaded, or printed — is built from one
  `ThamaniDawa.Serialisation.Label`. The struct is serialised into the wrapper's
  `data-label` attribute, and the `SerialLabel` JS hook draws the download and
  print artifacts from that same payload, so the three can never disagree.

  Identifiers render as strings in a monospaced face: a GTIN or SSCC that lost
  its leading zero to number formatting is a different code (§10).
  """

  use Phoenix.Component

  alias ThamaniDawa.Serialisation.Label
  alias ThamaniDawaWeb.CoreComponents

  attr :id, :string, required: true
  attr :label, Label, required: true
  attr :class, :any, default: nil
  slot :actions, doc: "buttons rendered above the artwork, e.g. Download and Print"

  @doc "One pallet or shipper SSCC label, with its Data Matrix and AI lines."
  def sscc_label(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="SerialLabel"
      data-label={Jason.encode!(payload(@label))}
      class={["group", @class]}
    >
      <div :if={@actions != []} class="mb-3 flex flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>

      <article class="mx-auto w-full max-w-sm border-2 border-black bg-white text-black">
        <div :if={@label.from_address || @label.to_address} class="grid grid-cols-2">
          <div class="border-r-2 border-b-2 border-black p-3">
            <p class="text-xs font-bold">From Address</p>
            <p class="mt-1 text-xs leading-snug">{@label.from_company_name}</p>
            <p class="text-xs leading-snug">{@label.from_address}</p>
          </div>
          <div class="border-b-2 border-black p-3">
            <p class="text-xs font-bold">To Address</p>
            <p class="mt-1 text-xs leading-snug">{@label.to_company_name}</p>
            <p class="text-xs leading-snug">{@label.to_address}</p>
          </div>
        </div>

        <dl class="grid grid-cols-2 gap-x-3 gap-y-2 p-3">
          <.label_field name="SSCC" value={@label.sscc} mono />
          <.label_field name="Quantity" value={@label.quantity} align="right" />
          <.label_field name="Content" value={@label.gtin} mono />
          <.label_field name="Expiry" value={Label.ai_date(@label.expiry)} align="right" mono />
          <.label_field name="Batch/Lot" value={@label.batch} />
          <.label_field
            name="Prod date"
            value={Label.ai_date(@label.production)}
            align="right"
            mono
          />
          <.label_field :if={@label.serial} name="Shipper serial" value={@label.serial} mono />
          <.label_field :if={@label.order_number} name="Order number" value={@label.order_number} />
        </dl>

        <div :if={@label.material_description} class="px-3 pb-2">
          <p class="text-[0.6rem] uppercase tracking-wide text-neutral-600">
            Material description
          </p>
          <p class="text-sm font-bold leading-tight">{@label.material_description}</p>
        </div>

        <div :if={@label.customer_part_number} class="px-3 pb-2">
          <p class="text-[0.6rem] uppercase tracking-wide text-neutral-600">Cust part no.</p>
          <p class="text-sm font-bold">{@label.customer_part_number}</p>
        </div>

        <div class="flex items-start gap-3 border-t-2 border-black p-3">
          <figure class="shrink-0 text-center">
            <canvas
              data-role="symbol"
              class="size-24 bg-white"
              role="img"
              aria-label="GS1 Data Matrix for SSCC #{@label.sscc}"
            ></canvas>
            <figcaption class="mt-1 text-[0.55rem] font-semibold uppercase tracking-wide text-neutral-600">
              GS1 Data Matrix
            </figcaption>
          </figure>
          <div>
            <p class="sr-only">GS1 application identifiers encoded in the Data Matrix</p>
            <p :for={line <- Label.ai_lines(@label)} class="font-mono text-[0.65rem] leading-tight">
              {line}
            </p>
          </div>
        </div>

        <p :if={@label.sequence} class="px-3 pb-2 text-right text-xs font-bold">
          {sequence_text(@label.sequence)}
        </p>
      </article>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, Label, required: true

  @doc "One primary serial card: the serial, its Data Matrix, and its AI lines."
  def primary_serial_card(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="SerialLabel"
      data-label={Jason.encode!(payload(@label))}
      class="rounded-xl border border-emerald-100 bg-emerald-50/40 p-4"
    >
      <p class="font-mono text-sm font-semibold text-slate-900">{@label.serial}</p>
      <p class="text-xs text-slate-500">serial</p>

      <div class="mt-3 flex items-start gap-3">
        <canvas data-role="symbol" class="size-24 shrink-0 bg-white" aria-hidden="true"></canvas>
        <div>
          <p
            :for={line <- Label.ai_lines(@label)}
            class="font-mono text-[0.65rem] leading-tight text-slate-700"
          >
            {line}
          </p>
        </div>
      </div>

      <button
        type="button"
        data-label-action="download"
        class="mt-3 inline-flex items-center gap-1.5 rounded-full bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2"
      >
        <CoreComponents.icon name="hero-arrow-down-tray" class="size-3.5" />
        Download<span class="sr-only">serial {@label.serial}</span>
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :serial, :string, default: nil

  @doc "The Download and Print pair used above a full label."
  def label_actions(assigns) do
    ~H"""
    <button
      type="button"
      data-label-action="download"
      class="inline-flex items-center gap-1.5 rounded-full bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2"
    >
      <CoreComponents.icon name="hero-arrow-down-tray" class="size-3.5" /> Download
      <span class="sr-only">{@label}</span>
    </button>
    <button
      type="button"
      data-label-action="print"
      class="inline-flex items-center gap-1.5 rounded-full bg-thamani-forest px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-thamani-forest/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
    >
      <CoreComponents.icon name="hero-printer" class="size-3.5" /> Print
      <span class="sr-only">{@label}</span>
    </button>
    """
  end

  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :align, :string, default: "left"
  attr :mono, :boolean, default: false

  defp label_field(assigns) do
    ~H"""
    <div :if={@value not in [nil, ""]} class={@align == "right" && "text-right"}>
      <dt class="text-[0.6rem] uppercase tracking-wide text-neutral-600">{@name}</dt>
      <dd class={["text-sm font-bold leading-tight", @mono && "font-mono"]}>{@value}</dd>
    </div>
    """
  end

  defp sequence_text({index, total}), do: "PALLET #{index}/#{total}"
  defp sequence_text(other) when is_binary(other), do: other

  # What the JS hook redraws for download and print. Keyed exactly like the
  # on-screen markup above so the two cannot drift.
  defp payload(%Label{} = label) do
    %{
      sscc: label.sscc,
      gtin: label.gtin,
      quantity: label.quantity,
      batch: label.batch,
      expiry: Label.ai_date(label.expiry),
      production: Label.ai_date(label.production),
      serial: label.serial,
      order_number: label.order_number,
      customer_part_number: label.customer_part_number,
      material_description: label.material_description,
      from_company_name: label.from_company_name,
      from_address: label.from_address,
      to_company_name: label.to_company_name,
      to_address: label.to_address,
      sequence: label.sequence && sequence_text(label.sequence),
      gs1_text: Label.gs1_text(label),
      ai_lines: Label.ai_lines(label),
      filename: Label.filename(label)
    }
  end
end
