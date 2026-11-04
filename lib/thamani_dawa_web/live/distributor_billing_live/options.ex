defmodule ThamaniDawaWeb.DistributorBillingLive.Options do
  @moduledoc """
  The serialisation plan chooser — the gate in front of the shipment
  workflow. Prepay goes on to buy a bundle; Flex opens its first billing
  cycle immediately and goes straight to shipments.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.{Billing, Pricing}
  alias ThamaniDawa.Organizations

  def mount(_params, _session, socket) do
    organization = Organizations.get_organization!(socket.assigns.current_scope.organization_id)

    if Billing.plan_selected?(organization) do
      {:ok, push_navigate(socket, to: ~p"/distributor/billing")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Choose a serialisation plan")
       |> assign(:organization, organization)
       |> assign(:tiers, Pricing.prepay_tiers())
       |> assign(:flex_rate, Pricing.unit_price(:flex, 1))
       |> assign(:cycle_days, Pricing.flex_cycle_days())}
    end
  end

  def handle_event("choose_prepay", _params, socket) do
    case Billing.choose_prepay(socket.assigns.organization) do
      {:ok, _organization} ->
        {:noreply, push_navigate(socket, to: ~p"/distributor/billing/payment")}

      {:error, _reason} ->
        {:noreply, push_navigate(socket, to: ~p"/distributor/billing")}
    end
  end

  def handle_event("choose_flex", _params, socket) do
    case Billing.ensure_first_postpay_cycle(socket.assigns.organization) do
      {:ok, _usage} ->
        {:noreply,
         socket
         |> put_flash(:info, "Flex pay-as-you-go is active. You'll be billed for what you use.")
         |> push_navigate(to: ~p"/distributor/shipments")}

      {:error, _reason} ->
        {:noreply, push_navigate(socket, to: ~p"/distributor/billing")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/billing"}
    >
      <.header icon="hero-credit-card">
        Choose a serialisation plan
        <:subtitle>
          Approving a shipment issues one SSCC per shipper, drawn from your serialisation allowance.
        </:subtitle>
      </.header>

      <div class="grid gap-5 md:grid-cols-2">
        <section
          id="plan-prepay"
          class="group flex flex-col rounded-2xl ff-surface-card p-6 transition-shadow duration-200 hover:shadow-lg"
        >
          <div class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-xl bg-thamani-lime text-thamani-forest">
              <.icon name="hero-cube" class="size-5" />
            </span>
            <div>
              <h2 class="text-lg font-semibold text-thamani-forest">Prepay bundle</h2>
              <p class="text-sm text-thamani-pewter">Buy serials up front at tiered rates.</p>
            </div>
          </div>
          <ul class="mt-5 space-y-2 text-sm">
            <li :for={{minimum, price} <- @tiers} class="flex justify-between gap-3 border-b border-thamani-stone pb-2">
              <span>From {number(minimum)} serials</span>
              <span class="font-semibold text-thamani-forest">{kes(price)} / serial</span>
            </li>
          </ul>
          <p class="mt-3 text-xs text-thamani-pewter">
            Prices exclude VAT. Any overage on a bundle is added to your next purchase.
          </p>
          <.button
            id="choose-prepay"
            variant="primary"
            class="mt-6 w-full"
            phx-click="choose_prepay"
            phx-disable-with="Setting up…"
          >
            Choose prepay
          </.button>
        </section>

        <section
          id="plan-flex"
          class="group flex flex-col rounded-2xl ff-surface-card p-6 transition-shadow duration-200 hover:shadow-lg"
        >
          <div class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-xl bg-thamani-canvas text-thamani-forest">
              <.icon name="hero-arrow-path" class="size-5" />
            </span>
            <div>
              <h2 class="text-lg font-semibold text-thamani-forest">Flex pay-as-you-go</h2>
              <p class="text-sm text-thamani-pewter">No upfront cost — pay for what you approve.</p>
            </div>
          </div>
          <p class="mt-5 text-3xl font-semibold tracking-tight text-thamani-forest">
            {kes(@flex_rate)} <span class="text-sm font-normal text-thamani-pewter">/ serial</span>
          </p>
          <p class="mt-2 text-sm text-thamani-ink">
            Billed every {@cycle_days} days for exactly what you generated. Overdue cycles are capped
            until settled.
          </p>
          <div class="flex-1"></div>
          <.button
            id="choose-flex"
            class="mt-6 w-full"
            phx-click="choose_flex"
            phx-disable-with="Setting up…"
          >
            Choose flex
          </.button>
        </section>
      </div>
    </Layouts.distributor_shell>
    """
  end
end
