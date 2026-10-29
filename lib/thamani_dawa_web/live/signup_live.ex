defmodule ThamaniDawaWeb.SignupLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.User
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
      |> assign(
        :site_form,
        to_form(
          Site.default_changeset(%Site{}, %{site_type: :pharmacy}),
          as: :site
        )
      )
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
      |> assign(:trigger_login, false)

    {:ok, socket}
  end

  def handle_event("validate_organization", params, socket) do
    org_params = params |> Map.get("organization", %{}) |> normalize_operating_models()

    site_params =
      params
      |> Map.get("site", %{})
      |> maybe_suggest_site_type(params, org_params)

    org_changeset =
      %Organization{}
      |> Organization.changeset(org_params)
      |> Map.put(:action, :validate)

    site_changeset =
      %Site{}
      |> Site.default_changeset(site_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:org_form, to_form(org_changeset, as: :organization))
     |> assign(:site_form, to_form(site_changeset, as: :site))}
  end

  def handle_event("continue", %{"organization" => org_params, "site" => site_params}, socket) do
    org_params = normalize_operating_models(org_params)
    org_changeset = Organization.changeset(%Organization{}, org_params)
    site_changeset = Site.default_changeset(%Site{}, site_params)

    if org_changeset.valid? and site_changeset.valid? do
      {:noreply,
       socket
       |> assign(:step, :administrator)
       |> assign(:organization_params, org_params)
       |> assign(:site_params, site_params)
       |> assign(:org_form, to_form(org_changeset, as: :organization))
       |> assign(:site_form, to_form(site_changeset, as: :site))}
    else
      {:noreply,
       socket
       |> assign(:org_form, to_form(%{org_changeset | action: :validate}, as: :organization))
       |> assign(:site_form, to_form(%{site_changeset | action: :validate}, as: :site))}
    end
  end

  def handle_event("validate_administrator", %{"user" => admin_params}, socket) do
    changeset =
      %User{}
      |> User.registration_changeset(admin_params,
        hash_password: false,
        require_legal_consent: true
      )
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :admin_form, to_form(changeset, as: :user))}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, :step, :organization)}
  end

  def handle_event("save", %{"user" => admin_params}, socket) do
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
         |> assign(:step, :organization)
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

  defp normalize_operating_models(params) do
    Map.update(params, "operating_models", [], fn models ->
      Enum.reject(models, &(&1 in [nil, ""]))
    end)
  end

  defp maybe_suggest_site_type(site_params, params, org_params) do
    if Map.get(params, "_target") == ["organization", "operating_models"] do
      Map.put(site_params, "site_type", suggested_site_type(org_params["operating_models"]))
    else
      site_params
    end
  end

  defp suggested_site_type(models) do
    cond do
      "distributor" in models -> "warehouse"
      "pharmacy" in models and "laboratory" in models -> "pharmacy_lab"
      "laboratory" in models -> "lab"
      true -> "pharmacy"
    end
  end

  defp operating_model_options do
    [
      {"pharmacy", "Pharmacy", "Dispense medicines and manage retail stock",
       "hero-building-storefront"},
      {"laboratory", "Laboratory", "Manage diagnostic tests and specimens", "hero-beaker"},
      {"distributor", "Distributor", "Warehouse and distribute medical products", "hero-truck"}
    ]
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

  defp site_type_options do
    [
      {"Pharmacy", :pharmacy},
      {"Laboratory", :lab},
      {"Combined pharmacy & laboratory", :pharmacy_lab},
      {"Warehouse", :warehouse}
    ]
  end

  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; display: flex; flex-direction: row;">
      <div
        class="hidden lg:flex"
        style="width: 38%; background: var(--thamani-forest); flex-direction: column; justify-content: space-between; padding: 48px 52px; position: relative; overflow: hidden;"
      >
        <div
          aria-hidden="true"
          style="position: absolute; top: -120px; right: -120px; width: 420px; height: 420px; border-radius: 50%; background: var(--thamani-lime); opacity: 0.08; pointer-events: none;"
        >
        </div>
        <div
          aria-hidden="true"
          style="position: absolute; bottom: -80px; left: -80px; width: 280px; height: 280px; border-radius: 50%; background: var(--thamani-lime); opacity: 0.06; pointer-events: none;"
        >
        </div>

        <.link
          navigate={~p"/"}
          style="font-size: 17px; font-weight: 500; color: var(--thamani-snow); text-decoration: none; letter-spacing: -0.01em; position: relative;"
        >
          Thamani Dawa
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

      <div style="flex: 1; min-width: 0; background: var(--thamani-snow); display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 48px 40px;">
        <div style="width: 100%; max-width: 560px;">
          <ThamaniDawaWeb.Layouts.flash_group flash={@flash} />

          <div
            id="onboarding-progress"
            class="mb-7 flex items-center gap-3"
            aria-label="Onboarding progress"
          >
            <div class="flex items-center gap-2">
              <span class={[
                "flex size-7 items-center justify-center rounded-full text-xs font-semibold",
                "bg-[var(--thamani-forest)] text-white"
              ]}>1</span>
              <span class="text-xs font-medium text-[var(--thamani-forest)]">Organization</span>
            </div>
            <div class="h-px flex-1 bg-[var(--thamani-stone)]" />
            <div class="flex items-center gap-2">
              <span class={[
                "flex size-7 items-center justify-center rounded-full text-xs font-semibold transition-colors",
                if(@step == :administrator,
                  do: "bg-[var(--thamani-forest)] text-white",
                  else: "bg-white text-[var(--thamani-pewter)] ring-1 ring-[var(--thamani-stone)]"
                )
              ]}>2</span>
              <span class={[
                "text-xs font-medium",
                if(@step == :administrator,
                  do: "text-[var(--thamani-forest)]",
                  else: "text-[var(--thamani-pewter)]"
                )
              ]}>Administrator</span>
            </div>
          </div>

          <%= if @step == :organization do %>
            <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
              Tell us about your organization
            </h1>
            <p class="mb-8 text-[15px] leading-6 text-[var(--thamani-pewter)]">
              Select all the services you operate. You can choose more than one.
            </p>

            <.form
              for={@org_form}
              id="organization-setup-form"
              phx-change="validate_organization"
              phx-submit="continue"
            >
              <div class="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
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
                  What does your organization operate?
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
                <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
                  <%= for {value, label, description, icon} <- operating_model_options() do %>
                    <label class={[
                      "group relative cursor-pointer rounded-xl border-2 p-3 transition-all hover:-translate-y-0.5 hover:border-[var(--thamani-forest)] focus-within:ring-2 focus-within:ring-[var(--thamani-lime)] focus-within:ring-offset-2",
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
                      <span class={[
                        "absolute right-2.5 top-2.5 flex size-5 items-center justify-center rounded-md border transition-colors",
                        operating_model_selected?(@org_form, value) &&
                          "border-[var(--thamani-forest)] bg-[var(--thamani-forest)] text-white",
                        !operating_model_selected?(@org_form, value) &&
                          "border-[var(--thamani-stone)] bg-white text-transparent group-hover:border-[var(--thamani-forest)]"
                      ]}>
                        <.icon name="hero-check" class="size-3.5" />
                      </span>
                      <.icon name={icon} class="mb-2 size-5 text-[var(--thamani-forest)]" />
                      <span class="block text-sm font-semibold text-[var(--thamani-forest)]">{label}</span>
                      <span class="mt-1 block text-[11px] leading-4 text-[var(--thamani-pewter)]">{description}</span>
                    </label>
                  <% end %>
                </div>
                <%= for error <- @org_form[:operating_models].errors do %>
                  <p class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
                <% end %>
              </fieldset>

              <div class="my-6 border-t border-[var(--thamani-stone)] pt-5">
                <div class="mb-4">
                  <p class="text-sm font-semibold text-[var(--thamani-forest)]">Initial site</p>
                  <p class="mt-1 text-xs text-[var(--thamani-pewter)]">
                    This is the first location you'll set up. You can add more sites later.
                  </p>
                </div>
                <div class="grid grid-cols-1 gap-x-4 sm:grid-cols-2">
                  <.thamani_input
                    field={@site_form[:name]}
                    label="Site name"
                    placeholder="e.g. Main Branch"
                    phx-debounce="blur"
                    required
                  />
                  <.input
                    field={@site_form[:site_type]}
                    type="select"
                    label="Site type"
                    options={site_type_options()}
                    class="mt-2 block w-full rounded-lg border border-[var(--thamani-stone)] bg-white px-3 py-2.5 text-sm text-[var(--thamani-forest)] focus:border-[var(--thamani-forest)] focus:outline-none focus:ring-2 focus:ring-[color-mix(in_srgb,var(--thamani-lime)_30%,transparent)]"
                    required
                  />
                </div>
                <.thamani_input
                  field={@site_form[:address]}
                  label="Address (optional)"
                  placeholder="Street, town or county"
                  phx-debounce="blur"
                />
              </div>

              <.thamani_btn id="onboarding-continue" type="submit" variant="primary">
                Continue <.icon name="hero-arrow-right" class="ml-2 size-4" />
              </.thamani_btn>
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
                <.thamani_input
                  field={@admin_form[:name]}
                  label="Your name"
                  placeholder="Jane Mwangi"
                  autocomplete="name"
                  phx-debounce="blur"
                  required
                />
                <.thamani_input
                  field={@admin_form[:email]}
                  type="email"
                  label="Email address"
                  placeholder="you@organization.com"
                  autocomplete="email"
                  phx-debounce="blur"
                  required
                />
              </div>

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
