defmodule ThamaniDawaWeb.ConfirmEmailLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts

  @resend_cooldown_seconds 30

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:resend_ready_at, nil)
     |> assign(:resend_seconds_remaining, 0)}
  end

  def handle_event("resend", _params, socket) do
    user = socket.assigns.current_scope.user

    if resend_ready?(socket.assigns) do
      Accounts.deliver_user_confirmation_instructions(user, fn token ->
        url(~p"/confirm/#{token}")
      end)

      ready_at = DateTime.add(DateTime.utc_now(), @resend_cooldown_seconds, :second)
      Process.send_after(self(), :tick, 1000)

      {:noreply,
       socket
       |> assign(:resend_ready_at, ready_at)
       |> assign(:resend_seconds_remaining, @resend_cooldown_seconds)
       |> put_flash(:info, "Confirmation email resent to #{user.email}.")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:tick, socket) do
    deadline_remaining = seconds_remaining(socket.assigns.resend_ready_at)

    remaining =
      socket.assigns.resend_seconds_remaining
      |> Kernel.-(1)
      |> max(0)
      |> min(deadline_remaining)

    if deadline_remaining == 0 do
      {:noreply,
       socket
       |> assign(:resend_ready_at, nil)
       |> assign(:resend_seconds_remaining, 0)}
    else
      Process.send_after(self(), :tick, 1000)
      {:noreply, assign(socket, :resend_seconds_remaining, max(remaining, 1))}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp resend_ready?(%{resend_ready_at: nil}), do: true

  defp resend_ready?(%{resend_ready_at: ready_at}),
    do: DateTime.compare(DateTime.utc_now(), ready_at) != :lt

  defp seconds_remaining(nil), do: 0

  defp seconds_remaining(ready_at) do
    DateTime.diff(ready_at, DateTime.utc_now(), :second) |> max(0)
  end

  def render(assigns) do
    ~H"""
    <div class="auth-shell lg:h-svh lg:overflow-hidden">
      <div class="auth-aside hidden lg:flex lg:h-svh">
        <div class="auth-aside-main">
          <.link navigate={~p"/"} aria-label="Thamani Dawa home" class="auth-aside-logo">
            <img src="/images/logo-transparent.png" alt="" class="h-auto w-full brightness-0 invert" />
          </.link>

          <div>
            <span
              class="thamani-badge"
              style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px; margin-bottom: 24px; display: inline-flex; align-items: center; gap: 7px;"
            >
              Almost there
            </span>
            <h2 style="font-size: clamp(28px, 2.8vw, 40px); font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-snow); text-wrap: balance; margin: 16px 0 20px;">
              One quick check before you get started.
            </h2>
            <p style="font-size: 16px; line-height: 1.65; color: rgba(252,252,247,0.55); max-width: 340px;">
              Confirming your email protects your organization's account from
              being set up by someone who isn't actually you.
            </p>
          </div>
        </div>

        <div style="border-top: 1px solid rgba(252,252,247,0.1); padding-top: 28px;">
          <p style="font-size: 15px; font-weight: 350; color: rgba(252,252,247,0.75); line-height: 1.55; font-style: italic; margin-bottom: 16px;">
            "We were up and running in a single afternoon: stock, prescriptions, everything."
          </p>
          <p style="font-size: 13px; font-weight: 500; color: rgba(252,252,247,0.45);">
            Jane Mwangi · Owner, MedPoint Pharmacy, Nakuru
          </p>
        </div>
      </div>

      <div class="auth-form-panel lg:h-svh lg:overflow-y-auto" style="justify-content: center;">
        <div class="auth-form-inner" style="max-width: 380px;">
          <ThamaniDawaWeb.Layouts.flash_group flash={@flash} />

          <div class="mb-5 flex size-12 items-center justify-center rounded-2xl bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] text-[var(--thamani-forest)]">
            <.icon name="hero-envelope" class="size-6" />
          </div>

          <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
            Confirm your email
          </h1>
          <p class="mb-8 text-[15px] leading-6 text-[var(--thamani-pewter)]">
            We sent a confirmation link to
            <span class="font-semibold text-[var(--thamani-forest)]">
              {@current_scope.user.email}
            </span>
            . Click it to finish setting up your organization.
          </p>

          <div class="flex items-center gap-4">
            <button
              id="confirm-email-resend"
              type="button"
              phx-click="resend"
              disabled={not resend_ready?(assigns)}
              class="inline-flex h-11 items-center justify-center rounded-full border-0 bg-thamani-forest px-6 text-[15px] font-medium text-thamani-snow no-underline transition-all duration-200 ease-out hover:-translate-y-0.5 hover:bg-[#10221e] hover:shadow-lg disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:translate-y-0 disabled:hover:bg-thamani-forest"
            >
              <%= if resend_ready?(assigns) do %>
                Resend confirmation email
              <% else %>
                Resend in {@resend_seconds_remaining}s
              <% end %>
            </button>
          </div>

          <p class="mt-8 text-sm text-[var(--thamani-pewter)]">
            Wrong account? <.link href={~p"/logout"} method="delete" class="underline">Log out</.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
