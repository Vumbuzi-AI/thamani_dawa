defmodule ThamaniDawaWeb.ApiKeysLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Organizations

  def mount(_params, _session, socket) do
    organization = Organizations.get_organization!(socket.assigns.current_scope.organization_id)
    portal = if Scope.admin?(socket.assigns.current_scope), do: :organization, else: :distributor

    current_path =
      if portal == :organization, do: ~p"/org/api-keys", else: ~p"/distributor/api-keys"

    {:ok,
     socket
     |> assign(:page_title, "API keys")
     |> assign(:portal, portal)
     |> assign(:current_path, current_path)
     |> assign(:organization, organization)
     |> assign(:editing_key_tier, nil)
     |> assign(:editing_gs1, false)}
  end

  def handle_event("edit_api_key", %{"tier" => tier}, socket)
      when tier in ["distributor", "facility"] do
    {:noreply, socket |> assign(:editing_key_tier, tier) |> assign(:editing_gs1, false)}
  end

  def handle_event("cancel_edit_api_key", _params, socket) do
    {:noreply, assign(socket, :editing_key_tier, nil)}
  end

  def handle_event("save_api_key", %{"tier" => tier, "key" => key}, socket)
      when tier in ["distributor", "facility"] do
    case Organizations.set_epcis_api_key(socket.assigns.organization, tier, key) do
      {:ok, updated} ->
        message =
          if blank?(key),
            do: "#{tier_label(tier)} key cleared. Reporting falls back to the platform key.",
            else: "#{tier_label(tier)} key saved."

        {:noreply,
         socket
         |> assign(:organization, updated)
         |> assign(:editing_key_tier, nil)
         |> put_flash(:info, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't save that key.")}
    end
  end

  def handle_event("clear_api_key", %{"tier" => tier}, socket)
      when tier in ["distributor", "facility"] do
    {:ok, updated} = Organizations.clear_epcis_api_key(socket.assigns.organization, tier)

    {:noreply,
     socket
     |> assign(:organization, updated)
     |> assign(:editing_key_tier, nil)
     |> put_flash(
       :info,
       "#{tier_label(tier)} key cleared. Reporting falls back to the platform key."
     )}
  end

  def handle_event("edit_gs1_key", _params, socket) do
    {:noreply, socket |> assign(:editing_gs1, true) |> assign(:editing_key_tier, nil)}
  end

  def handle_event("cancel_gs1_key", _params, socket) do
    {:noreply, assign(socket, :editing_gs1, false)}
  end

  def handle_event("save_gs1_key", %{"key" => key}, socket) do
    case Organizations.set_gs1_api_key(socket.assigns.organization, key) do
      {:ok, updated} ->
        message =
          if blank?(key),
            do: "GS1 key cleared. SSCC calls fall back to the platform token.",
            else: "GS1 key saved."

        {:noreply,
         socket
         |> assign(:organization, updated)
         |> assign(:editing_gs1, false)
         |> put_flash(:info, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't save that key.")}
    end
  end

  def handle_event("clear_gs1_key", _params, socket) do
    {:ok, updated} = Organizations.set_gs1_api_key(socket.assigns.organization, nil)

    {:noreply,
     socket
     |> assign(:organization, updated)
     |> assign(:editing_gs1, false)
     |> put_flash(:info, "GS1 key cleared. SSCC calls fall back to the platform token.")}
  end

  defp blank?(nil), do: true
  defp blank?(key), do: String.trim(key) == ""

  defp tier_label("distributor"), do: "Distributor"
  defp tier_label("facility"), do: "Facility"

  defp tier_events("distributor"), do: "Receiving, packing, and shipping"
  defp tier_events("facility"), do: "Receiving and dispensing"

  defp key_last4(organization, "distributor"), do: organization.epcis_distributor_api_key_last4
  defp key_last4(organization, "facility"), do: organization.epcis_facility_api_key_last4

  defp relevant_tiers(organization) do
    models = organization.operating_models || []

    [
      :distributor in models && "distributor",
      Enum.any?(models, &(&1 in [:pharmacy, :laboratory])) && "facility"
    ]
    |> Enum.filter(& &1)
  end

  defp keys_needed?(organization, tiers) do
    Enum.any?(tiers, &(key_last4(organization, &1) in [nil, ""]))
  end

  attr :portal, :atom, required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  defp keys_shell(%{portal: :organization} = assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      {render_slot(@inner_block)}
    </Layouts.org_shell>
    """
  end

  defp keys_shell(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      {render_slot(@inner_block)}
    </Layouts.distributor_shell>
    """
  end

  attr :tier, :string, required: true
  attr :last4, :string, default: nil
  attr :editing, :boolean, default: false

  defp api_key_row(assigns) do
    ~H"""
    <div
      id={"tnt-api-key-#{@tier}"}
      class="rounded-xl border border-thamani-frosted bg-thamani-canvas px-4 py-3"
    >
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0">
          <p class="text-sm font-semibold text-thamani-forest">{tier_label(@tier)}</p>
          <p class="mt-0.5 text-xs text-thamani-pewter">{tier_events(@tier)}</p>
        </div>

        <form
          :if={@editing}
          id={"tnt-api-key-form-#{@tier}"}
          phx-submit="save_api_key"
          class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center"
        >
          <input type="hidden" name="tier" value={@tier} />
          <input
            type="password"
            name="key"
            autocomplete="off"
            placeholder="trk_live_…"
            aria-label={"#{tier_label(@tier)} API key"}
            class="thamani-input w-full sm:w-64"
          />
          <.button type="submit" variant="primary">Save</.button>
          <.button type="button" phx-click="cancel_edit_api_key">Cancel</.button>
        </form>

        <div :if={!@editing} class="flex items-center justify-between gap-3 sm:justify-end">
          <p class="text-sm text-thamani-pewter">
            <%= if @last4 do %>
              Key ending <span class="font-medium tabular-nums text-thamani-forest">{@last4}</span>
            <% else %>
              No key saved
            <% end %>
          </p>
          <div class="flex items-center gap-2">
            <.button
              type="button"
              id={"edit-tnt-key-#{@tier}"}
              phx-click="edit_api_key"
              phx-value-tier={@tier}
              variant={if(@last4, do: "ghost", else: "primary")}
            >
              {if @last4, do: "Replace", else: "Add key"}
            </.button>
            <.button
              :if={@last4}
              type="button"
              id={"clear-tnt-key-#{@tier}"}
              phx-click="clear_api_key"
              phx-value-tier={@tier}
              data-confirm="Clear this key and use the platform-wide key?"
            >
              Clear
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    organization = assigns.organization
    tiers = relevant_tiers(organization)

    assigns =
      assigns
      |> assign(:tiers, tiers)
      |> assign(:keys_needed?, keys_needed?(organization, tiers))

    ~H"""
    <.keys_shell
      portal={@portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      <div class="space-y-5">
        <.header icon="hero-key">
          API keys
          <:subtitle>
            Credentials this organization uses with PPB Track &amp; Trace and GS1.
          </:subtitle>
        </.header>

        <section
          id="epcis-api-key-settings"
          class={[
            "rounded-2xl border bg-white p-5 sm:p-6",
            if(@keys_needed?, do: "border-thamani-forest", else: "border-thamani-frosted")
          ]}
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="max-w-2xl">
              <h2 class="text-base font-semibold text-thamani-forest">
                {if @keys_needed?, do: "Add your TNT API key", else: "TNT API key"}
              </h2>
              <p class="mt-1 text-sm leading-6 text-thamani-pewter">
                <%= if @keys_needed? do %>
                  Events are reported with your organization's TNT API key. Add it before you send anything. The TrackIQ Partner Portal is where you register and copy the key.
                <% else %>
                  Events are reported with the key saved here.
                <% end %>
              </p>
            </div>
            <a
              href="https://trackiq.apeiro-digital.com/"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex shrink-0 items-center gap-1.5 text-sm font-medium text-thamani-forest underline-offset-2 hover:underline"
            >
              Partner Portal <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </a>
          </div>

          <div :if={@tiers == []} class="mt-4 text-sm text-thamani-pewter">
            This organization has no distributor or facility reporting tier yet.
          </div>

          <div :if={@tiers != []} class="mt-4 space-y-3">
            <.api_key_row
              :for={tier <- @tiers}
              tier={tier}
              last4={key_last4(@organization, tier)}
              editing={@editing_key_tier == tier}
            />
          </div>
        </section>

        <section
          id="gs1-api-key-settings"
          class="rounded-2xl border border-thamani-frosted bg-white p-5 sm:p-6"
        >
          <div class="max-w-2xl">
            <h2 class="text-base font-semibold text-thamani-forest">GS1 API key</h2>
            <p class="mt-1 text-sm leading-6 text-thamani-pewter">
              Bearer token for the GS1 member API. This organization uses it when creating an SSCC and when fetching the serials inside a case. Leave it empty to use the platform token.
            </p>
          </div>

          <div
            id="gs1-api-key-row"
            class="mt-4 rounded-xl border border-thamani-frosted bg-thamani-canvas px-4 py-3"
          >
            <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div class="min-w-0">
                <p class="text-sm font-semibold text-thamani-forest">Member API</p>
                <p class="mt-0.5 text-xs text-thamani-pewter">
                  SSCC creation and case contents
                </p>
              </div>

              <form
                :if={@editing_gs1}
                id="gs1-api-key-form"
                phx-submit="save_gs1_key"
                class="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center"
              >
                <input
                  type="password"
                  name="key"
                  autocomplete="off"
                  placeholder="GS1 API key"
                  aria-label="GS1 API key"
                  class="thamani-input w-full sm:w-64"
                />
                <.button type="submit" variant="primary">Save</.button>
                <.button type="button" phx-click="cancel_gs1_key">Cancel</.button>
              </form>

              <div :if={!@editing_gs1} class="flex items-center justify-between gap-3 sm:justify-end">
                <p class="text-sm text-thamani-pewter">
                  <%= if @organization.gs1_api_key_last4 do %>
                    Key ending
                    <span class="font-medium tabular-nums text-thamani-forest">
                      {@organization.gs1_api_key_last4}
                    </span>
                  <% else %>
                    No key saved
                  <% end %>
                </p>
                <div class="flex items-center gap-2">
                  <.button
                    type="button"
                    id="edit-gs1-key"
                    phx-click="edit_gs1_key"
                    variant={if(@organization.gs1_api_key_last4, do: "ghost", else: "primary")}
                  >
                    {if @organization.gs1_api_key_last4, do: "Replace", else: "Add key"}
                  </.button>
                  <.button
                    :if={@organization.gs1_api_key_last4}
                    type="button"
                    id="clear-gs1-key"
                    phx-click="clear_gs1_key"
                    data-confirm="Clear this key and use the platform-wide key?"
                  >
                    Clear
                  </.button>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </.keys_shell>
    """
  end
end
