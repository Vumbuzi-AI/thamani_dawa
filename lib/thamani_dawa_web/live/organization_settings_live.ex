defmodule ThamaniDawaWeb.OrganizationSettingsLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Grp
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.OrganizationGs1Prefix
  alias ThamaniDawaWeb.Portals

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(org_id)

    portal = resolve_portal(socket.assigns.current_scope)

    current_path =
      case portal do
        :organization -> ~p"/org/settings"
        :manufacturer -> ~p"/manufacturer/settings"
        :distributor -> ~p"/distributor/settings"
      end

    {:ok,
     socket
     |> assign(:page_title, "Organization settings")
     |> assign(:portal, portal)
     |> assign(:current_path, current_path)
     |> assign(:organization, organization)
     |> assign(:gln_check, :idle)
     |> assign(:gln_check_value, nil)
     |> assign(:remove_prefix, nil)
     |> assign(
       :form,
       to_form(Organizations.change_organization_settings(organization), as: :organization)
     )
     |> assign_gs1_prefixes()
     |> assign(
       :add_prefix_form,
       to_form(Organizations.change_gs1_prefix(%{}), as: :organization_gs1_prefix)
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

  def handle_event("validate", %{"organization" => params} = raw_params, socket) do
    changeset =
      socket.assigns.organization
      |> Organizations.change_organization_settings(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :organization))
     |> maybe_check_gln(raw_params, params)}
  end

  def handle_event("save", %{"organization" => params}, socket) do
    case Organizations.update_organization_settings(socket.assigns.organization, params) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization settings saved.")
         |> assign(:organization, organization)
         |> apply_known_verifications(organization)
         |> assign(
           :form,
           to_form(Organizations.change_organization_settings(organization),
             as: :organization
           )
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :organization))}
    end
  end

  def handle_event("set_submission_mode", %{"mode" => mode}, socket)
      when mode in ["automatic", "manual"] do
    case Organizations.update_epcis_submission_mode(socket.assigns.organization, mode) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> assign(:organization, organization)
         |> put_flash(
           :info,
           if(mode == "automatic",
             do: "EPCIS events will now be sent to PPB automatically.",
             else: "EPCIS events will now wait as pending until you approve and send them."
           )
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update the EPCIS submission mode.")}
    end
  end

  def handle_event("add_gs1_prefix", %{"organization_gs1_prefix" => params}, socket) do
    case Organizations.add_gs1_prefix(socket.assigns.organization, params) do
      {:ok, _prefix} ->
        {:noreply,
         socket
         |> put_flash(:info, "GS1 company prefix added.")
         |> assign_gs1_prefixes()
         |> assign(
           :add_prefix_form,
           to_form(Organizations.change_gs1_prefix(%{}), as: :organization_gs1_prefix)
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :add_prefix_form, to_form(changeset, as: :organization_gs1_prefix))}
    end
  end

  def handle_event("set_primary_gs1_prefix", %{"id" => id}, socket) do
    case find_prefix(socket, id) do
      %OrganizationGs1Prefix{} = prefix ->
        {:ok, _updated} = Organizations.set_primary_gs1_prefix(prefix)

        {:noreply,
         socket
         |> put_flash(:info, "Primary GS1 company prefix updated.")
         |> assign_gs1_prefixes()}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("ask_remove_prefix", %{"id" => id}, socket) do
    {:noreply, assign(socket, :remove_prefix, find_prefix(socket, id))}
  end

  def handle_event("cancel_remove_prefix", _params, socket) do
    {:noreply, assign(socket, :remove_prefix, nil)}
  end

  def handle_event("confirm_remove_prefix", _params, socket) do
    case socket.assigns.remove_prefix do
      %OrganizationGs1Prefix{} = prefix ->
        {:ok, _} = Organizations.delete_gs1_prefix(prefix)

        {:noreply,
         socket
         |> assign(:remove_prefix, nil)
         |> put_flash(:info, "GS1 company prefix removed.")
         |> assign_gs1_prefixes()}

      _ ->
        {:noreply, assign(socket, :remove_prefix, nil)}
    end
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :verified, licence}}, socket) do
    matched = {:matched, socket.assigns.gln_check_value, licensee_name(licence)}
    {:noreply, assign(socket, :gln_check, matched)}
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :inactive, licence}}, socket) do
    inactive = {:inactive, socket.assigns.gln_check_value, licensee_name(licence)}
    {:noreply, assign(socket, :gln_check, inactive)}
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :not_verified}}, socket) do
    {:noreply, assign(socket, :gln_check, :not_found)}
  end

  def handle_async(:gln_lookup, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, :gln_check, :unavailable)}
  end

  def handle_async(:gln_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :gln_check, :unavailable)}
  end

  defp maybe_check_gln(socket, raw_params, params) do
    if Map.get(raw_params, "_target") == ["organization", "gln"] do
      check_gln(socket, params)
    else
      socket
    end
  end

  defp check_gln(socket, params) do
    gln = params |> Map.get("gln", "") |> to_string() |> String.trim()

    cond do
      not Regex.match?(~r/^\d{13}$/, gln) ->
        assign(socket, :gln_check, :idle)

      not gln_check_digit_valid?(gln) ->
        assign(socket, :gln_check, :invalid_check_digit)

      true ->
        socket
        |> assign(:gln_check, :checking)
        |> assign(:gln_check_value, gln)
        |> start_async(:gln_lookup, fn -> Grp.verify_gln(gln) end)
    end
  end

  defp gln_check_digit_valid?(gln) do
    {payload, check} = String.split_at(gln, -1)
    Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(payload)) == check
  end

  defp licensee_name(licence) when is_map(licence) do
    Enum.find_value(
      ["licenseeName", "partyName", "organizationName", "companyName", "name"],
      fn key ->
        case Map.get(licence, key) do
          value when is_binary(value) and value != "" -> value
          _ -> nil
        end
      end
    )
  end

  defp licensee_name(_licence), do: nil

  defp apply_known_verifications(socket, organization) do
    apply_known_gln_verification(socket, organization)
  end

  defp apply_known_gln_verification(socket, organization) do
    case socket.assigns.gln_check do
      {:matched, value, _name} when value == organization.gln ->
        {:ok, organization} = Organizations.mark_gln_verified(organization)
        assign(socket, :organization, organization)

      _ ->
        socket
    end
  end

  defp operating_models_label(organization) do
    Enum.map_join(organization.operating_models, ", ", &Phoenix.Naming.humanize/1)
  end

  defp manufacturer_organization?(%{operating_models: models}) when is_list(models),
    do: :manufacturer in models

  defp manufacturer_organization?(_organization), do: false

  defp assign_gs1_prefixes(socket) do
    assign(
      socket,
      :organization_gs1_prefixes,
      Organizations.list_gs1_prefixes(socket.assigns.organization.id)
    )
  end

  defp find_prefix(socket, id) do
    Enum.find(socket.assigns.organization_gs1_prefixes, &(to_string(&1.id) == to_string(id)))
  end

  defp prefix_status(%{verification_status: :verified}), do: :verified
  defp prefix_status(%{verification_status: :failed}), do: :not_found
  defp prefix_status(_prefix), do: :pending

  defp gln_status(_organization, :checking), do: :checking
  defp gln_status(_organization, {:matched, _value, _name}), do: :verified
  defp gln_status(_organization, {:inactive, _value, _name}), do: :inactive
  defp gln_status(_organization, :not_found), do: :not_found
  defp gln_status(_organization, :invalid_check_digit), do: :invalid_check_digit
  defp gln_status(_organization, :unavailable), do: :unavailable
  defp gln_status(%{gln: gln}, _check) when gln in [nil, ""], do: :not_set

  defp gln_status(%{gln_verified_at: verified_at}, _check) when not is_nil(verified_at),
    do: :verified

  defp gln_status(_organization, _check), do: :pending

  defp matched_name({:matched, _value, name}), do: name
  defp matched_name({:inactive, _value, name}), do: name
  defp matched_name(_check), do: nil

  defp status_label(:checking), do: "Checking with GS1…"
  defp status_label(:verified), do: "Verified with GS1"
  defp status_label(:inactive), do: "Found, but not active in the registry"
  defp status_label(:not_found), do: "Not found in registry"
  defp status_label(:invalid_check_digit), do: "Invalid check digit"
  defp status_label(:unavailable), do: "Couldn't reach the GS1 registry"
  defp status_label(:not_set), do: "Not set"
  defp status_label(:pending), do: "Pending verification"

  defp status_tone(:verified), do: "success"

  defp status_tone(status)
       when status in [:not_found, :unavailable, :invalid_check_digit, :inactive],
       do: "warning"

  defp status_tone(_status), do: "neutral"

  attr :portal, :atom, required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  defp settings_shell(%{portal: :organization} = assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      {render_slot(@inner_block)}
    </Layouts.org_shell>
    """
  end

  defp settings_shell(%{portal: :manufacturer} = assigns) do
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

  defp settings_shell(assigns) do
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

  def render(assigns) do
    ~H"""
    <.settings_shell
      portal={@portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      <.td_detail_page
        title="Organization settings"
        subtitle="GS1 prefixes, GLN and how this organization appears to trading partners."
      >
        <:actions>
          <.td_button
            id="save-organization-settings"
            type="submit"
            form="distributor-gs1-settings-form"
            variant="primary"
            label="Save"
          />
        </:actions>
        <:body>
          <div class="td-pad is-account">
            <.form
              for={@form}
              id="distributor-gs1-settings-form"
              phx-change="validate"
              phx-submit="save"
              class="td-card"
            >
              <.td_card_header
                title="Identity"
                subtitle="Used on SSCCs, serials and EPCIS events."
              />
              <div class="td-card-body">
                <div class="td-g2">
                  <label class="td-field">
                    <span class="td-field-label">Legal name</span>
                    <span class="td-field-static">{@organization.name}</span>
                  </label>
                  <.td_input field={@form[:license_number]} label="License number" required />
                  <label class="td-field">
                    <span class="td-field-label">Operating model</span>
                    <span class="td-field-static">{operating_models_label(@organization)}</span>
                  </label>
                  <.td_input
                    field={@form[:gln]}
                    label="Organization GLN"
                    placeholder="13-digit Global Location Number"
                    maxlength="13"
                    inputmode="numeric"
                  />
                </div>
                <label class="td-cb">
                  <input type="hidden" name={@form[:vat_registered].name} value="false" />
                  <input
                    type="checkbox"
                    id={@form[:vat_registered].id}
                    name={@form[:vat_registered].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value("checkbox", @form[:vat_registered].value)
                    }
                  /> VAT registered
                </label>
                <label :if={manufacturer_organization?(@organization)} class="td-cb">
                  <input
                    type="hidden"
                    name={@form[:stock_serialization_enabled].name}
                    value="false"
                  />
                  <input
                    type="checkbox"
                    id="organization-stock-serialization-enabled"
                    name={@form[:stock_serialization_enabled].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        @form[:stock_serialization_enabled].value
                      )
                    }
                  /> Allow manufacturing for stock during serial generation
                  <span class="td-hint">
                    Off by default. This only controls the explicit “manufacturing for stock”
                    choice in the serial wizard. Order and destination fields are optional either
                    way; leaving them blank defers them to shipper and pallet creation.
                  </span>
                </label>
                <p id="gs1-verification-status" class="td-hint">
                  <.td_badge
                    tone={status_tone(gln_status(@organization, @gln_check))}
                    label={status_label(gln_status(@organization, @gln_check))}
                  />
                  <span :if={matched_name(@gln_check)}>Matches {matched_name(@gln_check)}</span>
                </p>
              </div>
            </.form>

            <section class="td-card">
              <.td_card_header
                title="GS1 company prefixes"
                subtitle="Used to build GTINs and SSCCs. The primary prefix is the one new identifiers are issued under."
              />
              <table :if={@organization_gs1_prefixes != []} id="gs1-prefixes-list" class="td-rows">
                <thead>
                  <tr>
                    <th>Prefix</th>
                    <th>Status</th>
                    <th><span class="sr-only">Actions</span></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={prefix <- @organization_gs1_prefixes} id={"gs1-prefix-#{prefix.id}"}>
                    <td>
                      <span class="td-mono">{prefix.prefix}</span>
                      <.td_badge :if={prefix.is_primary} tone="neutral" label="Primary" />
                    </td>
                    <td>
                      <.td_badge
                        tone={status_tone(prefix_status(prefix))}
                        label={status_label(prefix_status(prefix))}
                      />
                    </td>
                    <td class="td-row-actions">
                      <.td_button
                        :if={!prefix.is_primary}
                        type="button"
                        variant="secondary"
                        label="Make primary"
                        phx-click="set_primary_gs1_prefix"
                        phx-value-id={prefix.id}
                      />
                      <.td_button
                        type="button"
                        variant="danger"
                        label="Remove"
                        phx-click="ask_remove_prefix"
                        phx-value-id={prefix.id}
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
              <p :if={@organization_gs1_prefixes == []} class="td-card-body td-note">
                No GS1 company prefixes yet.
              </p>
              <.form
                for={@add_prefix_form}
                id="add-gs1-prefix-form"
                phx-submit="add_gs1_prefix"
                class="td-card-body is-row"
              >
                <.td_input
                  field={@add_prefix_form[:prefix]}
                  label="Add a GS1 company prefix"
                  placeholder="e.g. 0614141"
                  maxlength="10"
                  inputmode="numeric"
                />
                <.td_button type="submit" variant="primary" label="Add prefix" />
              </.form>
            </section>

            <section id="epcis-submission-settings" class="td-card">
              <.td_card_header
                title="How events are sent"
                subtitle={
                  if @organization.epcis_submission_mode == :automatic,
                    do: "Events go to PPB as soon as they are queued.",
                    else: "Events stay pending until someone approves and sends them."
                }
              />
              <div class="td-tnt-controls">
                <.td_segmented>
                  <.td_segment
                    id="settings-epcis-mode-automatic"
                    label="Automatic"
                    active={@organization.epcis_submission_mode == :automatic}
                    phx-click="set_submission_mode"
                    phx-value-mode="automatic"
                    aria-pressed={to_string(@organization.epcis_submission_mode == :automatic)}
                  />
                  <.td_segment
                    id="settings-epcis-mode-manual"
                    label="Manual"
                    active={@organization.epcis_submission_mode == :manual}
                    phx-click="set_submission_mode"
                    phx-value-mode="manual"
                    aria-pressed={to_string(@organization.epcis_submission_mode == :manual)}
                  />
                </.td_segmented>
              </div>
            </section>
          </div>
        </:body>
      </.td_detail_page>

      <.td_confirm
        :if={@remove_prefix}
        id="remove-gs1-prefix-modal"
        title={"Remove prefix #{@remove_prefix.prefix}?"}
        body="New GTINs and SSCCs will not be issued under this prefix. Existing identifiers stay as they are."
        confirm="Remove prefix"
        confirm_click="confirm_remove_prefix"
        on_cancel={JS.push("cancel_remove_prefix")}
      />
    </.settings_shell>
    """
  end
end
