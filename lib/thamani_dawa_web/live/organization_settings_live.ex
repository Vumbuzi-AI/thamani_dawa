defmodule ThamaniDawaWeb.OrganizationSettingsLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Grp
  alias ThamaniDawa.Organizations

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(org_id)

    portal = if Scope.admin?(socket.assigns.current_scope), do: :organization, else: :distributor

    current_path =
      if portal == :organization, do: ~p"/org/settings", else: ~p"/distributor/settings"

    {:ok,
     socket
     |> assign(:page_title, "Organization settings")
     |> assign(:portal, portal)
     |> assign(:current_path, current_path)
     |> assign(:organization, organization)
     |> assign(:gln_check, :idle)
     |> assign(:gln_check_value, nil)
     |> assign(
       :form,
       to_form(Organizations.change_organization_settings(organization), as: :organization)
     )}
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

  def handle_async(:gln_lookup, {:ok, {:ok, :verified, licence}}, socket) do
    matched = {:matched, socket.assigns.gln_check_value, licensee_name(licence)}
    {:noreply, assign(socket, :gln_check, matched)}
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

  defp prefix_status(%{gs1_prefix_verification_status: :verified}), do: :verified
  defp prefix_status(%{gs1_prefix_verification_status: :failed}), do: :not_found
  defp prefix_status(_organization), do: :pending

  defp gln_status(_organization, :checking), do: :checking
  defp gln_status(_organization, {:matched, _value, _name}), do: :verified
  defp gln_status(_organization, :not_found), do: :not_found
  defp gln_status(_organization, :invalid_check_digit), do: :invalid_check_digit
  defp gln_status(_organization, :unavailable), do: :unavailable
  defp gln_status(%{gln: gln}, _check) when gln in [nil, ""], do: :not_set

  defp gln_status(%{gln_verified_at: verified_at}, _check) when not is_nil(verified_at),
    do: :verified

  defp gln_status(_organization, _check), do: :pending

  defp matched_name({:matched, _value, name}), do: name
  defp matched_name(_check), do: nil

  defp status_label(:checking), do: "Checking with GS1…"
  defp status_label(:verified), do: "Verified with GS1"
  defp status_label(:not_found), do: "Not found in registry"
  defp status_label(:invalid_check_digit), do: "Invalid check digit"
  defp status_label(:unavailable), do: "Couldn't reach the GS1 registry"
  defp status_label(:not_set), do: "Not set"
  defp status_label(:pending), do: "Pending verification"

  defp status_class(status) when status in [:verified], do: "text-green-700"

  defp status_class(status) when status in [:not_found, :unavailable, :invalid_check_digit],
    do: "text-amber-700"

  defp status_class(_status), do: "text-thamani-pewter"

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
      <.header icon="hero-cog-6-tooth">
        Organization settings
        <:subtitle>
          Your organization's identity and the GS1 identifiers it issues or reports under.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="distributor-gs1-settings-form"
        phx-change="validate"
        phx-submit="save"
        class="mt-6 overflow-hidden rounded-2xl border border-thamani-stone bg-white shadow-sm"
      >
        <div class="p-6 lg:p-8">
          <section
            class="border-b border-thamani-stone pb-8"
            aria-labelledby="organization-details-heading"
          >
            <div class="mb-5">
              <h2
                id="organization-details-heading"
                class="text-base font-semibold text-thamani-forest"
              >
                Organization details
              </h2>
              <p class="mt-1 text-sm text-thamani-pewter">
                Business identity and statutory information.
              </p>
            </div>

            <div class="grid gap-x-7 lg:grid-cols-2">
              <div>
                <span class="thamani-label">Name</span>
                <div class="flex min-h-11 items-center rounded-lg border border-thamani-border-nav bg-thamani-canvas px-3.5 text-sm font-medium text-thamani-forest">
                  {@organization.name}
                </div>
              </div>
              <.input field={@form[:license_number]} label="License number" required />
              <div>
                <span class="thamani-label">Operating model</span>
                <div class="flex min-h-11 items-center rounded-lg border border-thamani-border-nav bg-thamani-canvas px-3.5 text-sm font-medium text-thamani-forest">
                  {operating_models_label(@organization)}
                </div>
              </div>
              <div class="flex items-center pt-2 lg:pt-7">
                <.input
                  field={@form[:vat_registered]}
                  type="checkbox"
                  label="VAT registered"
                  class="relative h-7 w-12 shrink-0 cursor-pointer appearance-none rounded-full bg-slate-300 transition-colors before:absolute before:left-1 before:top-1 before:size-5 before:rounded-full before:bg-white before:shadow-sm before:transition-transform checked:bg-thamani-forest checked:before:translate-x-5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
                />
              </div>
            </div>
          </section>

          <section
            class="pt-8"
            aria-labelledby="gs1-identifiers-heading"
          >
            <div class="mb-5">
              <h2 id="gs1-identifiers-heading" class="text-base font-semibold text-thamani-forest">
                GS1 identifiers
              </h2>
              <p class="mt-1 text-sm leading-5 text-thamani-pewter">
                Used for globally unique logistics identifiers and organization-level events.
              </p>
            </div>

            <div class="grid gap-x-7 lg:grid-cols-2">
              <div>
                <span class="thamani-label">GS1 company prefix</span>
                <div class="flex min-h-11 items-center rounded-lg border border-thamani-border-nav bg-thamani-canvas px-3.5 text-sm font-medium text-thamani-forest">
                  {@organization.gs1_company_prefix || "—"}
                </div>
              </div>
              <div class="relative">
                <.input
                  field={@form[:gln]}
                  label="Organization GLN (optional)"
                  placeholder="13-digit Global Location Number"
                  maxlength="13"
                  inputmode="numeric"
                />
                <.icon
                  :if={@gln_check == :checking}
                  name="hero-arrow-path"
                  class="absolute right-3 top-10 size-5 animate-spin text-thamani-pewter"
                />
                <.icon
                  :if={gln_status(@organization, @gln_check) == :verified}
                  name="hero-check"
                  class="absolute right-3 top-10 size-5 text-green-700"
                />
              </div>
            </div>

            <div
              id="gs1-verification-status"
              class="mt-3 grid gap-1.5 rounded-xl bg-thamani-canvas px-4 py-3 text-xs leading-5 sm:grid-cols-2"
            >
              <p :if={@organization.gs1_company_prefix not in [nil, ""]}>
                <span class={status_class(prefix_status(@organization))}>
                  {status_label(prefix_status(@organization))}
                </span>
                <span class="text-thamani-pewter"> · {@organization.next_sscc_serial} SSCC(s) issued</span>
              </p>
              <p>
                Organization GLN:
                <span class={status_class(gln_status(@organization, @gln_check))}>
                  {status_label(gln_status(@organization, @gln_check))}
                </span>
                <span :if={matched_name(@gln_check)} class="text-thamani-pewter">
                  — matches {matched_name(@gln_check)}
                </span>
              </p>
            </div>
          </section>
        </div>

        <div class="flex justify-end border-t border-thamani-stone bg-thamani-canvas/40 px-6 py-4 lg:px-8">
          <.button id="save-organization-settings" variant="primary" class="min-w-40">Save changes</.button>
        </div>
      </.form>
    </.settings_shell>
    """
  end
end
