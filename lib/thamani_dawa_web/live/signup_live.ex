defmodule ThamaniDawaWeb.SignupLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Grp
  alias ThamaniDawa.Grp.Licence
  alias ThamaniDawa.Kmlttb
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Ppb
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @steps [:operating_model, :regulatory_details, :main_location, :administrator]
  @operating_models ~w(pharmacy laboratory distributor)
  @step_labels %{
    operating_model: "Organization",
    regulatory_details: "Organization identity",
    main_location: "Main location",
    administrator: "Administrator"
  }

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
      |> assign(:step, :operating_model)
      |> assign(:organization_params, nil)
      |> assign(:site_params, nil)
      |> assign(:prefix_check, :idle)
      |> assign(:gln_check, :idle)
      |> assign(:ppb_check, :idle)
      |> assign(:kmlttb_check, :idle)
      |> assign(:admin_first_name, "")
      |> assign(:admin_last_name, "")
      |> assign(:trigger_login, false)

    {:ok, socket}
  end

  def handle_event("validate_operating_model", params, socket) do
    org_params = params |> Map.get("organization", %{}) |> normalize_operating_models()

    org_changeset =
      socket
      |> organization_base()
      |> Organization.changeset(org_params)
      |> Map.put(:action, :validate)

    site_form =
      if Map.get(params, "_target") == ["organization", "operating_models"] do
        site_changeset =
          socket
          |> site_base()
          |> Site.default_changeset(%{"activities" => suggested_site_activities(org_params)})
          |> Map.put(:action, :validate)

        to_form(site_changeset, as: :site)
      else
        socket.assigns.site_form
      end

    {:noreply,
     socket
     |> assign(:org_form, to_form(org_changeset, as: :organization))
     |> assign(:site_form, site_form)}
  end

  def handle_event("restore_signup_draft", draft, socket) do
    organization_params = restore_organization_params(Map.get(draft, "organization", %{}))

    site_params =
      draft
      |> Map.get("site", %{})
      |> restore_site_params()
      |> apply_activity_choice(organization_params)

    step = restorable_step(Map.get(draft, "step"), organization_params, site_params)

    org_changeset = Organization.signup_changeset(%Organization{}, organization_params)
    site_changeset = Site.default_changeset(%Site{}, site_params)

    socket =
      socket
      |> assign(:step, step)
      |> assign(:organization_params, organization_params)
      |> assign(:site_params, if(step == :administrator, do: site_params, else: nil))
      |> assign(:org_form, to_form(org_changeset, as: :organization))
      |> assign(:site_form, to_form(site_changeset, as: :site))
      |> reverify_restored_prefix(organization_params, step)
      |> reverify_restored_gln(site_params, step)
      |> reverify_restored_ppb(site_params, step)
      |> reverify_restored_kmlttb(site_params, step)

    {:reply, %{restored: true}, socket}
  end

  def handle_event("continue_operating_model", %{"organization" => org_params}, socket) do
    org_params = normalize_operating_models(org_params)

    org_changeset =
      socket
      |> organization_base()
      |> Organization.changeset(org_params)
      |> Map.put(:action, :validate)

    if Enum.empty?(Map.get(org_params, "operating_models", [])) do
      {:noreply, assign(socket, :org_form, to_form(org_changeset, as: :organization))}
    else
      site_changeset =
        socket
        |> site_base()
        |> Site.default_changeset(%{
          "activities" => preserved_or_suggested_site_activities(socket, org_params)
        })
        |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> assign(:step, :regulatory_details)
       |> assign(:organization_params, org_params)
       |> assign(:org_form, to_form(org_changeset, as: :organization))
       |> assign(:site_form, to_form(site_changeset, as: :site))}
    end
  end

  def handle_event("validate_regulatory_details", params, socket) do
    org_params = Map.get(params, "organization", %{})

    org_changeset =
      %Organization{}
      |> Organization.signup_changeset(org_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:org_form, to_form(org_changeset, as: :organization))
     |> maybe_check_gs1_prefix(params, org_params)}
  end

  def handle_event("continue_regulatory_details", %{"organization" => org_params}, socket) do
    org_changeset = Organization.signup_changeset(%Organization{}, org_params)

    cond do
      blocking_regulatory_errors?(org_changeset) ->
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
           "Still checking the GS1 registry. Press Continue again in a moment."
         )}

      socket.assigns.prefix_check == :idle ->
        {:noreply,
         socket
         |> maybe_check_gs1_prefix(
           %{"_target" => ["organization", "gs1_company_prefix"]},
           org_params
         )
         |> put_flash(
           :error,
           "Checking your GS1 company prefix with the GS1 registry. Press Continue again in a moment."
         )}

      match?({:inactive, _}, socket.assigns.prefix_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This GS1 company prefix was found in the registry but isn't currently active. Please check its status with GS1 Kenya before continuing."
         )}

      match?({:name_taken, _}, socket.assigns.prefix_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "An organization with this registered name already exists. If this is your organization, log in instead — otherwise this GS1 prefix may be registered to a different company."
         )}

      not gs1_name_verified?(socket.assigns.prefix_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "We couldn't find this GS1 company prefix in the registry. Please double-check the number before continuing."
         )}

      not org_changeset.valid? ->
        {:noreply,
         assign(
           socket,
           :org_form,
           to_form(%{org_changeset | action: :validate}, as: :organization)
         )}

      true ->
        site_changeset =
          socket
          |> site_base()
          |> Site.default_changeset(%{
            "activities" => preserved_or_suggested_site_activities(socket, org_params)
          })
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:step, :main_location)
         |> assign(:organization_params, org_params)
         |> assign(:org_form, to_form(org_changeset, as: :organization))
         |> assign(:site_form, to_form(site_changeset, as: :site))}
    end
  end

  def handle_event("validate_site", params, socket) do
    site_params =
      params
      |> Map.get("site", %{})
      |> apply_activity_choice(socket.assigns.organization_params)

    site_changeset =
      %Site{}
      |> Site.default_changeset(site_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:site_form, to_form(site_changeset, as: :site))
     |> maybe_autofill_ppb_facility_name()
     |> maybe_autofill_kmlttb_facility_name()
     |> maybe_check_gln(params, site_params)
     |> maybe_check_ppb(params, site_params)
     |> maybe_check_kmlttb(params, site_params)}
  end

  def handle_event("continue_site", %{"site" => site_params} = params, socket) do
    site_params = apply_activity_choice(site_params, socket.assigns.organization_params)

    site_changeset = Site.default_changeset(%Site{}, site_params)
    ppb_ftype = Site.ppb_ftype(Map.get(site_params, "activities", []))
    kmlttb_required = Site.kmlttb_required?(Map.get(site_params, "activities", []))

    cond do
      not gln_present?(site_params) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A GLN is required for your main location. Enter one above, or get one from GS1 Kenya first."
         )}

      socket.assigns.gln_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still checking the site GLN with the GS1 registry. Press Continue again in a moment."
         )}

      socket.assigns.gln_check == :idle ->
        {:noreply,
         socket
         |> maybe_check_gln(Map.put(params, "_target", ["site", "gln"]), site_params)
         |> put_flash(
           :error,
           "Checking the site GLN with the GS1 registry. Press Continue again in a moment."
         )}

      match?({:inactive, _, _}, socket.assigns.gln_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This GLN was found in the registry but isn't currently active. Please check its status with GS1 Kenya before continuing."
         )}

      match?({:taken, _, _}, socket.assigns.gln_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This GLN is already registered to another location on Thamani Dawa. Double-check the number, or use a different GLN for this location."
         )}

      not match?({:matched, _, _}, socket.assigns.gln_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "We couldn't find this GLN in the GS1 registry. Get one from GS1 Kenya, then try again."
         )}

      ppb_ftype && socket.assigns.ppb_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still checking this location's PPB license. Press Continue again in a moment."
         )}

      ppb_ftype && socket.assigns.ppb_check == :idle ->
        {:noreply,
         socket
         |> maybe_check_ppb(
           Map.put(params, "_target", ["site", "license_number"]),
           site_params
         )
         |> put_flash(
           :error,
           "Checking this location's PPB license. Press Continue again in a moment."
         )}

      ppb_ftype && not match?({:matched, _}, socket.assigns.ppb_check) ->
        {:noreply, put_flash(socket, :error, ppb_error_message(socket.assigns.ppb_check))}

      kmlttb_required && socket.assigns.kmlttb_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still checking this location's KMLTTB license. Press Continue again in a moment."
         )}

      kmlttb_required && socket.assigns.kmlttb_check == :idle ->
        {:noreply,
         socket
         |> maybe_check_kmlttb(
           Map.put(params, "_target", ["site", "kmlttb_license_number"]),
           site_params
         )
         |> put_flash(
           :error,
           "Checking this location's KMLTTB license. Press Continue again in a moment."
         )}

      kmlttb_required && not match?({:matched, _}, socket.assigns.kmlttb_check) ->
        {:noreply, put_flash(socket, :error, kmlttb_error_message(socket.assigns.kmlttb_check))}

      not site_changeset.valid? ->
        {:noreply,
         assign(socket, :site_form, to_form(%{site_changeset | action: :validate}, as: :site))}

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

  def handle_event("back", %{"from" => from}, socket) do
    index = Enum.find_index(@steps, &(Atom.to_string(&1) == from))
    previous = if index && index > 0, do: Enum.at(@steps, index - 1), else: hd(@steps)
    {:noreply, assign(socket, :step, previous)}
  end

  def handle_event("select_ppb_candidate", %{"index" => index}, socket) do
    case socket.assigns.ppb_check do
      {:ambiguous, candidates} ->
        case Enum.at(candidates, String.to_integer(index)) do
          nil -> {:noreply, socket}
          detail -> {:noreply, assign(socket, :ppb_check, {:matched, detail})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_kmlttb_candidate", %{"index" => index}, socket) do
    case socket.assigns.kmlttb_check do
      {:ambiguous, candidates} ->
        case Enum.at(candidates, String.to_integer(index)) do
          nil -> {:noreply, socket}
          detail -> {:noreply, assign(socket, :kmlttb_check, {:matched, detail})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"user" => admin_params}, socket) do
    admin_params = compose_admin_name(admin_params)
    site_activities = Map.get(socket.assigns.site_params || %{}, "activities", [])
    site_ppb_ftype = Site.ppb_ftype(site_activities)
    site_kmlttb_required = Site.kmlttb_required?(site_activities)

    cond do
      socket.assigns.prefix_check == :checking or socket.assigns.gln_check == :checking ->
        {:noreply,
         put_flash(socket, :error, "We’re rechecking your GS1 details. Try again in a moment.")}

      not gs1_name_verified?(socket.assigns.prefix_check) ->
        {:noreply,
         socket
         |> assign(:step, :regulatory_details)
         |> put_flash(:error, "Please verify your GS1 company prefix again before continuing.")}

      not match?({:matched, _, _}, socket.assigns.gln_check) ->
        {:noreply,
         socket
         |> assign(:step, :main_location)
         |> put_flash(:error, "Please verify your location GLN again before continuing.")}

      site_ppb_ftype && not match?({:matched, _}, socket.assigns.ppb_check) ->
        {:noreply,
         socket
         |> assign(:step, :main_location)
         |> put_flash(
           :error,
           "Please verify this location's PPB license again before continuing."
         )}

      site_kmlttb_required && not match?({:matched, _}, socket.assigns.kmlttb_check) ->
        {:noreply,
         socket
         |> assign(:step, :main_location)
         |> put_flash(
           :error,
           "Please verify this location's KMLTTB license again before continuing."
         )}

      true ->
        complete_signup(socket, admin_params)
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp complete_signup(socket, admin_params) do
    case Organizations.signup(
           socket.assigns.organization_params,
           socket.assigns.site_params,
           admin_params
         ) do
      {:ok, result} ->
        Accounts.deliver_user_confirmation_instructions(result.user, fn token ->
          url(~p"/confirm/#{token}")
        end)

        {:noreply,
         socket
         |> push_event("clear_signup_draft", %{})
         |> assign(:trigger_login, true)}

      {:error, %Ecto.Changeset{data: %Organization{}} = changeset} ->
        {:noreply,
         socket
         |> assign(:step, :regulatory_details)
         |> assign(:org_form, to_form(changeset, as: :organization))
         |> put_flash(:error, changeset_error_flash(changeset, "organization"))}

      {:error, %Ecto.Changeset{data: %Site{}} = changeset} ->
        {:noreply,
         socket
         |> assign(:step, :main_location)
         |> assign(:site_form, to_form(changeset, as: :site))
         |> put_flash(:error, changeset_error_flash(changeset, "location"))}

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

  # Surfaces *why* the final submit bounced the user back a step — without
  # this, a DB-level failure caught only at insert time (e.g. the
  # organization name/slug or site GLN already being taken by an earlier
  # attempt) silently sent them back with no explanation and no way to
  # tell what to fix, since some of the offending fields (e.g. the
  # organization name) aren't even visible as inputs on the step they land
  # back on.
  defp changeset_error_flash(changeset, subject) do
    errors =
      changeset
      |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(messages, &format_field_error(field, &1))
      end)

    case errors do
      [] ->
        "We couldn't save your #{subject} details. Please review and try again."

      messages ->
        "We couldn't save your #{subject} details: #{Enum.join(messages, "; ")}."
    end
  end

  # Ecto's own generated messages ("can't be blank", "has already been
  # taken") are short lowercase fragments that need the field name for
  # context; this app's custom messages ("An organization with this name
  # already exists") are already full sentences and read oddly with a
  # field name glued on front.
  defp format_field_error(field, message) do
    if message =~ ~r/^[A-Z]/ do
      message
    else
      "#{humanize_field(field)} #{message}"
    end
  end

  defp humanize_field(field),
    do: field |> to_string() |> String.replace("_", " ")

  def handle_async(:gs1_prefix_lookup, {:ok, {:ok, :verified, licence}}, socket) do
    name = licensee_name(licence)

    if is_binary(name) and name != "" and Organizations.organization_name_taken?(name) do
      {:noreply, socket |> clear_flash(:error) |> assign(:prefix_check, {:name_taken, name})}
    else
      {:noreply,
       socket
       |> clear_flash(:error)
       |> assign(:prefix_check, {:matched, name})
       |> maybe_autofill_org_name(name)
       |> maybe_autofill_organization_params_name(name)}
    end
  end

  def handle_async(:gs1_prefix_lookup, {:ok, {:ok, :inactive, licence}}, socket) do
    {:noreply,
     socket |> clear_flash(:error) |> assign(:prefix_check, {:inactive, licensee_name(licence)})}
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
    name = licensee_name(licence)
    address = licensee_address(licence)
    gln = Map.get(licence, "gln")

    if is_binary(gln) and gln != "" and Sites.gln_taken?(gln) do
      {:noreply, socket |> clear_flash(:error) |> assign(:gln_check, {:taken, name, address})}
    else
      {:noreply,
       socket
       |> clear_flash(:error)
       |> assign(:gln_check, {:matched, name, address})
       |> maybe_autofill_site_fields(licence)}
    end
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :inactive, licence}}, socket) do
    {:noreply,
     socket
     |> clear_flash(:error)
     |> assign(:gln_check, {:inactive, licensee_name(licence), licensee_address(licence)})}
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

  def handle_async(:ppb_lookup, {:ok, {:ok, :verified, detail}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, {:matched, detail})}
  end

  def handle_async(:ppb_lookup, {:ok, {:ok, :license_inactive, detail}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, {:license_inactive, detail})}
  end

  def handle_async(:ppb_lookup, {:ok, {:ok, :ambiguous, candidates}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, {:ambiguous, candidates})}
  end

  def handle_async(:ppb_lookup, {:ok, {:error, :name_not_found}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, :name_not_found)}
  end

  def handle_async(:ppb_lookup, {:ok, {:error, :license_mismatch}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, :license_mismatch)}
  end

  def handle_async(:ppb_lookup, {:ok, {:error, _reason}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, :unavailable)}
  end

  def handle_async(:ppb_lookup, {:exit, _reason}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:ppb_check, :unavailable)}
  end

  def handle_async(:kmlttb_lookup, {:ok, {:ok, :verified, detail}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:kmlttb_check, {:matched, detail})}
  end

  def handle_async(:kmlttb_lookup, {:ok, {:ok, :license_inactive, detail}}, socket) do
    {:noreply,
     socket |> clear_flash(:error) |> assign(:kmlttb_check, {:license_inactive, detail})}
  end

  def handle_async(:kmlttb_lookup, {:ok, {:ok, :ambiguous, candidates}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:kmlttb_check, {:ambiguous, candidates})}
  end

  def handle_async(:kmlttb_lookup, {:ok, {:error, :name_not_found}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:kmlttb_check, :name_not_found)}
  end

  def handle_async(:kmlttb_lookup, {:ok, {:error, :license_mismatch}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:kmlttb_check, :license_mismatch)}
  end

  def handle_async(:kmlttb_lookup, {:ok, {:error, _reason}}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:kmlttb_check, :unavailable)}
  end

  def handle_async(:kmlttb_lookup, {:exit, _reason}, socket) do
    {:noreply, socket |> clear_flash(:error) |> assign(:kmlttb_check, :unavailable)}
  end

  # The organization name is supplied by the asynchronous GS1 lookup, so it
  # cannot block the initial submit that starts that lookup.
  defp blocking_regulatory_errors?(changeset) do
    changeset.errors
    |> Keyword.keys()
    |> Enum.any?(&(&1 != :name))
  end

  # Step 1's form only submits operating_models, so rebasing on a bare
  # %Organization{} here would silently drop fields (e.g. gs1_company_prefix)
  # already entered on a later step before the user went "back".
  defp organization_base(socket) do
    Ecto.Changeset.apply_changes(socket.assigns.org_form.source)
  end

  # Steps 1 and 2's "continue" handlers rebuild the suggested site
  # activities from the org's operating models each time they're submitted
  # — including a second time, if the user goes back and continues again
  # without changing anything. Rebasing on a bare %Site{} would silently
  # wipe out the GLN, PPB fields, or any manually-adjusted activities
  # already entered on step 3.
  defp site_base(socket) do
    Ecto.Changeset.apply_changes(socket.assigns.site_form.source)
  end

  defp normalize_operating_models(params) do
    Map.update(params, "operating_models", [], fn models ->
      Enum.reject(models, &(&1 in [nil, ""]))
    end)
  end

  defp restore_organization_params(params) when is_map(params) do
    %{
      "operating_models" =>
        params
        |> Map.get("operating_models", [])
        |> List.wrap()
        |> Enum.filter(&(&1 in @operating_models)),
      "gs1_company_prefix" => restored_string(params, "gs1_company_prefix", 10),
      # Registry-owned names are deliberately re-derived after restoration.
      "name" => ""
    }
  end

  defp restore_organization_params(_params), do: restore_organization_params(%{})

  @site_activity_choices ~w(pharmacy laboratory pharmacy_laboratory distribution)

  defp restore_site_params(params) when is_map(params) do
    %{
      "activity_choice" => restored_activity_choice(params),
      "gln" => restored_string(params, "gln", 13),
      # Registry-owned location details are deliberately re-derived too.
      "name" => "",
      "address" => "",
      # These are typed, not registry-derived, so unlike name/address above
      # they're worth restoring — losing them on a refresh meant redoing
      # PPB/KMLTTB verification from scratch for no reason.
      "ppb_facility_name" => restored_string(params, "ppb_facility_name", 200),
      "license_number" => restored_string(params, "license_number", 50),
      "kmlttb_facility_name" => restored_string(params, "kmlttb_facility_name", 200),
      "kmlttb_license_number" => restored_string(params, "kmlttb_license_number", 50)
    }
  end

  defp restore_site_params(_params), do: restore_site_params(%{})

  defp restored_activity_choice(params) do
    case Map.get(params, "activity_choice") do
      choice when choice in @site_activity_choices -> choice
      _choice -> nil
    end
  end

  defp restored_string(params, key, max_length) do
    params
    |> Map.get(key, "")
    |> to_string()
    |> String.trim()
    |> String.slice(0, max_length)
  end

  defp restorable_step(step, organization_params, site_params) do
    models_present? = Map.get(organization_params, "operating_models", []) != []

    identity_present? =
      models_present? and Map.get(organization_params, "gs1_company_prefix") != ""

    site_present? = identity_present? and Map.get(site_params, "gln") != ""

    case step do
      "administrator" when site_present? -> :administrator
      "main_location" when identity_present? -> :main_location
      "regulatory_details" when models_present? -> :regulatory_details
      _ -> :operating_model
    end
  end

  defp reverify_restored_prefix(socket, organization_params, step)
       when step in [:main_location, :administrator] do
    check_gs1_prefix(socket, organization_params)
  end

  defp reverify_restored_prefix(socket, _organization_params, _step), do: socket

  defp reverify_restored_gln(socket, site_params, step)
       when step in [:main_location, :administrator] do
    check_gln(socket, site_params)
  end

  defp reverify_restored_gln(socket, _site_params, _step), do: socket

  defp reverify_restored_ppb(socket, site_params, step)
       when step in [:main_location, :administrator] do
    check_ppb(socket, site_params)
  end

  defp reverify_restored_ppb(socket, _site_params, _step), do: socket

  defp reverify_restored_kmlttb(socket, site_params, step)
       when step in [:main_location, :administrator] do
    check_kmlttb(socket, site_params)
  end

  defp reverify_restored_kmlttb(socket, _site_params, _step), do: socket

  defp compose_admin_name(admin_params) do
    first = admin_params |> Map.get("first_name", "") |> to_string() |> String.trim()
    last = admin_params |> Map.get("last_name", "") |> to_string() |> String.trim()
    name = [first, last] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")

    Map.put(admin_params, "name", name)
  end

  # The site-activity picker offers exactly four real-world premises types
  # (see `site_activity_choices/1`) instead of free-form checkboxes, so a
  # single radio value unambiguously determines the underlying `:activities`
  # list — no client-side conflict resolution needed. When only one choice
  # is valid for the org's operating models, the template renders no radio
  # at all (just a fixed summary), so `activity_choice` won't be present;
  # fall back to that one forced choice in that case.
  defp apply_activity_choice(site_params, org_params) do
    activities =
      case site_activity_choices(org_params) do
        [only] -> only.activities
        _choices -> activities_for_choice(Map.get(site_params, "activity_choice"))
      end

    Map.put(site_params, "activities", activities)
  end

  defp activities_for_choice("pharmacy"), do: ["pharmacy"]
  defp activities_for_choice("laboratory"), do: ["laboratory"]
  defp activities_for_choice("pharmacy_laboratory"), do: ["pharmacy", "laboratory"]
  defp activities_for_choice("distribution"), do: ["distribution"]
  defp activities_for_choice(_choice), do: []

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

  defp licensee_name(licence), do: Licence.name(licence)
  defp licensee_address(licence), do: Licence.address(licence)

  defp maybe_autofill_org_name(socket, name) do
    autofill_field(socket, :org_form, :organization, :name, name)
  end

  # `organization_params` (the payload that actually reaches
  # `Organizations.signup/3`) is only captured once, at
  # `continue_regulatory_details` time — or set with a deliberately blank
  # name on draft restore (see `restore_organization_params/1`). Unlike
  # `@org_form`, nothing re-syncs it once this async lookup resolves, so a
  # restored session that lands past this step (main_location or
  # administrator) carried a blank name all the way to the final submit,
  # failing with "Please enter your organization name" despite the UI
  # showing a resolved, verified prefix the whole time.
  defp maybe_autofill_organization_params_name(socket, name)
       when is_binary(name) and name != "" do
    case socket.assigns.organization_params do
      %{} = params ->
        if blank?(Map.get(params, "name")) do
          assign(socket, :organization_params, Map.put(params, "name", name))
        else
          socket
        end

      _params ->
        socket
    end
  end

  defp maybe_autofill_organization_params_name(socket, _name), do: socket

  defp gs1_name_verified?({:matched, name}) when is_binary(name), do: String.trim(name) != ""
  defp gs1_name_verified?(_prefix_check), do: false

  defp maybe_autofill_site_fields(socket, licence) do
    socket
    |> autofill_field(:site_form, :site, :name, licensee_name(licence))
    |> autofill_field(:site_form, :site, :address, licensee_address(licence))
  end

  defp autofill_field(socket, assign_key, form_as, field, value)
       when is_binary(value) and value != "" do
    changeset = Map.fetch!(socket.assigns, assign_key).source

    if blank?(Ecto.Changeset.get_field(changeset, field)) do
      assign(
        socket,
        assign_key,
        changeset |> Ecto.Changeset.put_change(field, value) |> to_form(as: form_as)
      )
    else
      socket
    end
  end

  defp autofill_field(socket, _assign_key, _form_as, _field, _value), do: socket

  defp gs1_gln_registration_url, do: "https://gs1kenya.org/"

  defp blank?(nil), do: true
  defp blank?(value), do: value |> to_string() |> String.trim() == ""

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

  defp maybe_check_ppb(socket, params, site_params) do
    if Map.get(params, "_target") in [["site", "ppb_facility_name"], ["site", "license_number"]] do
      check_ppb(socket, site_params)
    else
      socket
    end
  end

  defp check_ppb(socket, site_params) do
    ftype = Site.ppb_ftype(Map.get(site_params, "activities", []))

    facility_name =
      site_params |> Map.get("ppb_facility_name", "") |> to_string() |> String.trim()

    license_number = site_params |> Map.get("license_number", "") |> to_string() |> String.trim()

    if ftype && likely_complete_name?(facility_name) && ppb_license_complete?(license_number) do
      socket
      |> assign(:ppb_check, :checking)
      |> start_async(:ppb_lookup, fn ->
        Ppb.verify_license(facility_name, license_number, ftype)
      end)
    else
      assign(socket, :ppb_check, :idle)
    end
  end

  # Every PPB masked license we've observed (any ftype) is 11 characters —
  # a 3-character prefix, 4 masked characters, and a 4-character suffix —
  # and `Ppb.license_match?/2` only ever matches when the entered value's
  # length equals the mask's, so a value that isn't 11 characters can never
  # verify. Gate on that length instead of firing on every keystroke.
  defp ppb_license_complete?(value), do: String.length(value) == 11

  defp ppb_error_message({:ambiguous, _candidates}),
    do:
      "Multiple facilities matched that name and license. Pick the correct one below before continuing."

  defp ppb_error_message(:name_not_found),
    do:
      "We couldn't find a facility by that name with PPB. Double-check the spelling, or confirm this location's activities (retail vs. wholesale) match how it's actually licensed."

  defp ppb_error_message(:license_mismatch),
    do:
      "We found that facility with PPB, but this license number doesn't match their record for it. Double-check the number."

  defp ppb_error_message({:license_inactive, _detail}),
    do:
      "This facility's PPB license was found but isn't currently active. Please check its status with PPB before continuing."

  defp ppb_error_message(:unavailable),
    do: "We couldn't reach the PPB registry to verify this license. Try again in a moment."

  defp ppb_error_message(_ppb_check),
    do: "Please verify this location's PPB license before continuing."

  defp maybe_check_kmlttb(socket, params, site_params) do
    if Map.get(params, "_target") in [
         ["site", "kmlttb_facility_name"],
         ["site", "kmlttb_license_number"]
       ] do
      check_kmlttb(socket, site_params)
    else
      socket
    end
  end

  defp check_kmlttb(socket, site_params) do
    required = Site.kmlttb_required?(Map.get(site_params, "activities", []))

    facility_name =
      site_params |> Map.get("kmlttb_facility_name", "") |> to_string() |> String.trim()

    license_number =
      site_params |> Map.get("kmlttb_license_number", "") |> to_string() |> String.trim()

    if required && likely_complete_name?(facility_name) &&
         kmlttb_license_complete?(license_number) do
      socket
      |> assign(:kmlttb_check, :checking)
      |> start_async(:kmlttb_lookup, fn ->
        Kmlttb.verify_license(facility_name, license_number)
      end)
    else
      assign(socket, :kmlttb_check, :idle)
    end
  end

  # KMLTTB's licence numbers are unmasked, and every real one we've seen
  # follows "L" + 5 digits + "/" + 2 digits (e.g. "L 01710/26"), with or
  # without the space — so unlike PPB we can gate on the actual format,
  # not just a length guess.
  defp kmlttb_license_complete?(value), do: Regex.match?(~r/^L\s?\d{5}\/\d{2}$/i, value)

  # Fires registry checks only once a field looks plausibly finished, not on
  # every keystroke of a value that's clearly still being typed — a bare
  # non-empty check combined with a short debounce meant a normal pause
  # mid-name (e.g. glancing at a card before typing the next word) fired a
  # real external API call for each partial value. License numbers have
  # their own format-specific gates (`ppb_license_complete?/1`,
  # `kmlttb_license_complete?/1`) since we know their real shape; a
  # facility name is free text, so length is the only signal available.
  defp likely_complete_name?(value), do: String.length(value) >= 4

  defp kmlttb_error_message({:ambiguous, _candidates}),
    do:
      "Multiple labs matched that name and license. Pick the correct one below before continuing."

  defp kmlttb_error_message(:name_not_found),
    do:
      "We couldn't verify this lab with KMLTTB. Double-check the facility name and license number."

  defp kmlttb_error_message(:license_mismatch),
    do:
      "We found that lab with KMLTTB, but this license number doesn't match their record for it. Double-check the number."

  defp kmlttb_error_message({:license_inactive, _detail}),
    do:
      "This lab's KMLTTB license was found but isn't currently active. Please check its status with KMLTTB before continuing."

  defp kmlttb_error_message(:unavailable),
    do: "We couldn't reach the KMLTTB registry to verify this license. Try again in a moment."

  defp kmlttb_error_message(_kmlttb_check),
    do: "Please verify this location's KMLTTB license before continuing."

  # Prefills the KMLTTB facility-name field the same way
  # `maybe_autofill_ppb_facility_name/1` does for PPB — left editable, since
  # a lab's KMLTTB trading name can legitimately differ from the parent
  # organization's GS1 legal name.
  defp maybe_autofill_kmlttb_facility_name(socket) do
    changeset = socket.assigns.site_form.source

    if Site.kmlttb_required?(Ecto.Changeset.get_field(changeset, :activities) || []) do
      autofill_field(
        socket,
        :site_form,
        :site,
        :kmlttb_facility_name,
        Ecto.Changeset.get_field(changeset, :name)
      )
    else
      socket
    end
  end

  # Prefills the PPB facility-name field from the site's (already-resolved)
  # GLN-matched name once a licensable activity is selected, the same
  # "verified name feeds the next field" pattern used for the GS1 steps —
  # left editable, since a branch's PPB trading name can legitimately differ
  # from the parent organization's GS1 legal name.
  defp maybe_autofill_ppb_facility_name(socket) do
    changeset = socket.assigns.site_form.source

    if Site.ppb_ftype(Ecto.Changeset.get_field(changeset, :activities) || []) do
      autofill_field(
        socket,
        :site_form,
        :site,
        :ppb_facility_name,
        Ecto.Changeset.get_field(changeset, :name)
      )
    else
      socket
    end
  end

  defp current_site_ftype(form), do: Site.ppb_ftype(form[:activities].value || [])
  defp current_site_lab_required?(form), do: Site.kmlttb_required?(form[:activities].value || [])

  defp gln_present?(site_params) do
    site_params |> Map.get("gln", "") |> to_string() |> String.trim() != ""
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

  # `continue_operating_model`/`continue_regulatory_details` rebuild the
  # site changeset every time they run — including a second time, if the
  # user goes back and continues again without changing anything upstream.
  # Unconditionally defaulting to `suggested_site_activities/1` there would
  # silently discard whatever the user explicitly picked on the site-setup
  # step's activity-choice radio (e.g. "Retail pharmacy + diagnostic lab"
  # when the plain default would only suggest the first one). Only fall
  # back to the suggestion when there's nothing already selected, or what's
  # selected is no longer one of the valid choices for the current
  # operating models (e.g. the user went back and removed a model).
  defp preserved_or_suggested_site_activities(socket, org_params) do
    current =
      socket
      |> site_base()
      |> then(& &1.activities)
      |> List.wrap()
      |> Enum.map(&to_string/1)

    valid_choices = org_params |> site_activity_choices() |> Enum.map(&MapSet.new(&1.activities))

    if current != [] and MapSet.new(current) in valid_choices do
      current
    else
      suggested_site_activities(org_params)
    end
  end

  defp operating_model_options do
    [
      {"pharmacy", "Retail pharmacy", "Dispense medicines directly to patients",
       "hero-building-storefront"},
      {"laboratory", "Diagnostic laboratory", "Collect specimens and perform diagnostic tests",
       "hero-beaker"},
      {"distributor", "Pharmaceutical wholesale",
       "Supply branches and licensed healthcare buyers", "hero-truck"}
    ]
  end

  # The four real-world premises types a site can actually be licensed as.
  # Retail and wholesale are deliberately never offered together — PPB
  # licenses them on separate premises (see `Site.validate_activity_exclusivity/1`)
  # — and wholesale + lab is left out for now pending confirmation with
  # PPB/KMLTTB on whether that combination is actually valid.
  defp site_activity_choices(org_params) do
    allowed = MapSet.new(suggested_site_activities(org_params))

    [
      %{
        key: "pharmacy",
        label: "Retail pharmacy",
        description: "Dispense medicines directly to patients",
        icon: "hero-building-storefront",
        activities: ["pharmacy"]
      },
      %{
        key: "laboratory",
        label: "Diagnostic laboratory",
        description: "Collect specimens and perform diagnostic tests",
        icon: "hero-beaker",
        activities: ["laboratory"]
      },
      %{
        key: "pharmacy_laboratory",
        label: "Retail pharmacy + diagnostic lab",
        description: "Dispense medicines and provide diagnostic testing at the same location",
        icon: "hero-building-storefront",
        activities: ["pharmacy", "laboratory"]
      },
      %{
        key: "distribution",
        label: "Pharmaceutical wholesale",
        description: "Supply branches, pharmacies, hospitals and other licensed facilities",
        icon: "hero-truck",
        activities: ["distribution"]
      }
    ]
    |> Enum.filter(fn choice -> Enum.all?(choice.activities, &(&1 in allowed)) end)
  end

  defp operating_model_values(form) do
    form[:operating_models].value |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp operating_model_selected?(form, value) do
    form |> operating_model_values() |> Enum.map(&to_string/1) |> Enum.member?(value)
  end

  defp selected_operating_model_count(form), do: form |> operating_model_values() |> length()

  defp activity_choice_selected?(form, choice) do
    current = form[:activities].value |> List.wrap() |> Enum.map(&to_string/1) |> MapSet.new()
    MapSet.new(choice.activities) == current
  end

  defp step_index(step), do: Enum.find_index(@steps, &(&1 == step)) + 1
  defp step_label(step), do: Map.fetch!(@step_labels, step)
  defp total_steps, do: length(@steps)

  def render(assigns) do
    ~H"""
    <div
      id="signup-onboarding"
      class="auth-shell lg:h-svh lg:overflow-hidden"
      data-step={@step}
      data-signup-complete={to_string(@trigger_login)}
      phx-hook=".SignupDraft"
    >
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SignupDraft">
        const storageKey = "thamani-dawa:signup-draft:v2"
        const draftVersion = 2
        const lifetime = 12 * 60 * 60 * 1000

        export default {
          mounted() {
            this.draft = this.readDraft()
            this.capture = () => this.captureVisibleFields()
            this.el.addEventListener("input", this.capture)
            this.el.addEventListener("change", this.capture)
            this.handleEvent("clear_signup_draft", () => this.clearDraft())

            if (this.draft) {
              this.showRestoring()
              this.restoreTimeout = setTimeout(() => this.finishRestoring(), 2000)
              this.pushEvent("restore_signup_draft", this.draft, () => this.finishRestoring())
            }
          },

          updated() {
            if (this.el.dataset.signupComplete === "true") {
              this.clearDraft()
              return
            }

            this.captureVisibleFields()
          },

          destroyed() {
            clearTimeout(this.restoreTimeout)
            this.el.removeEventListener("input", this.capture)
            this.el.removeEventListener("change", this.capture)
          },

          readDraft() {
            try {
              const draft = JSON.parse(localStorage.getItem(storageKey))
              if (!draft || draft.version !== draftVersion || draft.expiresAt <= Date.now()) {
                localStorage.removeItem(storageKey)
                return null
              }
              return draft
            } catch (_error) {
              localStorage.removeItem(storageKey)
              return null
            }
          },

          captureVisibleFields() {
            const draft = this.draft || {
              version: draftVersion,
              organization: {},
              site: {}
            }

            draft.step = this.el.dataset.step
            draft.expiresAt = Date.now() + lifetime
            draft.organization = this.formValues("organization", [
              "operating_models",
              "gs1_company_prefix",
              "name"
            ], draft.organization)
            draft.site = this.formValues("site", [
              "activity_choice",
              "gln",
              "name",
              "address",
              "ppb_facility_name",
              "license_number",
              "kmlttb_facility_name",
              "kmlttb_license_number"
            ], draft.site)

            this.draft = draft
            try { localStorage.setItem(storageKey, JSON.stringify(draft)) } catch (_error) {}
          },

          formValues(scope, fields, previous) {
            const values = {...(previous || {})}

            fields.forEach(field => {
              const inputs = [...this.el.querySelectorAll(`[name="${scope}[${field}]"], [name="${scope}[${field}][]"]`)]
              if (!inputs.length) return

              const multiple = inputs.some(input => input.name.endsWith("[]"))
              const isRadioGroup = inputs.every(input => input.type === "radio")

              if (multiple || inputs.some(input => input.type === "checkbox")) {
                values[field] = inputs
                  .filter(input => input.value && (input.type !== "checkbox" || input.checked))
                  .map(input => input.value)
              } else if (isRadioGroup) {
                // Several radios share this name; the last one in the DOM
                // isn't necessarily the checked one, unlike a plain text/
                // hidden input, so it must be found explicitly.
                const checked = inputs.find(input => input.checked)
                values[field] = checked ? checked.value : ""
              } else {
                values[field] = inputs[inputs.length - 1].value
              }
            })

            return values
          },

          clearDraft() {
            this.draft = null
            try { localStorage.removeItem(storageKey) } catch (_error) {}
          },

          showRestoring() {
            const restoring = this.el.querySelector("#signup-restoring")
            if (restoring) {
              restoring.hidden = false
              restoring.classList.remove("hidden")
            }
          },

          finishRestoring() {
            clearTimeout(this.restoreTimeout)
            const restoring = this.el.querySelector("#signup-restoring")
            if (restoring) {
              restoring.hidden = true
              restoring.classList.add("hidden")
            }
          }
        }
      </script>

      <div
        id="signup-restoring"
        role="status"
        aria-live="polite"
        phx-update="ignore"
        hidden
        class="hidden fixed inset-0 z-[100] flex items-center justify-center bg-[var(--thamani-snow)]"
      >
        <div class="flex flex-col items-center px-6 text-center">
          <span class="flex size-12 items-center justify-center rounded-full bg-[color-mix(in_srgb,var(--thamani-lime)_22%,white)] text-[var(--thamani-forest)]">
            <.icon name="hero-arrow-path" class="size-6 animate-spin" />
          </span>
          <p class="mt-4 text-base font-semibold text-[var(--thamani-forest)]">
            Restoring your progress&hellip;
          </p>
          <p class="mt-1 text-sm text-[var(--thamani-pewter)]">
            Taking you back to where you left off.
          </p>
        </div>
      </div>

      <div class="auth-aside hidden lg:flex lg:h-svh">
        <.link navigate={~p"/"} aria-label="Thamani Dawa home" style="width: 200px;">
          <img src="/images/logo-transparent.png" alt="" class="h-auto w-full brightness-0 invert" />
        </.link>

        <div>
          <span
            class="thamani-badge"
            style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px; margin-bottom: 24px; display: inline-flex; align-items: center; gap: 7px;"
          >
            <svg
              viewBox="0 0 24 24"
              width="14"
              height="14"
              aria-hidden="true"
              style="stroke: currentColor; stroke-width: 1.6; fill: none;"
            >
              <path d="M4 5v14M8 5v14M11 5v14M15 5v14M17 5v14M20 5v14" />
            </svg>
            GS1 Compliant · Built for Kenya
          </span>
          <h2 style="font-size: clamp(28px, 2.8vw, 40px); font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-snow); text-wrap: balance; margin: 16px 0 20px;">
            Start with clarity. Scale with confidence.
          </h2>
          <p style="font-size: 16px; line-height: 1.65; color: rgba(252,252,247,0.55); max-width: 340px;">
            Configure a pharmacy, laboratory, distribution business, or a combination, then invite your team and start operating.
          </p>
        </div>

        <div style="border-top: 1px solid rgba(252,252,247,0.1); padding-top: 28px;">
          <p style="font-size: 15px; font-weight: 350; color: rgba(252,252,247,0.75); line-height: 1.55; font-style: italic; margin-bottom: 16px;">
            "We were up and running in a single afternoon: stock, prescriptions, everything."
          </p>
          <p style="font-size: 13px; font-weight: 500; color: rgba(252,252,247,0.45);">
            Jane Mwangi · Owner, MedPoint Pharmacy, Nakuru
          </p>
        </div>
      </div>

      <div class="auth-form-panel lg:h-svh lg:overflow-y-auto">
        <div class="auth-form-inner">
          <ThamaniDawaWeb.Layouts.flash_group flash={@flash} />

          <.progress_bar
            current={step_index(@step)}
            total={total_steps()}
            label={step_label(@step)}
            class="mb-7"
          />

          <div id={"step-panel-#{@step}"} class="thamani-step-enter">
            <%= case @step do %>
              <% :operating_model -> %>
                <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
                  Tell us about your organization
                </h1>
                <p class="mb-8 text-[15px] leading-6 text-[var(--thamani-pewter)]">
                  Select all the services you operate. You can choose more than one.
                </p>

                <.form
                  for={@org_form}
                  id="organization-setup-form"
                  phx-change="validate_operating_model"
                  phx-submit="continue_operating_model"
                >
                  <fieldset class="mb-6">
                    <legend class="sr-only">Organization services</legend>
                    <div class="mb-3 flex items-center justify-between gap-3">
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
                        <.activity_card
                          name="organization[operating_models][]"
                          value={value}
                          label={label}
                          description={description}
                          icon={icon}
                          selected={operating_model_selected?(@org_form, value)}
                        />
                      <% end %>
                    </div>
                    <%= for error <- @org_form[:operating_models].errors do %>
                      <p class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
                    <% end %>
                  </fieldset>

                  <.thamani_btn id="onboarding-continue" type="submit" variant="primary">
                    Continue <.icon name="hero-arrow-right" class="ml-2 size-4" />
                  </.thamani_btn>
                </.form>
              <% :regulatory_details -> %>
                <h1 class="mb-3 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
                  Verify your organization
                </h1>
                <p class="mb-10 max-w-3xl text-[15px] leading-6 text-[var(--thamani-pewter)]">
                  Enter your GS1 company prefix to confirm your organization's identity and
                  registered name.
                </p>

                <.form
                  for={@org_form}
                  id="regulatory-details-form"
                  phx-change="validate_regulatory_details"
                  phx-submit="continue_regulatory_details"
                >
                  <input
                    :for={model <- operating_model_values(@org_form)}
                    type="hidden"
                    name="organization[operating_models][]"
                    value={model}
                  />
                  <input
                    type="hidden"
                    name="organization[name]"
                    value={@org_form[:name].value}
                  />

                  <div class="mb-8">
                    <.thamani_input
                      field={@org_form[:gs1_company_prefix]}
                      label="GS1 company prefix"
                      placeholder="e.g. 6160001"
                      phx-debounce="500"
                      required
                    />
                    <%= case @prefix_check do %>
                      <% :checking -> %>
                        <p class="mb-2 -mt-4 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--thamani-pewter)]">
                          <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                          Checking with the GS1 registry&hellip;
                        </p>
                      <% {:matched, name} when is_binary(name) -> %>
                        <p class="mb-2 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2 text-xs font-semibold text-[var(--thamani-forest)]">
                          <.icon name="hero-check-circle" class="size-4" /> Verified · matches {name}
                        </p>
                      <% {:matched, nil} -> %>
                        <p class="mb-2 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2 text-xs font-semibold text-[var(--thamani-forest)]">
                          <.icon name="hero-check-circle" class="size-4" /> Verified with GS1
                        </p>
                      <% {:inactive, name} when is_binary(name) -> %>
                        <p class="mb-2 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          Found · matches {name} · not currently active in the GS1 registry.
                        </p>
                      <% {:inactive, nil} -> %>
                        <p class="mb-2 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          Found in the GS1 registry, but not currently active.
                        </p>
                      <% :not_found -> %>
                        <p class="mb-2 -mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          We couldn't find this prefix in the GS1 registry. Double-check the number before continuing.
                        </p>
                      <% {:name_taken, _name} -> %>
                        <div class="mb-2 -mt-4 flex items-start gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
                          <div>
                            <p>An organization is already registered with this GS1 company prefix.</p>
                            <p class="mt-1">
                              If that's you, <a href="/login" class="underline">log in</a> instead.
                            </p>
                          </div>
                        </div>
                      <% _ -> %>
                        <p class="mb-2 -mt-4 text-xs text-[var(--thamani-pewter)]">
                          We verify this with the GS1 registry as soon as you enter it.
                        </p>
                    <% end %>

                    <aside
                      :if={not match?({:matched, _}, @prefix_check)}
                      id="gs1-prefix-help"
                      class="mt-5 rounded-xl border border-[color-mix(in_srgb,var(--thamani-forest)_14%,white)] bg-[color-mix(in_srgb,var(--thamani-forest)_4%,white)] px-5 py-5"
                    >
                      <div class="flex items-start gap-4">
                        <.icon
                          name="hero-information-circle"
                          class="mt-0.5 size-5 shrink-0 text-[var(--thamani-forest)]"
                        />
                        <div>
                          <p class="text-sm font-semibold text-[var(--thamani-forest)]">
                            Not sure what this is?
                          </p>
                          <p class="mt-1.5 max-w-2xl text-xs leading-5 text-[var(--thamani-pewter)]">
                            A GS1 company prefix identifies your organization and is used to create
                            GS1 identifiers for your locations and products.
                          </p>
                          <a
                            id="gs1-prefix-registration-link"
                            href="https://gs1kenya.org/"
                            target="_blank"
                            rel="noopener noreferrer"
                            class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-[var(--thamani-forest)] underline decoration-[color-mix(in_srgb,var(--thamani-forest)_35%,transparent)] underline-offset-4 transition hover:decoration-[var(--thamani-forest)]"
                          >
                            Don’t have one? Get a prefix from GS1 Kenya
                            <.icon name="hero-arrow-up-right" class="size-3.5" />
                          </a>
                        </div>
                      </div>
                    </aside>
                  </div>

                  <div class="flex items-center gap-4">
                    <button
                      id="regulatory-details-back"
                      type="button"
                      phx-click="back"
                      phx-value-from="regulatory_details"
                      class="inline-flex h-11 items-center justify-center rounded-full border border-[var(--thamani-stone)] bg-white px-5 text-sm font-medium text-[var(--thamani-forest)] transition hover:border-[var(--thamani-forest)]"
                    >
                      <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
                    </button>
                    <.thamani_btn
                      id="regulatory-details-continue"
                      type="submit"
                      variant="primary"
                      disabled={@prefix_check == :checking}
                    >
                      <%= if @prefix_check == :checking do %>
                        <.icon name="hero-arrow-path" class="mr-2 size-4 animate-spin" />
                        Checking GS1&hellip;
                      <% else %>
                        Continue <.icon name="hero-arrow-right" class="ml-2 size-4" />
                      <% end %>
                    </.thamani_btn>
                  </div>
                </.form>
              <% :main_location -> %>
                <h1 class="mb-2 text-[32px] font-light leading-tight tracking-[-0.4px] text-[var(--thamani-forest)]">
                  Set up your main location
                </h1>
                <p class="mb-8 text-[15px] leading-6 text-[var(--thamani-pewter)]">
                  Verify this location first, then choose what this specific premises is licensed
                  to do. You can add other branches and wholesale locations later.
                </p>

                <.form
                  for={@site_form}
                  id="site-setup-form"
                  phx-change="validate_site"
                  phx-submit="continue_site"
                >
                  <input
                    :if={not match?({:matched, nil, _}, @gln_check)}
                    type="hidden"
                    name="site[name]"
                    value={@site_form[:name].value}
                  />
                  <input type="hidden" name="site[address]" value={@site_form[:address].value} />

                  <div class="mb-8">
                    <.thamani_input
                      field={@site_form[:gln]}
                      label="Location GLN"
                      placeholder="13-digit GS1 Global Location Number"
                      phx-debounce="500"
                      required
                    />
                    <%= case @gln_check do %>
                      <% :checking -> %>
                        <p class="-mt-4 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--thamani-pewter)]">
                          <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                          Checking with the GS1 registry&hellip;
                        </p>
                      <% {:matched, name, address} when is_binary(name) -> %>
                        <div class="-mt-4 mb-2 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2.5 text-xs font-semibold text-[var(--thamani-forest)]">
                          <p class="inline-flex items-center gap-1.5">
                            <.icon name="hero-check-circle" class="size-4" /> Verified · {name}
                          </p>
                          <p :if={address} class="mt-1 font-normal text-[var(--thamani-pewter)]">
                            {address}
                          </p>
                        </div>
                      <% {:matched, nil, address} -> %>
                        <div class="-mt-4 mb-2 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2.5 text-xs font-semibold text-[var(--thamani-forest)]">
                          <p class="inline-flex items-center gap-1.5">
                            <.icon name="hero-check-circle" class="size-4" /> Verified with GS1
                          </p>
                          <p :if={address} class="mt-1 font-normal text-[var(--thamani-pewter)]">
                            {address}
                          </p>
                        </div>
                        <.thamani_input
                          field={@site_form[:name]}
                          label="Site name"
                          placeholder="e.g. Afya CBD"
                          phx-debounce="blur"
                          required
                        />
                      <% {:inactive, name, address} when is_binary(name) -> %>
                        <div class="-mt-4 mb-2 rounded-lg bg-amber-50 px-3 py-2.5 text-xs font-semibold text-amber-800">
                          <p class="inline-flex items-center gap-1.5">
                            <.icon name="hero-exclamation-triangle" class="size-4" />
                            Found · {name} · not currently active in the GS1 registry.
                          </p>
                          <p :if={address} class="mt-1 font-normal text-amber-700">
                            {address}
                          </p>
                        </div>
                      <% {:inactive, nil, _address} -> %>
                        <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          Found in the GS1 registry, but not currently active.
                        </p>
                      <% {:taken, _name, _address} -> %>
                        <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          This GLN is already registered to another location on Thamani Dawa. Double-check the number, or use a different GLN.
                        </p>
                      <% :not_found -> %>
                        <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          We couldn't find this GLN in the GS1 registry. Double-check the number before continuing.
                        </p>
                      <% :invalid_check_digit -> %>
                        <p class="-mt-4 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                          <.icon name="hero-exclamation-triangle" class="size-4" />
                          That doesn't look like a valid GLN. Double-check the digits.
                        </p>
                      <% :unavailable -> %>
                        <p class="-mt-4 text-xs text-[var(--thamani-pewter)]">
                          We couldn't reach the GS1 registry to verify this GLN. Try again in a
                          moment.
                        </p>
                      <% _ -> %>
                        <p class="mb-2 -mt-4 text-xs text-[var(--thamani-pewter)]">
                          We verify this with the GS1 registry as soon as you enter it.
                        </p>
                    <% end %>

                    <aside
                      :if={not match?({:matched, _, _}, @gln_check)}
                      id="gln-help"
                      class="mt-5 rounded-xl border border-[color-mix(in_srgb,var(--thamani-forest)_14%,white)] bg-[color-mix(in_srgb,var(--thamani-forest)_4%,white)] px-5 py-5"
                    >
                      <div class="flex items-start gap-4">
                        <.icon
                          name="hero-information-circle"
                          class="mt-0.5 size-5 shrink-0 text-[var(--thamani-forest)]"
                        />
                        <div>
                          <p class="text-sm font-semibold text-[var(--thamani-forest)]">
                            Not sure what this is?
                          </p>
                          <p class="mt-1.5 max-w-2xl text-xs leading-5 text-[var(--thamani-pewter)]">
                            A GLN uniquely identifies this physical location. Each additional
                            branch or wholesale premises should use its own GLN.
                          </p>
                          <a
                            id="gln-registration-link"
                            href={gs1_gln_registration_url()}
                            target="_blank"
                            rel="noopener noreferrer"
                            class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-[var(--thamani-forest)] underline decoration-[color-mix(in_srgb,var(--thamani-forest)_35%,transparent)] underline-offset-4 transition hover:decoration-[var(--thamani-forest)]"
                          >
                            Don’t have one? Get a GLN from GS1 Kenya
                            <.icon name="hero-arrow-up-right" class="size-3.5" />
                          </a>
                        </div>
                      </div>
                    </aside>
                  </div>

                  <%= if match?({:matched, _, _}, @gln_check) do %>
                    <%= case site_activity_choices(@organization_params) do %>
                      <% [only] -> %>
                        <input type="hidden" name="site[activity_choice]" value={only.key} />
                        <div
                          id="single-site-activity"
                          class="mb-7 rounded-xl border border-[color-mix(in_srgb,var(--thamani-forest)_18%,white)] bg-[color-mix(in_srgb,var(--thamani-lime)_12%,white)] px-4 py-3"
                        >
                          <p class="text-xs font-medium text-[var(--thamani-pewter)]">
                            Activity at this location
                          </p>
                          <p class="mt-1 text-sm font-semibold text-[var(--thamani-forest)]">
                            {only.label}
                          </p>
                          <p class="mt-0.5 text-xs text-[var(--thamani-pewter)]">
                            {only.description}
                          </p>
                        </div>
                      <% choices -> %>
                        <fieldset class="mb-7">
                          <legend class="text-sm font-medium text-[var(--thamani-forest)]">
                            What happens at this location?<span class="text-red-600">&nbsp;*</span>
                          </legend>
                          <p class="mb-3 mt-1 max-w-2xl text-xs leading-5 text-[var(--thamani-pewter)]">
                            Choose the option that matches how this premises is actually
                            licensed. A retail branch and a wholesale warehouse are always
                            separate locations, so pick whichever this one is.
                          </p>
                          <div class="grid grid-cols-1 gap-2">
                            <%= for choice <- choices do %>
                              <.activity_card
                                type="radio"
                                name="site[activity_choice]"
                                value={choice.key}
                                label={choice.label}
                                description={choice.description}
                                icon={choice.icon}
                                selected={activity_choice_selected?(@site_form, choice)}
                                compact
                              />
                            <% end %>
                          </div>
                          <%= for error <- @site_form[:activities].errors do %>
                            <p class="mt-2 text-xs text-red-700">{translate_error(error)}</p>
                          <% end %>
                        </fieldset>
                    <% end %>

                    <%= if ftype = current_site_ftype(@site_form) do %>
                      <div class="mb-7">
                        <h2 class="mb-1 text-sm font-medium text-[var(--thamani-forest)]">
                          PPB facility license
                        </h2>
                        <p class="mb-4 text-xs leading-5 text-[var(--thamani-pewter)]">
                          <%= if ftype == "retail" do %>
                            Retail pharmacy premises are licensed by PPB separately from
                            wholesale ones — verify this location's facility license below.
                          <% else %>
                            Wholesale distribution premises are licensed by PPB separately
                            from retail ones — verify this location's facility license below.
                          <% end %>
                        </p>

                        <.thamani_input
                          field={@site_form[:ppb_facility_name]}
                          label="Facility name (as licensed with PPB)"
                          placeholder="e.g. Afya CBD Pharmacy"
                          phx-debounce="900"
                          required
                        />
                        <.thamani_input
                          field={@site_form[:license_number]}
                          label="PPB license number"
                          placeholder="e.g. RD1234"
                          phx-debounce="900"
                          required
                        />

                        <%= case @ppb_check do %>
                          <% :checking -> %>
                            <p class="-mt-3 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--thamani-pewter)]">
                              <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                              Checking with the PPB registry&hellip;
                            </p>
                          <% {:matched, detail} -> %>
                            <div class="-mt-3 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2.5 text-xs font-semibold text-[var(--thamani-forest)]">
                              <p class="inline-flex items-center gap-1.5">
                                <.icon name="hero-check-circle" class="size-4" /> Verified with PPB
                              </p>
                              <p
                                :if={detail[:valid_till]}
                                class="mt-1 font-normal text-[var(--thamani-pewter)]"
                              >
                                Valid till {detail[:valid_till]}
                              </p>
                            </div>
                          <% {:license_inactive, detail} -> %>
                            <div class="-mt-3 rounded-lg bg-amber-50 px-3 py-2.5 text-xs font-semibold text-amber-800">
                              <p class="inline-flex items-center gap-1.5">
                                <.icon name="hero-exclamation-triangle" class="size-4" />
                                Found with PPB, but not currently active.
                              </p>
                              <p :if={detail[:status]} class="mt-1 font-normal text-amber-700">
                                Licence status: {detail[:status]}
                              </p>
                            </div>
                          <% {:ambiguous, candidates} -> %>
                            <div class="-mt-3 rounded-lg bg-amber-50 px-3 py-3 text-xs text-amber-800">
                              <p class="mb-2 inline-flex items-center gap-1.5 font-semibold">
                                <.icon name="hero-exclamation-triangle" class="size-4" />
                                Multiple facilities matched — pick the correct one:
                              </p>
                              <div class="flex flex-col gap-2">
                                <%= for {candidate, index} <- Enum.with_index(candidates) do %>
                                  <button
                                    type="button"
                                    phx-click="select_ppb_candidate"
                                    phx-value-index={index}
                                    class="rounded-lg border border-amber-200 bg-white px-3 py-2 text-left font-medium text-amber-900 hover:border-amber-400"
                                  >
                                    {candidate[:name]}
                                    <span :if={candidate[:county]} class="font-normal text-amber-700">
                                      · {candidate[:county]}
                                    </span>
                                  </button>
                                <% end %>
                              </div>
                            </div>
                          <% :name_not_found -> %>
                            <p class="-mt-3 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                              <.icon name="hero-exclamation-triangle" class="size-4" />
                              We couldn't find a facility by that name with PPB. Double-check the spelling, or confirm this matches how it's actually licensed (retail vs. wholesale).
                            </p>
                          <% :license_mismatch -> %>
                            <p class="-mt-3 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                              <.icon name="hero-exclamation-triangle" class="size-4" />
                              We found that facility, but this license number doesn't match PPB's record for it.
                            </p>
                          <% :unavailable -> %>
                            <p class="-mt-3 text-xs text-[var(--thamani-pewter)]">
                              We couldn't reach the PPB registry to verify this license. Try again in a moment.
                            </p>
                          <% _ -> %>
                            <p class="-mt-3 text-xs text-[var(--thamani-pewter)]">
                              We verify this with the PPB facilities register once both fields are filled in.
                            </p>
                        <% end %>
                      </div>
                    <% end %>

                    <%= if current_site_lab_required?(@site_form) do %>
                      <div class="mb-7">
                        <h2 class="mb-1 text-sm font-medium text-[var(--thamani-forest)]">
                          KMLTTB lab license
                        </h2>
                        <p class="mb-4 text-xs leading-5 text-[var(--thamani-pewter)]">
                          Diagnostic labs are licensed by KMLTTB, separately from PPB — verify
                          this location's lab license below.
                        </p>

                        <.thamani_input
                          field={@site_form[:kmlttb_facility_name]}
                          label="Facility name (as licensed with KMLTTB)"
                          placeholder="e.g. Afya CBD Diagnostics"
                          phx-debounce="900"
                          required
                        />
                        <.thamani_input
                          field={@site_form[:kmlttb_license_number]}
                          label="KMLTTB license number"
                          placeholder="e.g. L 01234/26"
                          phx-debounce="900"
                          required
                        />

                        <%= case @kmlttb_check do %>
                          <% :checking -> %>
                            <p class="-mt-3 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--thamani-pewter)]">
                              <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                              Checking with the KMLTTB registry&hellip;
                            </p>
                          <% {:matched, detail} -> %>
                            <div class="-mt-3 rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2.5 text-xs font-semibold text-[var(--thamani-forest)]">
                              <p class="inline-flex items-center gap-1.5">
                                <.icon name="hero-check-circle" class="size-4" /> Verified with KMLTTB
                              </p>
                              <p
                                :if={detail[:valid_until]}
                                class="mt-1 font-normal text-[var(--thamani-pewter)]"
                              >
                                Valid until {detail[:valid_until]}
                              </p>
                            </div>
                          <% {:license_inactive, detail} -> %>
                            <div class="-mt-3 rounded-lg bg-amber-50 px-3 py-2.5 text-xs font-semibold text-amber-800">
                              <p class="inline-flex items-center gap-1.5">
                                <.icon name="hero-exclamation-triangle" class="size-4" />
                                Found with KMLTTB, but not currently active.
                              </p>
                              <p :if={detail[:status]} class="mt-1 font-normal text-amber-700">
                                Status: {detail[:status]}
                              </p>
                            </div>
                          <% {:ambiguous, candidates} -> %>
                            <div class="-mt-3 rounded-lg bg-amber-50 px-3 py-3 text-xs text-amber-800">
                              <p class="mb-2 inline-flex items-center gap-1.5 font-semibold">
                                <.icon name="hero-exclamation-triangle" class="size-4" />
                                Multiple labs matched — pick the correct one:
                              </p>
                              <div class="flex flex-col gap-2">
                                <%= for {candidate, index} <- Enum.with_index(candidates) do %>
                                  <button
                                    type="button"
                                    phx-click="select_kmlttb_candidate"
                                    phx-value-index={index}
                                    class="rounded-lg border border-amber-200 bg-white px-3 py-2 text-left font-medium text-amber-900 hover:border-amber-400"
                                  >
                                    {candidate[:name]}
                                    <span :if={candidate[:county]} class="font-normal text-amber-700">
                                      · {candidate[:county]}
                                    </span>
                                  </button>
                                <% end %>
                              </div>
                            </div>
                          <% :name_not_found -> %>
                            <p class="-mt-3 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                              <.icon name="hero-exclamation-triangle" class="size-4" />
                              We couldn't verify this lab with KMLTTB. Double-check the facility name and license number.
                            </p>
                          <% :license_mismatch -> %>
                            <p class="-mt-3 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                              <.icon name="hero-exclamation-triangle" class="size-4" />
                              We found that lab, but this license number doesn't match KMLTTB's record for it.
                            </p>
                          <% :unavailable -> %>
                            <p class="-mt-3 text-xs text-[var(--thamani-pewter)]">
                              We couldn't reach the KMLTTB registry to verify this license. Try again in a moment.
                            </p>
                          <% _ -> %>
                            <p class="-mt-3 text-xs text-[var(--thamani-pewter)]">
                              We verify this with the KMLTTB lab register once both fields are filled in.
                            </p>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>

                  <div class="flex items-center gap-3">
                    <button
                      id="main-location-back"
                      type="button"
                      phx-click="back"
                      phx-value-from="main_location"
                      class="inline-flex h-11 items-center justify-center rounded-full border border-[var(--thamani-stone)] bg-white px-5 text-sm font-medium text-[var(--thamani-forest)] transition hover:border-[var(--thamani-forest)]"
                    >
                      <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
                    </button>
                    <.thamani_btn
                      id="main-location-continue"
                      type="submit"
                      variant="primary"
                      disabled={
                        not match?({:matched, _, _}, @gln_check) or
                          (current_site_ftype(@site_form) != nil and
                             not match?({:matched, _}, @ppb_check)) or
                          (current_site_lab_required?(@site_form) and
                             not match?({:matched, _}, @kmlttb_check))
                      }
                    >
                      <%= if @gln_check == :checking do %>
                        <.icon name="hero-arrow-path" class="mr-2 size-4 animate-spin" />
                        Checking GS1 registry&hellip;
                      <% else %>
                        Continue <.icon name="hero-arrow-right" class="ml-2 size-4" />
                      <% end %>
                    </.thamani_btn>
                  </div>
                </.form>
              <% :administrator -> %>
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
                      Create account
                    </.thamani_btn>
                  </div>
                </.form>
            <% end %>
          </div>

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
      </div>
    </div>
    """
  end
end
