defmodule ThamaniDawaWeb.ManufacturerSsccLive.Serials do
  @moduledoc "Paginated list of primary serials packed under a shipper SSCC."

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @per_page 100

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, id)
    serials = Manufacturing.list_serials_for_sscc(organization_id, sscc.id)

    {:ok,
     socket
     |> assign(:page_title, "Serials")
     |> assign(:sscc, sscc)
     |> assign(:serials, serials)
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply, assign(socket, :page, socket.assigns.page + 1)}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply, assign(socket, :page, max(socket.assigns.page - 1, 1))}
  end

  defp page_slice(serials, page) do
    serials |> Enum.drop((page - 1) * @per_page) |> Enum.take(@per_page)
  end

  def render(assigns) do
    assigns = assign(assigns, :page_serials, page_slice(assigns.serials, assigns.page))

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-qr-code">
        Serials
        <:subtitle>
          <span class="font-mono">{@sscc.code}</span> · {length(@serials)} total
        </:subtitle>
      </.header>

      <div class="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
        <span
          :for={serial <- @page_serials}
          class="truncate rounded bg-thamani-canvas px-2 py-1 font-mono text-xs text-thamani-ink"
        >
          {serial.serial}
        </span>
      </div>

      <div class="mt-4 flex items-center justify-between">
        <.button type="button" phx-click="prev_page" disabled={@page == 1}>Previous</.button>
        <span class="text-xs text-thamani-pewter">Page {@page}</span>
        <.button type="button" phx-click="next_page" disabled={length(@page_serials) < @per_page}>
          Next
        </.button>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
