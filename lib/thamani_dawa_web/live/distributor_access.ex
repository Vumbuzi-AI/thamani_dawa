defmodule ThamaniDawaWeb.DistributorAccess do
  @moduledoc """
  LiveView `on_mount` hooks for the distributor shipment workflow, layered on
  top of `{ThamaniDawaWeb.UserAuth, :require_distributor_access}` (which
  enforces the distributor role and the organization's distributor model).

    * `:require_serialisation_plan` — the organization must have chosen a
      prepay or flex serialisation plan before any shipment or mobile-user
      screen is reachable; otherwise the user is sent to the plan chooser.
  """

  use ThamaniDawaWeb, :verified_routes

  alias ThamaniDawa.Distributor.Billing

  def on_mount(:require_serialisation_plan, _params, _session, socket) do
    if Billing.plan_selected?(socket.assigns.current_scope.organization_id) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :info,
          "Choose a serialisation plan before working with shipments."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/distributor/billing/options")

      {:halt, socket}
    end
  end
end
