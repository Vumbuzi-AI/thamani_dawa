defmodule ThamaniDawaWeb.ApiKeysLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Organizations
  alias ThamaniDawaWeb.Portals

  def mount(_params, _session, socket) do
    organization = Organizations.get_organization!(socket.assigns.current_scope.organization_id)
    portal = resolve_portal(socket.assigns.current_scope)

    current_path =
      case portal do
        :organization -> ~p"/org/api-keys"
        :manufacturer -> ~p"/manufacturer/api-keys"
        :distributor -> ~p"/distributor/api-keys"
      end

    {:ok,
     socket
     |> assign(:page_title, "API keys")
     |> assign(:portal, portal)
     |> assign(:current_path, current_path)
     |> assign(:organization, organization)
     |> assign(:editing_key_tier, nil)
     |> assign(:editing_gs1, false)
     |> assign(:clearing_key, nil)
     |> assign(:onboarding?, false)}
  end

  def handle_params(params, _url, socket) do
    onboarding? = params["return_to"] == "onboarding"

    {:noreply,
     socket
     |> assign(:onboarding?, onboarding?)
     |> assign(
       :onboarding_progress,
       Organizations.onboarding_progress(socket.assigns.organization)
     )}
  end

  defp resolve_portal(scope) do
    cond do
      Scope.admin?(scope) and is_nil(scope.current_site_id) ->
        :organization

      Scope.manufacturer_access?(scope) and Portals.manufacturer_organization?(scope) ->
        :manufacturer

      true ->
        :distributor
    end
  end

  def handle_event("edit_api_key", %{"tier" => tier}, socket)
      when tier in ["distributor", "facility", "manufacturer"] do
    {:noreply, socket |> assign(:editing_key_tier, tier) |> assign(:editing_gs1, false)}
  end

  def handle_event("cancel_edit_api_key", _params, socket) do
    {:noreply, assign(socket, :editing_key_tier, nil)}
  end

  def handle_event("save_api_key", %{"tier" => tier, "key" => key}, socket)
      when tier in ["distributor", "facility", "manufacturer"] do
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
      when tier in ["distributor", "facility", "manufacturer"] do
    {:ok, updated} = Organizations.clear_epcis_api_key(socket.assigns.organization, tier)

    {:noreply,
     socket
     |> assign(:organization, updated)
     |> assign(:editing_key_tier, nil)
     |> assign(:clearing_key, nil)
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
     |> assign(:clearing_key, nil)
     |> put_flash(:info, "GS1 key cleared. SSCC calls fall back to the platform token.")}
  end

  def handle_event("prompt_clear_api_key", %{"tier" => tier}, socket)
      when tier in ["distributor", "facility", "manufacturer"] do
    {:noreply,
     assign(socket, :clearing_key, %{
       kind: :tnt,
       tier: tier,
       last4: key_last4(socket.assigns.organization, tier)
     })}
  end

  def handle_event("prompt_clear_gs1_key", _params, socket) do
    {:noreply,
     assign(socket, :clearing_key, %{
       kind: :gs1,
       last4: socket.assigns.organization.gs1_api_key_last4
     })}
  end

  def handle_event("cancel_clear_key", _params, socket) do
    {:noreply, assign(socket, :clearing_key, nil)}
  end

  def handle_event("continue_onboarding", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/onboarding?complete=1")}
  end

  defp blank?(nil), do: true
  defp blank?(key), do: String.trim(key) == ""

  defp tier_label("distributor"), do: "Distributor"
  defp tier_label("facility"), do: "Facility"
  defp tier_label("manufacturer"), do: "Manufacturer"

  defp tier_events("distributor"), do: "Receiving, packing, and shipping"
  defp tier_events("facility"), do: "Receiving and dispensing"
  defp tier_events("manufacturer"), do: "Commissioning, packing, and shipping"

  defp key_last4(organization, "distributor"), do: organization.epcis_distributor_api_key_last4
  defp key_last4(organization, "facility"), do: organization.epcis_facility_api_key_last4
  defp key_last4(organization, "manufacturer"), do: organization.epcis_manufacturer_api_key_last4

  defp relevant_tiers(organization) do
    models = organization.operating_models || []

    [
      :distributor in models && "distributor",
      :manufacturer in models && "manufacturer",
      Enum.any?(models, &(&1 in [:pharmacy, :laboratory])) && "facility"
    ]
    |> Enum.filter(& &1)
  end

  defp keys_needed?(organization, tiers) do
    Enum.any?(tiers, &(key_last4(organization, &1) in [nil, ""]))
  end

  defp clear_key_identity(%{kind: :gs1, last4: last4}), do: "GS1 key ending #{last4}"

  defp clear_key_identity(%{kind: :tnt, tier: tier, last4: last4}),
    do: "#{tier_label(tier)} key ending #{last4}"

  defp clear_key_fallback(%{kind: :gs1}),
    do: "SSCC calls fall back to the platform token until you add a new one."

  defp clear_key_fallback(_key),
    do: "Reporting falls back to the platform-wide key until you add a new one."

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

  defp keys_shell(%{portal: :manufacturer} = assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      {render_slot(@inner_block)}
    </Layouts.manufacturer_shell>
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
    <div id={"tnt-api-key-#{@tier}"} class={["td-key-row", @editing && "is-editing"]}>
      <div class="td-key-row-meta">
        <b>{tier_label(@tier)}</b>
        <span>{tier_events(@tier)}</span>
      </div>

      <form
        :if={@editing}
        id={"tnt-api-key-form-#{@tier}"}
        phx-submit="save_api_key"
        class="td-key-row-form"
      >
        <input type="hidden" name="tier" value={@tier} />
        <.td_input
          id={"tnt-api-key-input-#{@tier}"}
          type="password"
          name="key"
          label={"#{tier_label(@tier)} API key"}
          autocomplete="off"
          placeholder="trk_live_…"
        />
        <.td_button type="submit" variant="primary" label="Save" />
        <.td_button type="button" variant="secondary" label="Cancel" phx-click="cancel_edit_api_key" />
      </form>

      <div :if={!@editing} class={["td-key-row-value", is_nil(@last4) && "is-empty"]}>
        <%= if @last4 do %>
          Key ending <code>{@last4}</code>
        <% else %>
          No key saved
        <% end %>
      </div>
      <div :if={!@editing} class="td-key-row-actions">
        <.td_button
          type="button"
          id={"edit-tnt-key-#{@tier}"}
          phx-click="edit_api_key"
          phx-value-tier={@tier}
          variant={if(@last4, do: "secondary", else: "primary")}
          glyph={if(@last4, do: nil, else: "plus")}
          label={if(@last4, do: "Replace", else: "Add key")}
        />
        <.td_button
          :if={@last4}
          type="button"
          id={"clear-tnt-key-#{@tier}"}
          variant="secondary"
          label="Clear"
          phx-click="prompt_clear_api_key"
          phx-value-tier={@tier}
        />
      </div>
    </div>
    """
  end

  defp clear_key_modal(assigns) do
    ~H"""
    <.td_modal
      :if={@clearing_key}
      id="clear-key-confirm"
      show
      title="Clear this key?"
      subtitle={clear_key_identity(@clearing_key)}
      on_cancel={JS.push("cancel_clear_key")}
    >
      <:body>
        <p class="td-note">{clear_key_fallback(@clearing_key)}</p>
      </:body>
      <:footer>
        <.td_button
          type="button"
          variant="secondary"
          label="Cancel"
          phx-click="cancel_clear_key"
        />
        <.td_button
          :if={@clearing_key.kind == :tnt}
          id="confirm-clear-key"
          type="button"
          variant="danger-confirm"
          label="Clear key"
          phx-click="clear_api_key"
          phx-value-tier={@clearing_key.tier}
        />
        <.td_button
          :if={@clearing_key.kind == :gs1}
          id="confirm-clear-key"
          type="button"
          variant="danger-confirm"
          label="Clear key"
          phx-click="clear_gs1_key"
        />
      </:footer>
    </.td_modal>
    """
  end

  def render(assigns) do
    if assigns.onboarding? do
      render_onboarding(assigns)
    else
      render_default(assigns)
    end
  end

  defp render_onboarding(assigns) do
    organization = assigns.organization
    tiers = relevant_tiers(organization)

    assigns =
      assigns
      |> assign(:tiers, tiers)
      |> assign(:keys_needed?, keys_needed?(organization, tiers))

    ~H"""
    <.onboarding_task_shell
      flash={@flash}
      current_scope={@current_scope}
      icon="hero-key"
      title="Connect your tracing keys"
      description="Add your EPCIS keys so PPB reporting works."
      progress_current={elem(@onboarding_progress, 0)}
      progress_total={elem(@onboarding_progress, 1)}
    >
      <:right>
        <div>
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">API keys</h2>
          <p class="mt-2 text-sm leading-6 text-thamani-pewter">
            Credentials this organization uses with PPB Track &amp; Trace.
          </p>
        </div>

        <div :if={@tiers != []} id="keys-epcis-tiers" class="td-card mt-6">
          <.api_key_row
            :for={tier <- @tiers}
            tier={tier}
            last4={key_last4(@organization, tier)}
            editing={@editing_key_tier == tier}
          />
        </div>
      </:right>

      <:footer>
        <div class="flex items-center gap-4">
          <.link
            id="keys-onboarding-back"
            navigate={~p"/onboarding"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:text-[var(--thamani-forest)]"
          >
            <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
          </.link>
          <.link
            id="keys-onboarding-skip"
            navigate={~p"/onboarding?skip=connect_keys"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] underline decoration-[color-mix(in_srgb,var(--thamani-pewter)_45%,transparent)] underline-offset-4 transition-colors hover:text-[var(--thamani-forest)]"
          >
            Skip this step
          </.link>
        </div>
        <button
          id="keys-onboarding-continue"
          type="button"
          phx-click="continue_onboarding"
          class="inline-flex min-h-12 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg"
        >
          Continue <.icon name="hero-arrow-right" class="ml-3 size-4" />
        </button>
      </:footer>
    </.onboarding_task_shell>
    <.clear_key_modal clearing_key={@clearing_key} />
    """
  end

  defp render_default(assigns) do
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
      <.td_detail_page
        title="API keys"
        subtitle="Credentials this organization uses with PPB Track & Trace and GS1."
      >
        <:body>
          <div class="td-pad is-account">
            <section
              id="epcis-api-key-settings"
              class="td-card"
            >
              <.td_card_header
                title={if(@keys_needed?, do: "Add your TNT API key", else: "TNT API key")}
                subtitle={
                  if @keys_needed? do
                    "Events are reported with your organization's TNT API key. Add it before you send anything. The TrackIQ Partner Portal is where you register and copy the key."
                  else
                    "Events are reported with the key saved here."
                  end
                }
              >
                <:actions>
                  <.td_button
                    variant="secondary"
                    label="Partner Portal"
                    glyph="arrow-up-right"
                    href="https://trackiq.apeiro-digital.com/"
                    target="_blank"
                    rel="noopener noreferrer"
                  />
                </:actions>
              </.td_card_header>

              <div :if={@tiers == []} class="td-key-row">
                <div class="td-key-row-value is-empty">
                  This organization has no distributor or facility reporting tier yet.
                </div>
              </div>

              <.api_key_row
                :for={tier <- @tiers}
                tier={tier}
                last4={key_last4(@organization, tier)}
                editing={@editing_key_tier == tier}
              />
            </section>

            <section id="gs1-api-key-settings" class="td-card">
              <.td_card_header
                title="GS1 API key"
                subtitle="Bearer token for the GS1 member API, used when creating an SSCC and fetching the serials in a case. Leave it empty to use the platform token."
              />

              <div id="gs1-api-key-row" class={["td-key-row", @editing_gs1 && "is-editing"]}>
                <div class="td-key-row-meta">
                  <b>Member API</b>
                  <span>SSCC creation and case contents</span>
                </div>

                <form
                  :if={@editing_gs1}
                  id="gs1-api-key-form"
                  phx-submit="save_gs1_key"
                  class="td-key-row-form"
                >
                  <.td_input
                    id="gs1-api-key-input"
                    type="password"
                    name="key"
                    label="GS1 API key"
                    autocomplete="off"
                    placeholder="Paste the GS1 member API key"
                  />
                  <.td_button type="submit" variant="primary" label="Save" />
                  <.td_button
                    type="button"
                    variant="secondary"
                    label="Cancel"
                    phx-click="cancel_gs1_key"
                  />
                </form>

                <div
                  :if={!@editing_gs1}
                  class={["td-key-row-value", is_nil(@organization.gs1_api_key_last4) && "is-empty"]}
                >
                  <%= if @organization.gs1_api_key_last4 do %>
                    Key ending <code>{@organization.gs1_api_key_last4}</code>
                  <% else %>
                    No key saved
                  <% end %>
                </div>
                <div :if={!@editing_gs1} class="td-key-row-actions">
                  <.td_button
                    type="button"
                    id="edit-gs1-key"
                    phx-click="edit_gs1_key"
                    variant={if(@organization.gs1_api_key_last4, do: "secondary", else: "primary")}
                    glyph={if(@organization.gs1_api_key_last4, do: nil, else: "plus")}
                    label={if(@organization.gs1_api_key_last4, do: "Replace", else: "Add key")}
                  />
                  <.td_button
                    :if={@organization.gs1_api_key_last4}
                    type="button"
                    id="clear-gs1-key"
                    variant="secondary"
                    label="Clear"
                    phx-click="prompt_clear_gs1_key"
                  />
                </div>
              </div>
            </section>
          </div>
        </:body>
      </.td_detail_page>
      <.clear_key_modal clearing_key={@clearing_key} />
    </.keys_shell>
    """
  end
end
