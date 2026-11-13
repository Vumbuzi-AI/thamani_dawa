defmodule ThamaniDawaWeb.DistributorBillingLive.Invoice do
  @moduledoc """
  A printable invoice for a paid serialisation payment: issuer and
  bill-to details, the billed serials (with any folded-in buffer), VAT,
  total, payment reference, and a PAID stamp.

  Issuer and remittance details come from
  `config :thamani_dawa, :distributor_invoice_issuer` (placeholders until
  confirmed).
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.Billing
  alias ThamaniDawa.Organizations

  @empty_issuer %{name: "", address: "", email: "", pin: "", paybill: "", bank: ""}

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    payment = Billing.get_payment!(organization_id, id)

    if payment.status == "paid" do
      {:ok,
       socket
       |> assign(:page_title, "Invoice #{payment.invoice_number}")
       |> assign(:payment, payment)
       |> assign(:organization, Organizations.get_organization!(organization_id))
       |> assign(:issuer, issuer())}
    else
      {:ok,
       socket
       |> put_flash(:error, "Invoices are issued once a payment is confirmed.")
       |> push_navigate(to: ~p"/distributor/billing")}
    end
  end

  defp issuer do
    configured = Application.get_env(:thamani_dawa, :distributor_invoice_issuer, %{})
    Map.merge(@empty_issuer, Map.new(configured))
  end

  defp description("prepay"), do: "Serialisation bundle (prepay)"
  defp description("postpay"), do: "Serialisation usage (flex pay-as-you-go)"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/billing"}
    >
      <div class="no-print mb-4 flex flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/distributor/billing"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-thamani-forest hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to billing
        </.link>
        <.button id="print-serial-invoice" type="button" variant="primary" onclick="window.print()">
          <.icon name="hero-printer" class="size-4" /> Print invoice
        </.button>
      </div>

      <article
        id="distributor-serial-invoice"
        class="printable-invoice print-document relative mx-auto max-w-4xl rounded-xl bg-white p-6 text-thamani-ink shadow-sm ring-1 ring-thamani-stone sm:p-10"
      >
        <span
          id="invoice-paid-stamp"
          class="pointer-events-none absolute right-8 top-8 rotate-12 rounded-lg border-4 border-emerald-600 px-4 py-1 text-2xl font-black tracking-widest text-emerald-600 opacity-80"
        >
          PAID
        </span>

        <header
          id="invoice-header"
          class="grid gap-8 border-b border-thamani-stone pb-7 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-start"
        >
          <div id="invoice-issuer" class="min-w-0">
            <div class="mb-4 flex items-center gap-3">
              <img
                id="invoice-brand-logo"
                src="/images/logo.png"
                alt="Thamani Dawa"
                class="size-14 shrink-0 object-contain"
              />
              <div>
                <p class="text-xl font-semibold tracking-tight text-thamani-forest">{@issuer.name}</p>
                <p class="text-xs font-medium uppercase tracking-[0.14em] text-thamani-pewter">
                  Health systems
                </p>
              </div>
            </div>
            <p class="break-words text-sm text-thamani-pewter">{@issuer.address}</p>
            <p class="break-words text-sm text-thamani-pewter">{@issuer.email}</p>
            <p class="text-sm text-thamani-pewter">KRA PIN {@issuer.pin}</p>
          </div>
          <div id="invoice-metadata" class="grid content-start gap-2 sm:min-w-64 sm:text-right">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wide text-thamani-pewter">Invoice</p>
              <p
                id="invoice-number"
                class="break-all font-mono text-lg font-semibold text-thamani-forest"
              >
                {@payment.invoice_number}
              </p>
              <p id="invoice-issue-date" class="text-sm text-thamani-pewter">
                Issued {short_date(@payment.paid_at)}
              </p>
            </div>
          </div>
        </header>

        <section class="grid gap-6 border-b border-thamani-stone py-6 sm:grid-cols-2">
          <div id="invoice-bill-to" class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-wide text-thamani-pewter">Bill to</p>
            <p class="mt-1 font-medium text-thamani-ink">{@organization.name}</p>
            <p :if={@organization.gs1_company_prefix} class="text-sm text-thamani-pewter">
              GS1 prefix {@organization.gs1_company_prefix}
            </p>
          </div>
          <div id="invoice-payment-details" class="min-w-0 sm:text-right">
            <p class="text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
              Payment details
            </p>
            <p class="mt-1 text-sm text-thamani-ink">
              {if @payment.method == "mpesa", do: "M-Pesa", else: "Manual reference"}
            </p>
            <p class="break-all font-mono text-sm text-thamani-pewter">
              {@payment.manual_reference || @payment.provider_reference}
            </p>
          </div>
        </section>

        <table id="invoice-line-items" class="mt-6 w-full table-fixed text-sm">
          <thead>
            <tr class="border-b border-thamani-stone text-left text-xs uppercase tracking-wide text-thamani-pewter">
              <th class="w-[52%] pb-2 font-semibold">Description</th>
              <th class="w-[12%] pb-2 text-right font-semibold">Serials</th>
              <th class="w-[16%] pb-2 text-right font-semibold">Rate</th>
              <th class="w-[20%] pb-2 text-right font-semibold">Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr class="border-b border-thamani-stone">
              <td class="break-words py-3">{description(@payment.kind)}</td>
              <td class="py-3 text-right">{number(@payment.quantity)}</td>
              <td class="py-3 text-right">{kes(@payment.unit_price)}</td>
              <td class="py-3 text-right">
                {kes(Decimal.mult(@payment.unit_price, @payment.quantity))}
              </td>
            </tr>
            <tr :if={@payment.buffer_quantity > 0} class="border-b border-thamani-stone">
              <td class="break-words py-3">Buffer carried from previous cycle</td>
              <td class="py-3 text-right">{number(@payment.buffer_quantity)}</td>
              <td class="py-3 text-right">{kes(@payment.unit_price)}</td>
              <td class="py-3 text-right">
                {kes(Decimal.mult(@payment.unit_price, @payment.buffer_quantity))}
              </td>
            </tr>
          </tbody>
        </table>

        <dl id="invoice-totals" class="ml-auto mt-4 w-full max-w-xs space-y-1.5 text-sm">
          <div class="flex justify-between">
            <dt class="text-thamani-pewter">Subtotal</dt>
            <dd>{kes(@payment.amount_excl_vat)}</dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-thamani-pewter">VAT</dt>
            <dd>{kes(@payment.vat_amount)}</dd>
          </div>
          <div class="flex justify-between border-t border-thamani-stone pt-2 text-base font-semibold text-thamani-forest">
            <dt>Total</dt>
            <dd>{kes(@payment.amount)}</dd>
          </div>
          <div class="flex justify-between text-emerald-700">
            <dt>Balance due</dt>
            <dd>{kes(Decimal.new(0))}</dd>
          </div>
        </dl>

        <footer
          id="invoice-remittance"
          class="mt-8 rounded-lg border border-thamani-stone bg-thamani-snow p-4 text-xs text-thamani-pewter"
        >
          <p class="font-semibold text-thamani-ink">Remittance</p>
          <p>M-Pesa paybill {@issuer.paybill} · {@issuer.bank}</p>
        </footer>
      </article>
    </Layouts.distributor_shell>
    """
  end
end
