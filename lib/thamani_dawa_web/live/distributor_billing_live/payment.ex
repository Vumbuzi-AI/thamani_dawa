defmodule ThamaniDawaWeb.DistributorBillingLive.Payment do
  @moduledoc """
  Serialisation checkout.

    * `:prepay` — choose a bundle size, see the tiered price (with any
      buffer from the current bundle folded in, plus VAT), and pay.
    * `:postpay` — settle the open flex cycle for exactly what it generated.

  A manually entered reference confirms the payment immediately.
  M-Pesa is offered only when Daraja is explicitly enabled and configured.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.{Billing, Pricing}
  alias ThamaniDawa.Organizations

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)
    if connected?(socket), do: Billing.subscribe(organization_id)

    expected_plan = if socket.assigns.live_action == :prepay, do: "prepay", else: "flex"

    cond do
      not Billing.plan_selected?(organization) ->
        {:ok, push_navigate(socket, to: ~p"/distributor/billing/options")}

      organization.serialisation_type != expected_plan ->
        {:ok, push_navigate(socket, to: ~p"/distributor/billing")}

      true ->
        params = %{
          "quantity" => Integer.to_string(Pricing.minimum_prepay_quantity() * 10),
          "method" => "manual",
          "phone" => "",
          "manual_reference" => ""
        }

        {:ok,
         socket
         |> assign(:organization, organization)
         |> assign(:page_title, page_title(socket.assigns.live_action))
         |> assign(:pending_payment, nil)
         |> assign(:error, nil)
         |> assign_form(params)}
    end
  end

  defp page_title(:prepay), do: "Buy a serialisation bundle"
  defp page_title(:postpay), do: "Settle flex usage"

  defp assign_form(socket, params) do
    charge =
      case socket.assigns.live_action do
        :prepay -> Billing.prepay_quote(socket.assigns.organization, parse_quantity(params))
        :postpay -> Billing.postpay_quote(socket.assigns.organization)
      end

    socket
    |> assign(:params, params)
    |> assign(:charge, charge)
    |> assign(:form, to_form(params, as: :payment))
  end

  defp parse_quantity(params) do
    case Integer.parse(params["quantity"] || "") do
      {quantity, ""} when quantity > 0 -> quantity
      _ -> 0
    end
  end

  def handle_event("change", %{"payment" => params}, socket) do
    {:noreply, socket |> assign(:error, nil) |> assign_form(params)}
  end

  def handle_event("pay", %{"payment" => params}, socket) do
    %{current_scope: scope, organization: organization} = socket.assigns

    result =
      case socket.assigns.live_action do
        :prepay -> Billing.start_prepay_payment(organization, scope.user, params)
        :postpay -> Billing.start_postpay_payment(organization, scope.user, params)
      end

    case result do
      {:ok, %{status: "paid"}} ->
        {:noreply, paid(socket)}

      {:ok, payment} ->
        {:noreply, socket |> assign(:pending_payment, payment) |> assign_form(params)}

      {:error, reason} ->
        {:noreply, socket |> assign(:error, error_message(reason)) |> assign_form(params)}
    end
  end

  def handle_event("cancel_pending", _params, socket) do
    {:noreply, assign(socket, :pending_payment, nil)}
  end

  def handle_info({:serial_payment, status, payment_id}, socket) do
    case socket.assigns.pending_payment do
      %{id: ^payment_id} when status == "paid" ->
        {:noreply, paid(socket)}

      %{id: ^payment_id} when status == "failed" ->
        {:noreply,
         socket
         |> assign(:pending_payment, nil)
         |> assign(:error, "The M-Pesa payment didn't go through. Please try again.")}

      _ ->
        {:noreply, socket}
    end
  end

  defp paid(socket) do
    socket
    |> put_flash(:info, "Payment received — your serialisation allowance has been updated.")
    |> push_navigate(to: ~p"/distributor/billing")
  end

  defp error_message(:quantity_below_minimum),
    do: "The minimum bundle is #{number(Pricing.minimum_prepay_quantity())} serials."

  defp error_message(:invalid_quantity), do: "Enter how many serials you'd like to buy."
  defp error_message(:invalid_method), do: "Choose a payment method."
  defp error_message(:invalid_phone), do: "Enter a valid Safaricom number, e.g. 0712 345 678."
  defp error_message(:missing_manual_reference), do: "Enter the payment reference."

  defp error_message(:mpesa_unavailable),
    do: "M-Pesa checkout is not available yet. Submit a manual payment reference instead."

  defp error_message(:nothing_to_pay), do: "There's no usage to settle in this cycle yet."
  defp error_message(:wrong_plan), do: "This payment doesn't match your plan."

  defp error_message(reason) when reason in [:auth_failed, :provider_error, :timeout],
    do: "We couldn't reach M-Pesa just now. Please try again in a moment."

  defp error_message(_reason), do: "Something went wrong. Please try again."

  defp vat_percent do
    rate = Pricing.vat_rate()

    rate
    |> Decimal.mult(100)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/billing"}
    >
      <.header icon="hero-credit-card" back={~p"/distributor/billing"}>
        {@page_title}
        <:subtitle>
          <%= if @live_action == :prepay do %>
            Tiered pricing applies to the whole bundle. {Pricing.rate_label(:prepay, @charge.quantity)}.
          <% else %>
            Billed at {Pricing.rate_label(:flex)} for every serial generated this cycle.
          <% end %>
        </:subtitle>
      </.header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section class="rounded-2xl ff-surface-card p-5 sm:p-6">
          <%= if @pending_payment do %>
            <div id="distributor-payment-pending" class="py-6 text-center">
              <div class="mx-auto flex size-14 items-center justify-center rounded-full bg-thamani-lime">
                <.icon
                  name={
                    if @pending_payment.method == "manual",
                      do: "hero-clock",
                      else: "hero-device-phone-mobile"
                  }
                  class="size-7 text-thamani-forest"
                />
              </div>
              <h2 class="mt-4 text-lg font-semibold text-thamani-forest">Check your phone</h2>
              <p class="mt-1 text-sm text-thamani-pewter">
                Enter your M-Pesa PIN on {@pending_payment.phone} to pay {kes(@pending_payment.amount)}.
                This page updates as soon as the payment is confirmed.
              </p>
              <.button id="cancel-pending-payment" class="mt-5" phx-click="cancel_pending">
                Cancel
              </.button>
            </div>
          <% else %>
            <.form for={@form} id="distributor-payment-form" phx-change="change" phx-submit="pay">
              <.input
                :if={@live_action == :prepay}
                field={@form[:quantity]}
                type="number"
                label="Serials to buy"
                min={Pricing.minimum_prepay_quantity()}
                step="1"
                required
              />
              <fieldset class="mb-3">
                <legend class="thamani-label">Payment method</legend>
                <div class="mt-1 grid gap-2 sm:grid-cols-2">
                  <label
                    :for={
                      {value, label, icon} <-
                        [{"manual", "Bank / manual reference", "hero-building-library"}] ++
                          if(Billing.mpesa_enabled?(),
                            do: [{"mpesa", "M-Pesa", "hero-device-phone-mobile"}],
                            else: []
                          )
                    }
                    class={[
                      "flex cursor-pointer items-center gap-3 rounded-xl border px-4 py-3 text-sm transition-colors duration-150",
                      if(@params["method"] == value,
                        do: "border-thamani-forest bg-thamani-lime/40 text-thamani-forest",
                        else: "border-thamani-stone hover:border-thamani-forest/40"
                      )
                    ]}
                  >
                    <input
                      type="radio"
                      name="payment[method]"
                      value={value}
                      checked={@params["method"] == value}
                      class="sr-only"
                    />
                    <.icon name={icon} class="size-5" />
                    <span class="font-medium">{label}</span>
                  </label>
                </div>
              </fieldset>
              <.input
                :if={@params["method"] == "mpesa"}
                field={@form[:phone]}
                type="tel"
                label="M-Pesa phone number"
                placeholder="0712 345 678"
                required
              />
              <.input
                :if={@params["method"] == "manual"}
                field={@form[:manual_reference]}
                label="Payment reference"
                placeholder="e.g. bank transfer or M-Pesa paybill confirmation code"
                required
              />
              <p
                :if={@error}
                id="distributor-payment-error"
                class="mb-3 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800"
              >
                {@error}
              </p>
              <.button
                id="submit-distributor-payment"
                variant="primary"
                class="w-full"
                phx-disable-with="Processing…"
                disabled={is_nil(@charge) or @charge.quantity == 0}
              >
                {if @params["method"] == "manual", do: "Confirm payment", else: "Pay"} {if @charge,
                  do: kes(@charge.amount),
                  else: kes(nil)}
              </.button>
            </.form>
          <% end %>
        </section>

        <aside id="distributor-payment-summary" class="h-fit rounded-2xl ff-surface-card p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">Summary</h2>
          <%= if @charge do %>
            <dl class="mt-3 space-y-2 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">
                  {if @live_action == :prepay, do: "Bundle", else: "Generated this cycle"}
                </dt>
                <dd>{number(@charge.purchased_quantity)} serials</dd>
              </div>
              <div :if={@charge.buffer_quantity > 0} class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Buffer carried in</dt>
                <dd>{number(@charge.buffer_quantity)} serials</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Rate</dt>
                <dd>{kes(@charge.unit_price)} / serial</dd>
              </div>
              <div class="flex justify-between gap-3 border-t border-thamani-stone pt-2">
                <dt class="text-thamani-pewter">Subtotal</dt>
                <dd>{kes(@charge.amount_excl_vat)}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">
                  VAT {if @charge.vat_applicable, do: "(#{vat_percent()}%)", else: "(not applicable)"}
                </dt>
                <dd>{kes(@charge.vat_amount)}</dd>
              </div>
              <div class="flex justify-between gap-3 border-t border-thamani-stone pt-2 text-base font-semibold text-thamani-forest">
                <dt>Total</dt>
                <dd>{kes(@charge.amount)}</dd>
              </div>
            </dl>
          <% else %>
            <p class="mt-3 text-sm text-thamani-pewter">Nothing to settle yet.</p>
          <% end %>
        </aside>
      </div>
    </Layouts.distributor_shell>
    """
  end
end
