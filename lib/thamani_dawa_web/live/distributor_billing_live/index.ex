defmodule ThamaniDawaWeb.DistributorBillingLive.Index do
  @moduledoc """
  Serialisation billing overview: plan usage tiles (serials left / used /
  buffer for prepay; generated / buffer limit / amount due for flex, with an
  overdue badge), a top-up or settle call to action, and payment history
  with links to invoices.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.{Billing, Pricing, SerialUsage}
  alias ThamaniDawa.Organizations

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)

    if Billing.plan_selected?(organization) do
      if connected?(socket), do: Billing.subscribe(organization_id)

      {:ok,
       socket
       |> assign(:page_title, "Billing")
       |> assign(:organization, organization)
       |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/distributor/billing/options")}
    end
  end

  def handle_info({:serial_payment, _status, _payment_id}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    organization = socket.assigns.organization
    usage = Billing.active_usage(organization.id)

    socket
    |> assign(:usage, usage)
    |> assign(:overdue?, SerialUsage.overdue?(usage))
    |> assign(:postpay_quote, flex_quote(organization, usage))
    |> assign(:payments, Billing.list_payments(organization.id))
  end

  defp flex_quote(organization, %SerialUsage{type: "flex"}), do: Billing.postpay_quote(organization)
  defp flex_quote(_organization, _usage), do: nil

  defp plan_label("prepay"), do: "Prepay bundle"
  defp plan_label("flex"), do: "Flex pay-as-you-go"

  defp kind_label("prepay"), do: "Bundle purchase"
  defp kind_label("postpay"), do: "Flex settlement"

  defp method_label("mpesa"), do: "M-Pesa"
  defp method_label("manual"), do: "Manual reference"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/billing"}
    >
      <.header icon="hero-credit-card">
        <span class="flex flex-wrap items-center gap-3">
          Billing
          <span class="rounded-full bg-thamani-stone px-3 py-1 text-xs font-semibold text-thamani-forest">
            {plan_label(@organization.serialisation_type)}
          </span>
          <span
            :if={@overdue?}
            id="distributor-billing-overdue"
            class="rounded-full bg-rose-100 px-3 py-1 text-xs font-semibold text-rose-800"
          >
            Overdue
          </span>
        </span>
        <:subtitle>Your serialisation allowance and payment history.</:subtitle>
        <:actions>
          <.button
            :if={@organization.serialisation_type == "prepay"}
            id="distributor-buy-bundle"
            variant="primary"
            navigate={~p"/distributor/billing/payment"}
          >
            <.icon name="hero-plus" class="size-4" /> Buy serials
          </.button>
          <.button
            :if={@organization.serialisation_type == "flex"}
            id="distributor-settle-flex"
            variant="primary"
            navigate={~p"/distributor/billing/postpay-payment"}
          >
            <.icon name="hero-banknotes" class="size-4" /> Settle usage
          </.button>
        </:actions>
      </.header>

      <%= if @organization.serialisation_type == "prepay" do %>
        <div class="dashboard-stat-grid" id="distributor-prepay-usage">
          <.stat_tile
            id="stat-serials-left"
            icon="hero-cube"
            label="Serials left"
            value={number((@usage && SerialUsage.serials_left(@usage)) || 0)}
            sublabel={if @usage, do: "of #{number(@usage.quantity_limit)} in this bundle", else: "No bundle yet — buy one to start approving"}
          />
          <.stat_tile
            id="stat-serials-used"
            icon="hero-qr-code"
            label="Used"
            value={number((@usage && @usage.running_quantity) || 0)}
            sublabel="SSCCs issued from this bundle"
          />
          <.stat_tile
            id="stat-serials-buffer"
            icon="hero-arrow-trending-up"
            label="Buffer used"
            value={number((@usage && @usage.running_buffer) || 0)}
            sublabel={"Up to #{number(Pricing.buffer_limit())}, added to your next purchase"}
          />
        </div>
      <% else %>
        <div class="dashboard-stat-grid" id="distributor-flex-usage">
          <.stat_tile
            id="stat-flex-generated"
            icon="hero-qr-code"
            label="Generated this cycle"
            value={number((@usage && SerialUsage.generated(@usage)) || 0)}
            sublabel={if @usage, do: "Since #{short_date(@usage.cycle_started_at)}", else: "—"}
          />
          <.stat_tile
            id="stat-flex-due"
            icon="hero-banknotes"
            label="Amount due"
            value={if @postpay_quote, do: kes(@postpay_quote.amount), else: kes(nil)}
            sublabel={if @usage, do: "Billing date #{short_date(@usage.billing_date)}", else: "—"}
          />
          <.stat_tile
            id="stat-flex-cap"
            icon="hero-shield-exclamation"
            label="Overdue cap"
            value={number(Pricing.buffer_limit())}
            sublabel={
              if @overdue?,
                do: "#{number((@usage && @usage.running_buffer) || 0)} used — settle to lift the cap",
                else: "Serials allowed once a cycle is overdue"
            }
          />
        </div>
      <% end %>

      <section class="mt-6">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wide text-thamani-pewter">
          Payment history
        </h2>
        <.table id="distributor-serial-payments" rows={@payments}>
          <:col :let={payment} label="Date">
            <span class="text-sm">{date_time(payment.paid_at || payment.inserted_at)}</span>
          </:col>
          <:col :let={payment} label="Status" mobile="aside">
            <.payment_status_badge status={payment.status} />
          </:col>
          <:col :let={payment} label="Type">{kind_label(payment.kind)}</:col>
          <:col :let={payment} label="Serials">
            {number(payment.quantity + payment.buffer_quantity)}
          </:col>
          <:col :let={payment} label="Amount">{kes(payment.amount)}</:col>
          <:col :let={payment} label="Method" tablet="hidden">{method_label(payment.method)}</:col>
          <:action :let={payment}>
            <.button
              :if={payment.invoice_number}
              id={"view-invoice-#{payment.id}"}
              variant="ghost"
              navigate={~p"/distributor/billing/invoices/#{payment.id}"}
            >
              {payment.invoice_number}
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-banknotes" title="No payments yet">
              Payments and their invoices will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </section>
    </Layouts.distributor_shell>
    """
  end
end
