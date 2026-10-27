defmodule ThamaniDawaWeb.DistributorSettingsLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Organizations

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(org_id)

    {:ok,
     socket
     |> assign(:page_title, "Distributor settings")
     |> assign(:organization, organization)
     |> assign(
       :form,
       to_form(Organizations.change_organization_gs1_settings(organization), as: :organization)
     )}
  end

  def handle_event("validate", %{"organization" => params}, socket) do
    changeset =
      socket.assigns.organization
      |> Organizations.change_organization_gs1_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :organization))}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    case Organizations.update_organization_gs1_settings(socket.assigns.organization, params) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> put_flash(:info, "GS1 settings saved.")
         |> assign(:organization, organization)
         |> assign(
           :form,
           to_form(Organizations.change_organization_gs1_settings(organization),
             as: :organization
           )
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :organization))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/settings"}
    >
      <.header icon="hero-cog-6-tooth">
        Distributor settings
        <:subtitle>
          Configure identifiers this organization issues, such as SSCCs for cartons.
        </:subtitle>
      </.header>

      <div class="mt-6 max-w-lg rounded-xl border border-thamani-stone bg-white p-6">
        <h2 class="text-sm font-semibold text-thamani-forest">GS1 Company Prefix</h2>
        <p class="mt-1 text-sm text-thamani-pewter">
          Assigned by your local GS1 Member Organization. Used to generate globally-unique
          SSCCs for shipping cartons. Must be 6–10 digits.
        </p>

        <.form
          for={@form}
          id="distributor-gs1-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-4"
        >
          <.input
            field={@form[:gs1_company_prefix]}
            label="GS1 Company Prefix"
            placeholder="e.g. 6141410"
            maxlength="10"
            inputmode="numeric"
          />
          <.button id="save-gs1-settings" variant="primary" class="mt-3">
            Save settings
          </.button>
        </.form>

        <%= if @organization.gs1_company_prefix && @organization.gs1_company_prefix != "" do %>
          <div class="mt-4 rounded-lg bg-thamani-canvas px-4 py-3 text-sm text-thamani-forest">
            <span class="font-semibold">Current prefix:</span> {@organization.gs1_company_prefix} —
            <span class="text-thamani-pewter">{@organization.next_sscc_serial} SSCC(s) issued so far</span>
          </div>
        <% end %>
      </div>
    </Layouts.distributor_shell>
    """
  end
end
