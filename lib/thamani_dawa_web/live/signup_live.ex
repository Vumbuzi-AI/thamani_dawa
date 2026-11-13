defmodule ThamaniDawaWeb.SignupLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Grp
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Sites.Site

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        :org_form,
        to_form(
          Organization.changeset(%Organization{operating_models: []}, %{}),
          as: :organization
        )
      )
      |> assign(:site_form, to_form(Site.default_changeset(%Site{}, %{}), as: :site))
      |> assign(
        :admin_form,
        to_form(
          User.registration_changeset(%User{}, %{},
            hash_password: false,
            require_legal_consent: true
          ),
          as: :user
        )
      )
      |> assign(:step, :organization)
      |> assign(:organization_params, nil)
      |> assign(:site_params, nil)
      |> assign(:prefix_check, :idle)
      |> assign(:gln_check, :idle)
      |> assign(:admin_first_name, "")
      |> assign(:admin_last_name, "")
      |> assign(:trigger_login, false)

    {:ok, socket}
  end

  def handle_event("validate_organization", params, socket) do
    org_params = params |> Map.get("organization", %{}) |> normalize_operating_models()

    org_changeset =
      %Organization{}
      |> Organization.signup_changeset(org_params)
      |> Map.put(:action, :validate)

    site_form =
      if Map.get(params, "_target") == ["organization", "operating_models"] do
        site_changeset =
          %Site{}
          |> Site.default_changeset(%{"activities" => suggested_site_activities(org_params)})
          |> Map.put(:action, :validate)

        to_form(site_changeset, as: :site)
      else
        socket.assigns.site_form
      end

    {:noreply,
     socket
     |> assign(:org_form, to_form(org_changeset, as: :organization))
     |> assign(:site_form, site_form)
     |> maybe_check_gs1_prefix(params, org_params)}
  end

  def handle_event("continue", %{"organization" => org_params} = params, socket) do
    org_params = normalize_operating_models(org_params)
    org_changeset = Organization.signup_changeset(%Organization{}, org_params)

    cond do
      not org_changeset.valid? ->
        {:noreply,
         assign(
           socket,
           :org_form,
           to_form(%{org_changeset | action: :validate}, as: :organization)
         )}

      socket.assigns.prefix_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still checking your GS1 company prefix with the GS1 registry — press Continue again in a moment."
         )}

      socket.assigns.prefix_check == :idle ->
        {:noreply,
         socket
         |> maybe_check_gs1_prefix(
           Map.put(params, "_target", ["organization", "gs1_company_prefix"]),
           org_params
         )
         |> put_flash(
           :error,
           "Checking your GS1 company prefix with the GS1 registry — press Continue again in a moment."
         )}

      socket.assigns.prefix_check == :not_found ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "We couldn't find this GS1 company prefix in the registry. Please double-check the number before continuing."
         )}

      true ->
        site_changeset =
          %Site{}
          |> Site.default_changeset(%{"activities" => suggested_site_activities(org_params)})
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:step, :site)
         |> assign(:organization_params, org_params)
         |> assign(:org_form, to_form(org_changeset, as: :organization))
         |> assign(:site_form, to_form(site_changeset, as: :site))}
    end
  end

  def handle_event("validate_site", params, socket) do
    site_params = params |> Map.get("site", %{}) |> normalize_activities()

    site_changeset =
      %Site{}
      |> Site.default_changeset(site_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:site_form, to_form(site_changeset, as: :site))
     |> maybe_check_gln(params, site_params)}
  end

  def handle_event("continue_site", %{"site" => site_params} = params, socket) do
    site_params = normalize_activities(site_params)
    site_changeset = Site.default_changeset(%Site{}, site_params)

    cond do
      not site_changeset.valid? ->
        {:noreply,
         assign(socket, :site_form, to_form(%{site_changeset | action: :validate}, as: :site))}

      gln_present?(site_params) and socket.assigns.gln_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still checking the site GLN with the GS1 registry — press Continue again in a moment."
         )}

      gln_present?(site_params) and socket.assigns.gln_check == :idle ->
        {:noreply,
         socket
         |> maybe_check_gln(Map.put(params, "_target", ["site", "gln"]), site_params)
         |> put_flash(
           :error,
           "Checking the site GLN with the GS1 registry — press Continue again in a moment."
         )}

      gln_present?(site_params) and socket.assigns.gln_check == :not_found ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "We couldn't find this GLN in the GS1 registry. Please double-check the number before continuing."
         )}

      true ->
        {:noreply,
         socket
         |> assign(:step, :administrator)
         |> assign(:site_params, site_params)
         |> assign(:site_form, to_form(site_changeset, as: :site))}
    end
  end

  def handle_event("validate_administrator", %{"user" => admin_params}, socket) do
    admin_params = compose_admin_name(admin_params)

    changeset =
      %User{}
      |> User.registration_changeset(admin_params,
        hash_password: false,
        require_legal_consent: true
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:admin_form, to_form(changeset, as: :user))
     |> assign(:admin_first_name, Map.get(admin_params, "first_name", ""))
     |> assign(:admin_last_name, Map.get(admin_params, "last_name", ""))}
  end

  def handle_event("back", %{"from" => "site"}, socket) do
    {:noreply, assign(socket, :step, :organization)}
  end

  def handle_event("back", %{"from" => "administrator"}, socket) do
    {:noreply, assign(socket, :step, :site)}
  end

  def handle_event("save", %{"user" => admin_params}, socket) do
    admin_params = compose_admin_name(admin_params)

    case Organizations.signup(
           socket.assigns.organization_params,
           socket.assigns.site_params,
           admin_params
         ) do
      {:ok, _result} ->
        {:noreply, assign(socket, :trigger_login, true)}

      {:error, %Ecto.Changeset{data: %Organization{}} = changeset} ->
        {:noreply,
         socket
         |> assign(:step, :organization)
         |> assign(:org_form, to_form(changeset, as: :organization))}

      {:error, %Ecto.Changeset{data: %Site{}} = changeset} ->
        {:noreply,
         socket
         |> assign(:step, :site)
         |> assign(:site_form, to_form(changeset, as: :site))}

      {:error, %Ecto.Changeset{data: %User{}} = changeset} ->
        {:noreply, assign(socket, :admin_form, to_form(changeset, as: :user))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Something went wrong setting up your organization. Please try again."
         )}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def handle_async(:gs1_prefix_lookup, {:ok, {:ok, :verified, licence}}, socket) do
    {:noreply,
     socket |> clear_flash(:error) |> assign(:prefix_check, {:matched, licensee_name(licence)})}
  end

  def handle_async(:gs1_prefix_lookup, {:ok, {:ok, :not_verified}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:prefix_check, :not_found)}
  end

  def handle_async(:gs1_prefix_lookup, {:ok, {:error, _reason}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:prefix_check, :unavailable)}
  end

  def handle_async(:gs1_prefix_lookup, {:exit, _reason}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:prefix_check, :unavailable)}
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :verified, licence}}, socket) do
    {:noreply,
     socket |> clear_flash(:error) |> assign(:gln_check, {:matched, licensee_name(licence)})}
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :not_verified}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:gln_check, :not_found)}
  end

  def handle_async(:gln_lookup, {:ok, {:error, _reason}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:gln_check, :unavailable)}
  end

  def handle_async(:gln_lookup, {:exit, _reason}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:gln_check, :unavailable)}
  end

  defp normalize_operating_models(params) do
    Map.update(params, "operating_models", [], fn models ->
      Enum.reject(models, &(&1 in [nil, ""]))
    end)
  end

  defp compose_admin_name(admin_params) do
    first = admin_params |> Map.get("first_name", "") |> to_string() |> String.trim()
    last = admin_params |> Map.get("last_name", "") |> to_string() |> String.trim()
    name = [first, last] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")

    Map.put(admin_params, "name", name)
  end

  defp normalize_activities(params) do
    Map.update(params, "activities", [], fn activities ->
      Enum.reject(activities, &(&1 in [nil, ""]))
    end)
  end

  defp maybe_check_gs1_prefix(socket, params, org_params) do
    if Map.get(params, "_target") == ["organization", "gs1_company_prefix"] do
      check_gs1_prefix(socket, org_params)
    else
      socket
    end
  end

  defp check_gs1_prefix(socket, org_params) do
    prefix = org_params |> Map.get("gs1_company_prefix", "") |> to_string() |> String.trim()

    if Regex.match?(~r/^\d{6,10}$/, prefix) do
      socket
      |> assign(:prefix_check, :checking)
      |> start_async(:gs1_prefix_lookup, fn -> Grp.verify_prefix(prefix) end)
    else
      assign(socket, :prefix_check, :idle)
    end
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

  defp maybe_check_gln(socket, params, site_params) do
    if Map.get(params, "_target") == ["site", "gln"] do
      check_gln(socket, site_params)
    else
      socket
    end
  end

  defp check_gln(socket, site_params) do
    gln = site_params |> Map.get("gln", "") |> to_string() |> String.trim()

    cond do
      not Regex.match?(~r/^\d{13}$/, gln) ->
        assign(socket, :gln_check, :idle)

      not gln_check_digit_valid?(gln) ->
        assign(socket, :gln_check, :invalid_check_digit)

      true ->
        socket
        |> assign(:gln_check, :checking)
        |> start_async(:gln_lookup, fn -> Grp.verify_gln(gln) end)
    end
  end

  defp gln_check_digit_valid?(gln) do
    {payload, check} = String.split_at(gln, -1)
    Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(payload)) == check
  end

  defp gln_present?(site_params) do
    site_params |> Map.get("gln", "") |> to_string() |> String.trim() != ""
  end

  defp gln_entered?(site_form) do
    site_form[:gln].value |> to_string() |> String.trim() != ""
  end

  defp suggested_site_activities(org_params) do
    org_params
    |> Map.get("operating_models", [])
    |> Enum.flat_map(fn
      "pharmacy" -> ["pharmacy"]
      "laboratory" -> ["laboratory"]
      "distributor" -> ["distribution"]
      _ -> []
    end)
  end

  defp operating_model_options do
    [
      {"pharmacy", "Pharmacy", "Dispense medicines and manage retail stock",
       "hero-building-storefront"},
      {"laboratory", "Laboratory", "Manage diagnostic tests and specimens", "hero-beaker"},
      {"distributor", "Distributor", "Warehouse and distribute medical products", "hero-truck"}
    ]
  end

  defp site_activity_options(models) do
    allowed = MapSet.new(suggested_site_activities(models))

    [
      {"pharmacy", "Pharmacy", "Dispensing & retail stock"},
      {"laboratory", "Laboratory", "Diagnostic tests & specimens"},
      {"distribution", "Distribution", "Warehouse & shipping"}
    ]
    |> Enum.filter(fn {value, _label, _description} -> value in allowed end)
  end

  defp operating_model_selected?(form, value) do
    form[:operating_models].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.member?(value)
  end

  defp selected_operating_model_count(form) do
    form[:operating_models].value
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> length()
  end

  defp site_activity_selected?(form, value) do
    form[:activities].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.member?(value)
  end

  defp selected_site_activity_count(form) do
    form[:activities].value
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> length()
  end

  defp step_number(:organization), do: 1
  defp step_number(:site), do: 2
  defp step_number(:administrator), do: 3

  def render(assigns) do
    ~H"""
    <div
      class="lg:h-svh lg:overflow-hidden"
      style="min-height: 100vh; display: flex; flex-direction: row;"
    >
      <div
        class="hidden lg:flex lg:h-svh"
        style="width: 38%; background: var(--thamani-forest); flex-direction: column; justify-content: space-between; padding: 48px 52px; position: relative; overflow: hidden;"
      >
        <.link
          navigate={~p"/"}
          aria-label="Thamani Dawa home"
          style="position: relative; width: 156px;"
        >
          <img src="/images/logo-transparent.png" alt="" class="h-auto w-full brightness-0 invert" />
        </.link>

        <div style="position: relative;">
          <span
            class="thamani-badge"
            style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px; margin-bottom: 24px; display: inline-flex;"
          >
            Free to start · No credit card
          </span>
          <h2 style="font-size: clamp(28px, 2.8vw, 40px); font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-snow); text-wrap: balance; margin: 16px 0 20px;">
            Set up your health operation in a few guided steps.
          </h2>
          <p style="font-size: 16px; line-height: 1.65; color: rgba(252,252,247,0.55); max-width: 340px;">
            Configure a pharmacy, laboratory, distribution business, or a combination — then invite your team and start operating.
          </p>
        </div>

        <div style="position: relative; border-top: 1px solid rgba(252,252,247,0.1); padding-top: 28px;">
          <p style="font-size: 15px; font-weight: 350; color: rgba(252,252,247,0.75); line-height: 1.55; font-style: italic; margin-bottom: 16px;">
            "We were up and running in a single afternoon — stock, prescriptions, everything."
          </p>
          <p style="font-size: 13px; font-weight: 500; color: rgba(252,252,247,0.45);">
            Jane Mwangi · Owner, MedPoint Pharmacy, Nakuru
          </p>
        </div>
      </div>

      <div
        class="lg:h-svh lg:overflow-y-auto"
        style="flex: 1; min-width: 0; background: var(--thamani-snow); display: flex; flex-direction: column; align-items: center; justify-content: center; padding: clamp(24px, 6vw, 48px) clamp(20px, 6vw, 40px);"
      >
        <div style="width: 100%; max-width: 560px;">
          <ThamaniDawaWeb.Layouts.flash_group flash={@flash} />

          <div id="onboarding-progress" class="mb-7" aria-label="Onboarding progress">
            <div class="flex items-center gap-3">
              <span class={[
                "flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
                step_number(@step) <= 1 && "bg-[var(--thamani-forest)] text-white",
                step_number(@step) > 1 &&
                  "bg-white text-[var(--thamani-pewter)] ring-1 ring-[var(--thamani-stone)]"
              ]}>1</span>
              <div class="h-px flex-1 bg-[var(--thamani-stone)]" />
              <span class={[
                "flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold transition-colors",
                step_number(@step) <= 2 && "bg-[var(--thamani-forest)] text-white",
                step_number(@step) > 2 &&
                  "bg-white text-[var(--thamani-pewter)] ring-1 ring-[var(--thamani-stone)]"
              ]}>2</span>
              <div class="h-px flex-1 bg-[var(--thamani-stone)]" />
              <span class={[
                "flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold transition-colors",
                step_number(@step) <= 3 && "bg-[var(--thamani-forest)] text-white",
                step_number(@step) > 3 &&
                  "bg-white text-[var(--thamani-pewter)] ring-1 ring-[var(--thamani-stone)]"
              ]}>3</span>
            </div>
            <div class="mt-2 flex items-start gap-3">
              <div class="flex w-7 shrink-0 justify-center">
                <span class={[
                  "whitespace-nowrap text-center text-[11px] font-medium",
                  if(step_number(@step) <= 1,
                    do: "text-[var(--thamani-forest)]",
                    else: "text-[var(--thamani-pewter)]"
                  )
                ]}>Organization</span>
              </div>
              <div class="flex-1" />
              <div class="flex w-7 shrink-0 justify-center">
                <span class={[
                  "whitespace-nowrap text-center text-[11px] font-medium",
                  if(step_number(@step) <= 2,
                    do: "text-[var(--thamani-forest)]",
                    else: "text-[var(--thamani-pewter)]"
                  )
                ]}>Main location</span>
              </div>
              <div class="flex-1" />
              <div class="flex w-7 shrink-0 justify-center">
                <span class={[
                  "whitespace-nowrap text-center text-[11px] font-medium",
                  if(step_number(@step) <= 3,
                    do: "text-[var(--thamani-forest)]",
                    else: "text-[var(--thamani-pewter)]"
                  )
                ]}>Administrator</span>
              </div>
            </div>
          </div>

          <%= if @step == :organization do %>
            <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
              Tell us about your organization
            </h1>
            <p class="mb-1 text-[15px] leading-6 text-[var(--thamani-pewter)]">
              Select all the services you operate. You can choose more than one.
            </p>
            <p class="mb-8 text-xs text-[var(--thamani-pewter)]">
              <span class="text-red-600">*</span> Required
            </p>

            <.form
              for={@org_form}
              id="organization-setup-form"
              phx-change="validate_organization"
              phx-submit="continue"
            >
              <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
                <.thamani_input
                  field={@org_form[:name]}
                  label="Organization name"
                  placeholder="e.g. MedPoint Health"
                  phx-debounce="blur"
                  required
                />

                <.thamani_input
                  field={@org_form[:license_number]}
                  label="License number"
                  placeholder="e.g. PPB-XXXX"
                  phx-debounce="blur"
                  required
                />
              </div>

              <fieldset class="mb-6">
                <legend class="text-sm font-medium text-[var(--thamani-forest)]">
                  What does your organization operate?<span class="text-red-600">&nbsp;*</span>
                </legend>
                <div class="mb-3 mt-1 flex items-center justify-between gap-3">
                  <p class="text-xs text-[var(--thamani-pewter)]">Select all that apply</p>
                  <%= if selected_operating_model_count(@org_form) > 0 do %>
                    <span
                      id="operating-model-selection-count"
                      class="rounded-full bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-2.5 py-1 text-[11px] font-semibold text-[var(--thamani-forest)]"
                    >
                      {selected_operating_model_count(@org_form)} selected
                    </span>
                  <% end %>
                </div>
                <input type="hidden" name="organization[operating_models][]" value="" />
                <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <%= for {value, label, description, icon} <- operating_model_options() do %>
                    <label class={[
                      "group cursor-pointer rounded-xl border-2 p-4 transition-all hover:-translate-y-0.5 hover:border-[var(--thamani-forest)] focus-within:ring-2 focus-within:ring-[var(--thamani-lime)] focus-within:ring-offset-2",
                      operating_model_selected?(@org_form, value) &&
                        "border-[var(--thamani-forest)] bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] shadow-md",
                      !operating_model_selected?(@org_form, value) &&
                        "border-[var(--thamani-stone)] bg-white"
                    ]}>
                      <input
                        type="checkbox"
                        name="organization[operating_models][]"
                        value={value}
                        checked={operating_model_selected?(@org_form, value)}
                        class="peer sr-only"
                      />
                      <div class="flex items-start justify-between gap-2">
                        <.icon name={icon} class="size-5 text-[var(--thamani-forest)]" />
                        <span class={[
                          "flex size-5 shrink-0 items-center justify-center rounded-md border transition-colors",
                          operating_model_selected?(@org_form, value) &&
                            "border-[var(--thamani-forest)] bg-[var(--thamani-forest)] text-white",
                          !operating_model_selected?(@org_form, value) &&
                            "border-[var(--thamani-stone)] bg-white text-transparent group-hover:border-[var(--thamani-forest)]"
                        ]}>
                          <.icon name="hero-check" class="size-3.5" />
                        </span>
                      </div>
                      <span class="mt-3 block text-sm font-semibold text-[var(--thamani-forest)]">{label}</span>
                      <span class="mt-1 block text-[11px] leading-4 text-[var(--thamani-pewter)]">{description}</span>
                    </label>
                  <% end %>
                </div>
                <%= for error <- @org_form[:operating_models].errors do %>
                  <p class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
                <% end %>
              </fieldset>

              <div>
                <.thamani_input
                  field={@org_form[:gs1_company_prefix]}
                  label="GS1 company prefix"
                  placeholder="e.g. 6160001"
                  phx-debounce="blur"
                  required
                />
                <%= case @prefix_check do %>
                  <% :checking -> %>
                    <p class="mb-6 -mt-4 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--thamani-pewter)]">
                      <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                      Checking with the GS1 registry&hellip;
                    </p>
                  <% {:matched, name} when is_binary(name) -> %>
                    <p class="mb-6 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2 text-xs font-semibold text-[var(--thamani-forest)]">
                      <.icon name="hero-check-circle" class="size-4" /> Verified — matches {name}
                    </p>
                  <% {:matched, nil} -> %>
                    <p class="mb-6 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2 text-xs font-semibold text-[var(--thamani-forest)]">
                      <.icon name="hero-check-circle" class="size-4" /> Verified with GS1
                    </p>
                  <% :not_found -> %>
                    <p class="mb-6 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                      <.icon name="hero-exclamation-triangle" class="size-4" />
                      We couldn't find this prefix in the GS1 registry. Double-check the number before continuing.
                    </p>
                  <% _ -> %>
                    <p class="mb-6 -mt-4 text-xs text-[var(--thamani-pewter)]">
                      Issued to you by GS1 Kenya. We verify it with the GS1 registry after setup.
                    </p>
                <% end %>
              </div>

              <.thamani_btn
                id="onboarding-continue"
                type="submit"
                variant="primary"
                disabled={@prefix_check == :checking}
              >
                <%= if @prefix_check == :checking do %>
                  <.icon name="hero-arrow-path" class="mr-2 size-4 animate-spin" />
                  Checking GS1 registry&hellip;
                <% else %>
                  Continue <.icon name="hero-arrow-right" class="ml-2 size-4" />
                <% end %>
              </.thamani_btn>
            </.form>
          <% else %>
            <%= if @step == :site do %>
              <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
                Set up your main location
              </h1>
              <p class="mb-1 text-[15px] leading-6 text-[var(--thamani-pewter)]">
                This is where your team starts operating. If you only have one branch, enter
                it here — you can add more locations later.
              </p>
              <p class="mb-8 text-xs text-[var(--thamani-pewter)]">
                <span class="text-red-600">*</span> Required
              </p>

              <.form
                for={@site_form}
                id="site-setup-form"
                phx-change="validate_site"
                phx-submit="continue_site"
              >
                <.thamani_input
                  field={@site_form[:name]}
                  label="Site name"
                  placeholder="e.g. Afya CBD"
                  phx-debounce="blur"
                  required
                />

                <%= case site_activity_options(@organization_params) do %>
                  <% [{only_value, _only_label, _description}] -> %>
                    <input type="hidden" name="site[activities][]" value={only_value} />
                  <% options -> %>
                    <fieldset class="mb-6">
                      <legend class="text-sm font-medium text-[var(--thamani-forest)]">
                        Activities at this location<span class="text-red-600">&nbsp;*</span>
                      </legend>
                      <div class="mb-3 mt-1 flex items-center justify-between gap-3">
                        <p class="text-xs text-[var(--thamani-pewter)]">Select all that apply</p>
                        <%= if selected_site_activity_count(@site_form) > 0 do %>
                          <span
                            id="site-activity-selection-count"
                            class="rounded-full bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-2.5 py-1 text-[11px] font-semibold text-[var(--thamani-forest)]"
                          >
                            {selected_site_activity_count(@site_form)} selected
                          </span>
                        <% end %>
                      </div>
                      <input type="hidden" name="site[activities][]" value="" />
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                        <%= for {value, label, description} <- options do %>
                          <label class={[
                            "group cursor-pointer rounded-xl border-2 p-4 transition-all hover:-translate-y-0.5 hover:border-[var(--thamani-forest)] focus-within:ring-2 focus-within:ring-[var(--thamani-lime)] focus-within:ring-offset-2",
                            site_activity_selected?(@site_form, value) &&
                              "border-[var(--thamani-forest)] bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] shadow-md",
                            !site_activity_selected?(@site_form, value) &&
                              "border-[var(--thamani-stone)] bg-white"
                          ]}>
                            <input
                              type="checkbox"
                              name="site[activities][]"
                              value={value}
                              checked={site_activity_selected?(@site_form, value)}
                              class="peer sr-only"
                            />
                            <div class="flex items-start justify-end">
                              <span class={[
                                "flex size-5 shrink-0 items-center justify-center rounded-md border transition-colors",
                                site_activity_selected?(@site_form, value) &&
                                  "border-[var(--thamani-forest)] bg-[var(--thamani-forest)] text-white",
                                !site_activity_selected?(@site_form, value) &&
                                  "border-[var(--thamani-stone)] bg-white text-transparent group-hover:border-[var(--thamani-forest)]"
                              ]}>
                                <.icon name="hero-check" class="size-3.5" />
                              </span>
                            </div>
                            <span class="mt-3 block text-sm font-semibold text-[var(--thamani-forest)]">{label}</span>
                            <span class="mt-1 block text-[11px] leading-4 text-[var(--thamani-pewter)]">{description}</span>
                          </label>
                        <% end %>
                      </div>
                      <%= for error <- @site_form[:activities].errors do %>
                        <p class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
                      <% end %>
                    </fieldset>
                <% end %>

                <.thamani_input
                  field={@site_form[:address]}
                  label="Address"
                  placeholder="Street, town or county"
                  phx-debounce="blur"
                />

                <div class="mb-6">
                  <.thamani_input
                    field={@site_form[:gln]}
                    label="Site GLN"
                    placeholder="13-digit GS1 Global Location Number"
                    phx-debounce="blur"
                  />
                  <%= case @gln_check do %>
                    <% :checking -> %>
                      <p class="-mt-4 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--thamani-pewter)]">
                        <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                        Checking with the GS1 registry&hellip;
                      </p>
                    <% {:matched, name} when is_binary(name) -> %>
                      <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2 text-xs font-semibold text-[var(--thamani-forest)]">
                        <.icon name="hero-check-circle" class="size-4" /> Verified — matches {name}
                      </p>
                    <% {:matched, nil} -> %>
                      <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2 text-xs font-semibold text-[var(--thamani-forest)]">
                        <.icon name="hero-check-circle" class="size-4" /> Verified with GS1
                      </p>
                    <% :not_found -> %>
                      <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                        <.icon name="hero-exclamation-triangle" class="size-4" />
                        We couldn't find this GLN in the GS1 registry. Double-check the number before continuing.
                      </p>
                    <% :invalid_check_digit -> %>
                      <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                        <.icon name="hero-exclamation-triangle" class="size-4" />
                        That doesn't look like a valid GLN — double-check the digits.
                      </p>
                    <% _ -> %>
                      <p class="-mt-4 text-xs text-[var(--thamani-pewter)]">
                        GLN issued to you through GS1 Kenya. We verify it with the GS1 registry after setup.
                      </p>
                  <% end %>
                  <p class="mt-2 text-xs text-[var(--thamani-pewter)]">
                    This also becomes your organization's GLN, since it's your only location
                    right now. You can set a different organization GLN later from Settings.
                  </p>
                </div>

                <div class="flex items-center gap-3">
                  <button
                    id="site-back"
                    type="button"
                    phx-click="back"
                    phx-value-from="site"
                    class="inline-flex h-11 items-center justify-center rounded-full border border-[var(--thamani-stone)] bg-white px-5 text-sm font-medium text-[var(--thamani-forest)] transition hover:border-[var(--thamani-forest)]"
                  >
                    <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
                  </button>
                  <.thamani_btn
                    id="site-continue"
                    type="submit"
                    variant="primary"
                    disabled={gln_entered?(@site_form) and @gln_check == :checking}
                  >
                    <%= if gln_entered?(@site_form) and @gln_check == :checking do %>
                      <.icon name="hero-arrow-path" class="mr-2 size-4 animate-spin" />
                      Checking GS1 registry&hellip;
                    <% else %>
                      Continue <.icon name="hero-arrow-right" class="ml-2 size-4" />
                    <% end %>
                  </.thamani_btn>
                </div>
              </.form>
            <% else %>
              <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
                Create your administrator
              </h1>
              <p class="mb-8 text-[15px] leading-6 text-[var(--thamani-pewter)]">
                Add the administrator who will manage your sites, team, and organization settings. Nothing is created until you complete setup.
              </p>

              <.form
                for={@admin_form}
                phx-submit="save"
                phx-change="validate_administrator"
                phx-trigger-action={@trigger_login}
                action={~p"/login"}
                method="post"
                id="signup-form"
              >
                <input type="hidden" name="start_tour" value="true" />
                <div class="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
                  <div class="mb-5">
                    <div class="mb-2 flex items-baseline justify-between">
                      <label
                        for="user_first_name"
                        class="block text-[13px] font-medium text-thamani-pewter tracking-[0.01em]"
                      >
                        First name<span class="text-red-600">&nbsp;*</span>
                      </label>
                    </div>
                    <input
                      id="user_first_name"
                      type="text"
                      name="user[first_name]"
                      value={@admin_first_name}
                      placeholder="Jane"
                      autocomplete="given-name"
                      phx-debounce="blur"
                      required
                      class="w-full box-border px-4 py-3 text-[15px] text-base-content bg-thamani-snow border-[1.5px] rounded-lg outline-none transition-[border-color,box-shadow] duration-150 ease-in-out focus:border-thamani-accent focus:shadow-[0_0_0_3px_rgba(102,103,171,0.12)] border-thamani-stone"
                    />
                  </div>
                  <div class="mb-5">
                    <div class="mb-2 flex items-baseline justify-between">
                      <label
                        for="user_last_name"
                        class="block text-[13px] font-medium text-thamani-pewter tracking-[0.01em]"
                      >
                        Last name<span class="text-red-600">&nbsp;*</span>
                      </label>
                    </div>
                    <input
                      id="user_last_name"
                      type="text"
                      name="user[last_name]"
                      value={@admin_last_name}
                      placeholder="Mwangi"
                      autocomplete="family-name"
                      phx-debounce="blur"
                      required
                      class="w-full box-border px-4 py-3 text-[15px] text-base-content bg-thamani-snow border-[1.5px] rounded-lg outline-none transition-[border-color,box-shadow] duration-150 ease-in-out focus:border-thamani-accent focus:shadow-[0_0_0_3px_rgba(102,103,171,0.12)] border-thamani-stone"
                    />
                  </div>
                </div>
                <p
                  :for={error <- @admin_form[:name].errors}
                  class="-mt-3 mb-5 text-[13px] text-thamani-error"
                >
                  {translate_error(error)}
                </p>

                <.thamani_input
                  field={@admin_form[:email]}
                  type="email"
                  label="Email address"
                  placeholder="you@organization.com"
                  autocomplete="email"
                  phx-debounce="blur"
                  required
                />

                <.thamani_input
                  field={@admin_form[:password]}
                  type="password"
                  label="Password"
                  placeholder="••••••••"
                  autocomplete="new-password"
                  class="mb-8"
                  phx-debounce="blur"
                  required
                />

                <div class="mb-7">
                  <label class="flex cursor-pointer items-start gap-3">
                    <input
                      type="hidden"
                      name={@admin_form[:accepted_legal_terms].name}
                      value="false"
                    />
                    <input
                      id={@admin_form[:accepted_legal_terms].id}
                      type="checkbox"
                      name={@admin_form[:accepted_legal_terms].name}
                      value="true"
                      checked={@admin_form[:accepted_legal_terms].value in [true, "true"]}
                      required
                      class="mt-0.5 size-4 shrink-0 rounded border-[var(--thamani-stone)] bg-transparent text-[var(--thamani-forest)] accent-[var(--thamani-forest)] focus:ring-2 focus:ring-[var(--thamani-lime)]"
                    />
                    <span class="text-xs leading-5 text-[var(--thamani-pewter)]">
                      I agree to the
                      <a
                        href={~p"/terms"}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="font-semibold text-[var(--thamani-forest)] underline underline-offset-2"
                      >Terms of Service</a>
                      and acknowledge the <a
                        href={~p"/privacy"}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="font-semibold text-[var(--thamani-forest)] underline underline-offset-2"
                      >Privacy Policy</a>.
                    </span>
                  </label>
                  <%= for error <- @admin_form[:accepted_legal_terms].errors do %>
                    <p class="mt-1.5 pl-7 text-xs text-red-700">{translate_error(error)}</p>
                  <% end %>
                </div>

                <div class="flex items-center gap-3">
                  <button
                    id="onboarding-back"
                    type="button"
                    phx-click="back"
                    phx-value-from="administrator"
                    class="inline-flex h-11 items-center justify-center rounded-full border border-[var(--thamani-stone)] bg-white px-5 text-sm font-medium text-[var(--thamani-forest)] transition hover:border-[var(--thamani-forest)]"
                  >
                    <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
                  </button>
                  <.thamani_btn id="signup-submit" type="submit" variant="primary">
                    Complete setup
                  </.thamani_btn>
                </div>
              </.form>
            <% end %>
          <% end %>

          <p style="text-align: center; font-size: 14px; color: var(--thamani-pewter); margin-top: 28px;">
            Already have an account?
            <.link
              navigate={~p"/login"}
              style="color: var(--thamani-forest); text-decoration: underline; text-underline-offset: 3px; font-weight: 500;"
            >
              Log in here
            </.link>
          </p>
        </div>

        <div
          class="lg:hidden"
          style="margin-top: 48px; display: flex; gap: 20px; align-items: center;"
        >
          <.link
            navigate={~p"/privacy"}
            style="font-size: 12px; color: var(--thamani-subtle); text-decoration: none;"
          >Privacy</.link>
          <span style="font-size: 12px; color: var(--thamani-stone);">·</span>
          <.link
            navigate={~p"/terms"}
            style="font-size: 12px; color: var(--thamani-subtle); text-decoration: none;"
          >Terms</.link>
        </div>
      </div>
    </div>
    """
  end
end
