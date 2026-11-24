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
    <div class="td-auth">
      <div class="td-auth-corner">
        <.td_button
          variant="secondary"
          label="Back to log in"
          href={~p"/logout"}
          method="delete"
          glyph="arrow-left"
        />
      </div>

      <div class="td-auth-col">
        <a href="/" aria-label="Thamani Dawa home" class="td-auth-logo">
          <img src="/images/logo-transparent.png" alt="Thamani Dawa" />
        </a>

        <div class="td-auth-panel">
          <h1>Confirm your email</h1>
          <p class="td-auth-lead">We sent a confirmation link to {@current_scope.user.email}.</p>

          <div class="td-auth-form">
            <.td_button
              id="confirm-email-resend"
              type="button"
              variant="secondary"
              size="lg"
              label={
                if resend_ready?(assigns),
                  do: "Resend confirmation email",
                  else: "Resend in #{@resend_seconds_remaining}s"
              }
              disabled={not resend_ready?(assigns)}
              phx-click="resend"
            />
          </div>

          <p class="td-auth-switch">
            <span>Wrong account?</span>
            <.link href={~p"/logout"} method="delete">Log out</.link>
          </p>
        </div>
      </div>

      <Layouts.flash_group flash={@flash} />

      <div class="td-auth-page-foot">
        <.link navigate={~p"/privacy"}>Privacy</.link>
        <.link navigate={~p"/terms"}>Terms</.link>
      </div>
    </div>
    """
  end
end
