defmodule ThamaniDawaWeb.SiteLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Grp
  alias ThamaniDawa.Grp.Licence
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @default_filters %{activities: "", status: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign(:show_onboarding_site_form?, false)
     |> assign_sites()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> assign_sites()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)

    socket
    |> assign(form: to_form(Site.changeset(%Site{}, %{}), as: :site), site: nil)
    |> assign(:back_path, back_path(params, ~p"/org/sites"))
    |> assign(:gln_check, :idle)
    |> assign(:operating_models, organization.operating_models)
    |> assign(:gs1_company_prefixes, org_prefixes(organization.id))
    |> assign_member_glns(organization)
    |> assign(:onboarding_progress, Organizations.onboarding_progress(organization))
  end

  defp apply_action(socket, :edit, %{"id" => id} = params) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)
    site = Sites.get_site!(organization_id, id)

    socket
    |> assign(form: to_form(Site.changeset(site, %{}), as: :site), site: site)
    |> assign(:back_path, back_path(params, ~p"/org/sites"))
    |> assign(:gln_check, nil)
    |> assign(:operating_models, organization.operating_models)
    |> assign(:gs1_glns, [])
    |> assign(:taken_glns, MapSet.new())
    |> assign(:gln_query, "")
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(form: nil, site: nil, back_path: ~p"/org/sites")
    |> assign(:gln_check, nil)
    |> assign(:operating_models, [])
    |> assign(:gs1_glns, [])
    |> assign(:taken_glns, MapSet.new())
    |> assign(:gln_query, "")
  end

  def handle_event("validate", _, %{assigns: %{live_action: :index}} = socket) do
    {:noreply, socket}
  end

  def handle_event("validate", %{"_target" => ["gln_query"], "gln_query" => query}, socket) do
    {:noreply, assign(socket, :gln_query, query)}
  end

  def handle_event("validate", %{"site" => attrs} = params, socket) do
    attrs = apply_activity_choice(attrs)
    changeset = Site.changeset(socket.assigns.site || %Site{}, attrs)

    socket =
      socket
      |> assign(:form, to_form(changeset, as: :site, action: :validate))
      |> maybe_check_gln(params, attrs)

    {:noreply, socket}
  end

  def handle_event("save", %{"site" => attrs}, %{assigns: %{live_action: :edit}} = socket) do
    save_site(socket, :edit, apply_activity_choice(attrs))
  end

  def handle_event("save", %{"site" => attrs}, socket) do
    attrs = apply_activity_choice(attrs)

    cond do
      socket.assigns.gln_check == :checking ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Still checking the GLN with the GS1 registry. Press Save again in a moment."
         )}

      socket.assigns.gln_check == :idle ->
        {:noreply,
         socket
         |> check_gln(attrs)
         |> put_flash(
           :error,
           "Checking the GLN with the GS1 registry. Press Save again in a moment."
         )}

      socket.assigns.gln_check == :prefix_mismatch ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This GLN does not belong to your verified GS1 company prefix."
         )}

      match?({:inactive, _, _}, socket.assigns.gln_check) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This GLN was found in the registry but isn't currently active."
         )}

      match?({:taken, _, _}, socket.assigns.gln_check) ->
        {:noreply,
         put_flash(socket, :error, "This GLN is already registered to another location.")}

      not match?({:matched, _, _}, socket.assigns.gln_check) ->
        {:noreply, put_flash(socket, :error, "Enter a valid, GS1-verified GLN before saving.")}

      true ->
        save_site(socket, :new, attrs)
    end
  end

  def handle_event("pick_gln", %{"gln" => gln}, socket) do
    row = Enum.find(socket.assigns.gs1_glns, &(&1["gln"] == gln))

    if row && gln_pickable?(row, socket.assigns.taken_glns) do
      attrs = %{"gln" => gln}
      changeset = Site.changeset(%Site{}, attrs)

      {:noreply,
       socket
       |> assign(:form, to_form(changeset, as: :site))
       |> check_gln(attrs)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_gln", _params, socket) do
    {:noreply,
     socket
     |> assign(:gln_check, :idle)
     |> assign(:form, to_form(Site.changeset(%Site{}, %{}), as: :site))}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign_sites()}
  end

  def handle_event("set_filter", %{"field" => field, "value" => value}, socket)
      when field in ["activities", "status"] do
    key = String.to_existing_atom(field)

    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | key => value}) |> assign_sites()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign_sites()}
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site = Sites.get_site!(organization_id, id)

    case Sites.update_site(site, %{is_active: !site.is_active}) do
      {:ok, _updated} ->
        {:noreply, assign_sites(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update site.")}
    end
  end

  def handle_event("open_onboarding_site", _params, socket) do
    {:noreply, assign(socket, :show_onboarding_site_form?, true)}
  end

  def handle_event("close_onboarding_site", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_onboarding_site_form?, false)
     |> assign(:gln_check, :idle)
     |> assign(:form, to_form(Site.changeset(%Site{}, %{}), as: :site))}
  end

  def handle_event("continue_onboarding", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/onboarding?complete=1")}
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :verified, licence}}, socket) do
    name = Licence.name(licence)
    address = Licence.address(licence)
    gln = Map.get(licence, "gln")

    if is_binary(gln) and gln != "" and Sites.gln_taken?(gln) do
      {:noreply, assign(socket, :gln_check, {:taken, name, address})}
    else
      {:noreply,
       socket
       |> assign(:gln_check, {:matched, name, address})
       |> autofill_site_fields(name, address)}
    end
  end

  def handle_async(:gln_lookup, {:ok, {:ok, :inactive, licence}}, socket) do
    {:noreply,
     assign(socket, :gln_check, {:inactive, Licence.name(licence), Licence.address(licence)})}
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

  defp save_site(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Sites.create_site(organization_id, attrs) do
      {:ok, _site} ->
        socket = socket |> put_flash(:info, "Site created.") |> assign_sites()

        if socket.assigns.back_path == ~p"/onboarding" do
          {:noreply,
           socket
           |> assign(:show_onboarding_site_form?, false)
           |> assign(:gln_check, :idle)
           |> assign(:form, to_form(Site.changeset(%Site{}, %{}), as: :site))}
        else
          {:noreply, return_after_save(socket)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp save_site(socket, :edit, attrs) do
    case Sites.update_site(socket.assigns.site, attrs) do
      {:ok, _site} ->
        socket = socket |> put_flash(:info, "Site updated.") |> assign_sites()
        {:noreply, return_after_save(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :site))}
    end
  end

  defp assign_member_glns(socket, organization) do
    rows = Organizations.list_member_gln_rows(organization)

    taken =
      rows
      |> Enum.map(& &1["gln"])
      |> Enum.filter(&Sites.gln_taken?/1)
      |> MapSet.new()

    socket
    |> assign(:gs1_glns, rows)
    |> assign(:taken_glns, taken)
    |> assign(:gln_query, "")
  end

  defp gln_active?(row), do: row["status"] in [true, "true", "active", "Active", 1, "1", nil]

  defp gln_pickable?(row, taken),
    do: gln_active?(row) and not MapSet.member?(taken, row["gln"])

  defp gln_name(row) do
    Enum.find_value(["description", "location", "address"], row["gln"], fn key ->
      case row[key] do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp gln_place(row) do
    [row["address"], row["location"]]
    |> Enum.filter(&(is_binary(&1) and &1 != "" and &1 != gln_name(row)))
    |> Enum.uniq()
    |> Enum.join(" · ")
  end

  defp filter_glns(rows, query) do
    case query |> to_string() |> String.trim() |> String.downcase() do
      "" ->
        rows

      q ->
        terms = String.split(q)

        Enum.filter(rows, fn row ->
          haystack =
            ["gln", "description", "address", "location", "company"]
            |> Enum.map_join(" ", &to_string(row[&1] || ""))
            |> String.downcase()

          Enum.all?(terms, &String.contains?(haystack, &1))
        end)
    end
  end

  defp back_path(%{"return_to" => "onboarding"}, _default), do: ~p"/onboarding"
  defp back_path(%{"return_to" => "dashboard"}, _default), do: ~p"/org/dashboard"
  defp back_path(_params, default), do: default

  defp return_after_save(socket) do
    cond do
      socket.assigns.back_path == ~p"/org/dashboard" ->
        push_navigate(socket, to: ~p"/org/dashboard?tour=1")

      socket.assigns.back_path == ~p"/onboarding" ->
        push_navigate(socket, to: ~p"/onboarding?complete=1")

      true ->
        push_patch(socket, to: socket.assigns.back_path)
    end
  end

  defp assign_sites(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = Sites.list_sites_paginated(organization_id, page)
    sites = page_result.entries

    filtered =
      sites
      |> filter_by_search(socket.assigns.search)
      |> filter_by_activity(socket.assigns.filters.activities)
      |> filter_by_status(socket.assigns.filters.status)

    socket
    |> assign(:sites, filtered)
    |> assign(:page_info, page_result)
  end

  defp filter_by_search(sites, ""), do: sites

  defp filter_by_search(sites, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(sites, fn site ->
      [site.name, site.address]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_activity(sites, ""), do: sites

  defp filter_by_activity(sites, activity) do
    activity = String.to_existing_atom(activity)
    Enum.filter(sites, &(activity in &1.activities))
  end

  defp filter_by_status(sites, ""), do: sites
  defp filter_by_status(sites, "active"), do: Enum.filter(sites, & &1.is_active)
  defp filter_by_status(sites, "inactive"), do: Enum.filter(sites, &(!&1.is_active))

  defp active_filter_count(filters) do
    Enum.count([filters.activities != "", filters.status != ""], & &1)
  end

  defp activity_options do
    [
      {"Pharmacy", "Dispensing & stock", :pharmacy},
      {"Laboratory", "Orders & results", :laboratory},
      {"Distribution", "Stock holding & shipping", :distribution}
    ]
  end

  defp activity_labels(site) do
    Enum.map_join(site.activities, ", ", &Phoenix.Naming.humanize/1)
  end

  defp maybe_check_gln(socket, params, attrs) do
    if socket.assigns.live_action == :new and Map.get(params, "_target") == ["site", "gln"] do
      check_gln(socket, attrs)
    else
      socket
    end
  end

  defp check_gln(socket, attrs) do
    gln = attrs |> Map.get("gln", "") |> to_string() |> String.trim()

    cond do
      not Regex.match?(~r/^\d{13}$/, gln) ->
        assign(socket, :gln_check, :idle)

      not gln_check_digit_valid?(gln) ->
        assign(socket, :gln_check, :invalid_check_digit)

      Sites.gln_taken?(gln) ->
        assign(socket, :gln_check, {:taken, nil, nil})

      not gln_matches_verified_prefix?(gln, socket.assigns[:gs1_company_prefixes] || []) ->
        assign(socket, :gln_check, :prefix_mismatch)

      true ->
        socket
        |> assign(:gln_check, :checking)
        |> start_async(:gln_lookup, fn -> Grp.verify_gln(gln) end)
    end
  end

  defp org_prefixes(organization_id) do
    organization_id |> Organizations.list_gs1_prefixes() |> Enum.map(& &1.prefix)
  end

  # An organization with no GS1 company prefix yet (none added, or none
  # verified) has nothing to mismatch a GLN against, so any GLN passes this
  # gate — the registry lookup below is still the real check.
  defp gln_matches_verified_prefix?(_gln, []), do: true

  defp gln_matches_verified_prefix?(gln, prefixes),
    do: Enum.any?(prefixes, &String.starts_with?(gln, &1))

  defp gln_check_digit_valid?(gln) do
    {payload, check} = String.split_at(gln, -1)
    Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(payload)) == check
  end

  defp autofill_site_fields(socket, name, address) do
    changeset =
      socket.assigns.form.source
      |> maybe_put_blank(:name, name)
      |> maybe_put_blank(:address, address)

    assign(socket, :form, to_form(changeset, as: :site))
  end

  defp maybe_put_blank(changeset, field, value) when is_binary(value) and value != "" do
    if blank?(Ecto.Changeset.get_field(changeset, field)) do
      Ecto.Changeset.put_change(changeset, field, value)
    else
      changeset
    end
  end

  defp maybe_put_blank(changeset, _field, _value), do: changeset

  defp blank?(nil), do: true
  defp blank?(value), do: value |> to_string() |> String.trim() == ""

  defp apply_activity_choice(%{"activity_choice" => choice} = attrs) do
    Map.put(attrs, "activities", activities_for_choice(choice))
  end

  defp apply_activity_choice(attrs), do: attrs

  defp activities_for_choice("pharmacy"), do: ["pharmacy"]
  defp activities_for_choice("laboratory"), do: ["laboratory"]
  defp activities_for_choice("pharmacy_laboratory"), do: ["pharmacy", "laboratory"]
  defp activities_for_choice("distribution"), do: ["distribution"]
  defp activities_for_choice("manufacturing"), do: ["manufacturing"]

  defp activities_for_choice("manufacturing_distribution"),
    do: ["manufacturing", "distribution"]

  defp activities_for_choice(_choice), do: []

  # The four real-world premises types a site can actually be licensed as,
  # filtered to whatever the organization's own operating models (chosen at
  # signup) actually support — mirrors `SignupLive`'s `site_activity_choices/1`.
  defp site_activity_choices(operating_models) do
    allowed =
      operating_models
      |> Enum.flat_map(fn
        :pharmacy -> ["pharmacy"]
        :laboratory -> ["laboratory"]
        :distributor -> ["distribution"]
        :manufacturer -> ["manufacturing"]
        _ -> []
      end)
      |> MapSet.new()

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
        label: "Pharmaceutical distributor",
        description: "Supply medicines to pharmacies, hospitals, and other authorized buyers",
        icon: "hero-truck",
        activities: ["distribution"]
      },
      %{
        key: "manufacturing",
        label: "Pharmaceutical manufacturer",
        description: "Produce and serialize medicines for distribution",
        icon: "hero-cog-8-tooth",
        activities: ["manufacturing"]
      },
      %{
        key: "manufacturing_distribution",
        label: "Manufacturer + distributor",
        description: "Produce medicines and also supply them onward from this location",
        icon: "hero-cog-8-tooth",
        activities: ["manufacturing", "distribution"]
      }
    ]
    |> Enum.filter(fn choice -> Enum.all?(choice.activities, &(&1 in allowed)) end)
  end

  defp activity_choice_selected?(form, choice) do
    current = form[:activities].value |> List.wrap() |> Enum.map(&to_string/1) |> MapSet.new()
    MapSet.new(choice.activities) == current
  end

  attr :form, :map, required: true
  attr :gln_check, :any, default: nil
  attr :rows, :list, required: true
  attr :taken, :any, required: true
  attr :query, :string, default: ""

  defp gln_picker(assigns) do
    selected = assigns.form[:gln].value |> to_string()
    selected_row = Enum.find(assigns.rows, &(&1["gln"] == selected))
    filtered = filter_glns(assigns.rows, assigns.query)
    available = Enum.count(assigns.rows, &gln_pickable?(&1, assigns.taken))

    assigns =
      assign(assigns,
        selected: selected,
        selected_row: selected_row,
        filtered: filtered,
        available: available
      )

    ~H"""
    <div id="gln-picker" class="mb-1">
      <input type="hidden" name="site[gln]" value={@selected} />
      <div class="mb-2 flex items-baseline justify-between gap-3">
        <span class="thamani-label">
          GS1 Global Location Number (GLN)<span class="text-error">&nbsp;*</span>
        </span>
        <span :if={is_nil(@selected_row)} class="text-xs tabular-nums text-thamani-pewter">
          {@available} of {length(@rows)} available
        </span>
      </div>

      <%= if @selected_row do %>
        <div
          id="gln-picker-selected"
          class="flex items-start gap-3 rounded-xl border border-thamani-forest/30 bg-[color-mix(in_srgb,var(--thamani-lime)_10%,white)] p-3"
        >
          <span class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg bg-thamani-forest text-white">
            <.icon name="hero-map-pin" class="size-4 bg-white" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-thamani-forest">
              {gln_name(@selected_row)}
            </p>
            <p :if={gln_place(@selected_row) != ""} class="truncate text-xs text-thamani-pewter">
              {gln_place(@selected_row)}
            </p>
            <p class="mt-1 font-mono text-xs tabular-nums text-thamani-forest/80">{@selected}</p>
          </div>
          <button
            type="button"
            id="gln-picker-change"
            phx-click="clear_gln"
            class="shrink-0 rounded-lg px-2.5 py-1.5 text-xs font-semibold text-thamani-forest transition hover:bg-thamani-forest/10"
          >
            Change
          </button>
        </div>
      <% else %>
        <.td_search
          id="gln-picker-search"
          name="gln_query"
          value={@query}
          placeholder="Search by name, town, address or GLN"
          autocomplete="off"
          phx-debounce="150"
        />

        <ul
          id="gln-picker-list"
          role="listbox"
          class="mt-2 max-h-80 divide-y divide-thamani-stone/70 overflow-y-auto rounded-xl border border-thamani-stone bg-white"
        >
          <li :if={@filtered == []} class="px-4 py-6 text-center text-sm text-thamani-pewter">
            No GLNs match “{@query}”.
          </li>
          <li :for={row <- @filtered} id={"gln-option-#{row["gln"]}"}>
            <% pickable = gln_pickable?(row, @taken) %>
            <button
              type="button"
              phx-click="pick_gln"
              phx-value-gln={row["gln"]}
              disabled={!pickable}
              class={[
                "group flex w-full items-center gap-3 px-3 py-2.5 text-left transition",
                if(pickable,
                  do:
                    "hover:bg-[var(--color-td-hover)] focus-visible:bg-[var(--color-td-hover)] focus-visible:outline-none",
                  else: "cursor-not-allowed opacity-55"
                )
              ]}
            >
              <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-[var(--color-td-control)] text-[var(--color-td-ink-2)] transition group-hover:bg-[var(--color-td-accent)] group-hover:text-[var(--color-td-on-accent)] group-disabled:group-hover:bg-[var(--color-td-control)] group-disabled:group-hover:text-[var(--color-td-ink-2)]">
                <.icon name="hero-building-office-2" class="size-4" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium text-thamani-forest">
                  {gln_name(row)}
                </span>
                <span class="block truncate text-xs text-thamani-pewter">
                  <span class="font-mono tabular-nums">{row["gln"]}</span>
                  <span :if={gln_place(row) != ""}> · {gln_place(row)}</span>
                </span>
              </span>
              <%= cond do %>
                <% MapSet.member?(@taken, row["gln"]) -> %>
                  <span class="shrink-0 rounded-full bg-[var(--color-td-control)] px-2 py-0.5 text-[11px] font-semibold text-[var(--color-td-ink-2)]">
                    Already added
                  </span>
                <% not gln_active?(row) -> %>
                  <span class="shrink-0 rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-800">
                    Inactive
                  </span>
                <% true -> %>
                  <.icon
                    name="hero-chevron-right"
                    class="size-4 shrink-0 text-thamani-pewter/60 transition group-hover:translate-x-0.5 group-hover:text-thamani-forest"
                  />
              <% end %>
            </button>
          </li>
        </ul>
      <% end %>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :gln_check, :any, default: nil
  attr :operating_models, :list, default: []
  attr :gs1_glns, :list, default: []
  attr :taken_glns, :any, default: MapSet.new()
  attr :gln_query, :string, default: ""

  defp site_form(assigns) do
    ~H"""
    <form id="site-form" phx-submit="save" phx-change="validate" class="td-modal-form">
      <%= if @gln_check do %>
        <%= if @gs1_glns != [] do %>
          <.gln_picker
            form={@form}
            gln_check={@gln_check}
            rows={@gs1_glns}
            taken={@taken_glns}
            query={@gln_query}
          />
        <% else %>
          <.td_input
            id="site-gln"
            field={@form[:gln]}
            label="GS1 Global Location Number (GLN)"
            placeholder="13-digit GLN issued by GS1"
            inputmode="numeric"
            phx-debounce="500"
            required
          />
        <% end %>

        <%= case @gln_check do %>
          <% :checking -> %>
            <p class="mb-4 mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-thamani-pewter">
              <.icon name="hero-arrow-path" class="size-3.5 motion-safe:animate-spin" />
              Checking with the GS1 registry&hellip;
            </p>
          <% {:matched, _name, _address} -> %>
            <div class="mb-4 mt-2 rounded-lg bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] px-3 py-2.5 text-xs font-semibold text-thamani-forest">
              <p class="inline-flex items-center gap-1.5">
                <.icon name="hero-check-circle" class="size-4" /> Verified with GS1
              </p>
            </div>
          <% {:inactive, name, address} when is_binary(name) -> %>
            <div class="mb-4 mt-2 rounded-lg bg-amber-50 px-3 py-2.5 text-xs font-semibold text-amber-800">
              <p class="inline-flex items-center gap-1.5">
                <.icon name="hero-exclamation-triangle" class="size-4" />
                Found · {name} · not currently active in the GS1 registry.
              </p>
              <p :if={address} class="mt-1 font-normal text-amber-700">{address}</p>
            </div>
          <% {:inactive, nil, _address} -> %>
            <p class="mb-4 mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              Found in the GS1 registry, but not currently active.
            </p>
          <% {:taken, _name, _address} -> %>
            <p class="mb-4 mt-2 inline-flex items-center gap-1.5 rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-800">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              This GLN is already registered to another location. Double-check the number, or use a different GLN.
            </p>
          <% :not_found -> %>
            <p class="mb-4 mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              We couldn't find this GLN in the GS1 registry. Double-check the number before continuing.
            </p>
          <% :invalid_check_digit -> %>
          <% :prefix_mismatch -> %>
            <p
              id="site-gln-prefix-mismatch"
              class="mb-4 mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800"
            >
              <.icon name="hero-exclamation-triangle" class="size-4" />
              This GLN does not belong to your verified GS1 company prefix.
            </p>
          <% :unavailable -> %>
            <p class="mb-4 mt-2 text-xs text-thamani-pewter">
              We couldn't reach the GS1 registry to verify this GLN. Try again in a moment.
            </p>
          <% _ -> %>
            <p class="mb-4 mt-2 text-xs text-thamani-pewter">
              We verify this with the GS1 registry as soon as you enter it.
            </p>
        <% end %>

        <input
          :if={not match?({:matched, _, _}, @gln_check)}
          type="hidden"
          name="site[address]"
          value={@form[:address].value}
        />

        <%= if match?({:matched, _, _}, @gln_check) do %>
          <div class="td-fgrid is-2">
            <.td_input
              id="site-name"
              field={@form[:name]}
              label="Site name"
              placeholder="e.g. Afya CBD"
              phx-debounce="blur"
              required
            />
            <.td_input
              id="site-address"
              field={@form[:address]}
              label="Address"
              required
            />
          </div>

          <%= case site_activity_choices(@operating_models) do %>
            <% [] -> %>
              <p class="mb-4 text-xs text-red-700">
                No site activities are available for this organization's operating models.
              </p>
            <% [only] -> %>
              <div class="mb-4">
                <.activity_card
                  type="radio"
                  name="site[activity_choice]"
                  value={only.key}
                  label={only.label}
                  description={only.description}
                  icon={only.icon}
                  selected
                  compact
                />
              </div>
            <% choices -> %>
              <fieldset class="mb-4">
                <legend class="mb-2 text-sm font-medium text-thamani-forest">
                  What happens at this location?<span class="text-error">&nbsp;*</span>
                </legend>
                <div class="grid grid-cols-1 gap-2">
                  <.activity_card
                    :for={choice <- choices}
                    type="radio"
                    name="site[activity_choice]"
                    value={choice.key}
                    label={choice.label}
                    description={choice.description}
                    icon={choice.icon}
                    selected={activity_choice_selected?(@form, choice)}
                    compact
                  />
                </div>
                <p :for={error <- @form[:activities].errors} class="mt-2 text-xs text-red-700">
                  {translate_error(error)}
                </p>
              </fieldset>
          <% end %>
        <% end %>
      <% else %>
        <div class="td-fgrid is-2">
          <.td_input id="site-name" field={@form[:name]} label="Name" required />
          <.td_input
            id="site-gln"
            field={@form[:gln]}
            label="GS1 Global Location Number (GLN)"
            placeholder="13-digit GLN issued by GS1"
            inputmode="numeric"
            required
          />
        </div>
        <%= case site_activity_choices(@operating_models) do %>
          <% [] -> %>
            <p class="mb-4 text-xs text-red-700">
              No site activities are available for this organization's operating models.
            </p>
          <% [only] -> %>
            <div class="mb-4">
              <.activity_card
                type="radio"
                name="site[activity_choice]"
                value={only.key}
                label={only.label}
                description={only.description}
                icon={only.icon}
                selected
                compact
              />
            </div>
          <% choices -> %>
            <fieldset class="mb-4">
              <legend class="mb-2 text-sm font-medium text-thamani-forest">
                What happens at this location?<span class="text-error">&nbsp;*</span>
              </legend>
              <div class="grid grid-cols-1 gap-2">
                <.activity_card
                  :for={choice <- choices}
                  type="radio"
                  name="site[activity_choice]"
                  value={choice.key}
                  label={choice.label}
                  description={choice.description}
                  icon={choice.icon}
                  selected={activity_choice_selected?(@form, choice)}
                  compact
                />
              </div>
              <p :for={error <- @form[:activities].errors} class="mt-2 text-xs text-red-700">
                {translate_error(error)}
              </p>
            </fieldset>
        <% end %>
        <.td_textarea
          id="site-address"
          field={@form[:address]}
          label="Address"
          rows="2"
          required
        />
      <% end %>
    </form>
    """
  end

  defp site_modal_cancel(back_path) do
    if back_path in [~p"/org/dashboard", ~p"/onboarding"] do
      JS.navigate(back_path)
    else
      JS.patch(back_path)
    end
  end

  def render(assigns) do
    if assigns.live_action == :new and assigns.back_path == ~p"/onboarding" do
      render_onboarding(assigns)
    else
      render_index(assigns)
    end
  end

  defp render_onboarding(assigns) do
    ~H"""
    <.onboarding_task_shell
      flash={@flash}
      current_scope={@current_scope}
      icon="hero-building-office-2"
      title="Manage your branches"
      description="Register another location once you're ready to operate from more than one."
      progress_current={elem(@onboarding_progress, 0)}
      progress_total={elem(@onboarding_progress, 1)}
    >
      <:right>
        <div class="flex items-start justify-between gap-5">
          <div>
            <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">Branches</h2>
            <p class="mt-2 text-sm leading-6 text-thamani-pewter">
              Locations registered for this organization so far.
            </p>
          </div>
          <button
            id="onboarding-open-site"
            type="button"
            phx-click="open_onboarding_site"
            class="inline-flex min-h-11 shrink-0 items-center justify-center rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md"
          >
            <.icon name="hero-plus" class="mr-2 size-4" /> Add a branch
          </button>
        </div>

        <div
          :if={@sites == []}
          id="onboarding-sites-empty"
          class="mt-8 flex min-h-52 flex-col items-center justify-center rounded-2xl border border-dashed border-[var(--thamani-stone)] bg-transparent px-6 text-center"
        >
          <span class="flex size-12 items-center justify-center rounded-2xl bg-td-surface text-[var(--thamani-forest)] shadow-sm ring-1 ring-black/[0.04]">
            <.icon name="hero-building-office-2" class="size-6" />
          </span>
          <h3 class="mt-4 text-base font-semibold text-thamani-forest">No branches yet</h3>
          <p class="mt-1 max-w-xs text-sm leading-6 text-thamani-pewter">
            Your primary location is already set up — add another when you're ready.
          </p>
        </div>

        <div :if={@sites != []} id="onboarding-sites-list" class="mt-8">
          <h3 class="mb-3 text-sm font-semibold text-thamani-forest">
            Branches ({length(@sites)})
          </h3>

          <div class="overflow-hidden rounded-2xl border border-[var(--thamani-stone)]">
            <div class="grid grid-cols-[1fr_auto_auto] gap-4 bg-[color-mix(in_srgb,var(--thamani-stone)_35%,white)] px-4 py-2.5 text-xs font-medium text-thamani-pewter">
              <span>Name</span>
              <span class="w-40">Activities</span>
              <span class="w-20 text-right">Status</span>
            </div>

            <div class="divide-y divide-[var(--thamani-stone)]">
              <div
                :for={site <- @sites}
                id={"onboarding-site-#{site.id}"}
                class="grid grid-cols-[1fr_auto_auto] items-center gap-4 px-4 py-3"
              >
                <span class="min-w-0 truncate text-sm text-thamani-forest">{site.name}</span>
                <span class="w-40 truncate text-sm text-thamani-pewter">
                  {activity_labels(site)}
                </span>
                <span class="flex w-20 justify-end">
                  <.status_badge status={if site.is_active, do: :active, else: :inactive} />
                </span>
              </div>
            </div>
          </div>
        </div>
      </:right>

      <:footer>
        <div class="flex items-center gap-4">
          <.link
            id="onboarding-site-back"
            navigate={~p"/onboarding"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:text-[var(--thamani-forest)]"
          >
            <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
          </.link>
          <.link
            id="onboarding-site-skip"
            navigate={~p"/onboarding?skip=add_branch"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] underline decoration-[color-mix(in_srgb,var(--thamani-pewter)_45%,transparent)] underline-offset-4 transition-colors hover:text-[var(--thamani-forest)]"
          >
            Skip this step
          </.link>
        </div>
        <button
          id="onboarding-site-continue"
          type="button"
          phx-click="continue_onboarding"
          class="inline-flex min-h-12 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg"
        >
          Continue <.icon name="hero-arrow-right" class="ml-3 size-4" />
        </button>
      </:footer>
    </.onboarding_task_shell>

    <.td_modal
      :if={@show_onboarding_site_form?}
      id="onboarding-site-modal"
      show
      width={600}
      title="Add a branch"
      subtitle="Register another location once you're ready to operate from more than one."
      on_cancel={JS.push("close_onboarding_site")}
    >
      <:body>
        <.site_form
          form={@form}
          gln_check={@gln_check}
          operating_models={@operating_models}
          gs1_glns={@gs1_glns}
          taken_glns={@taken_glns}
          gln_query={@gln_query}
        />
      </:body>
      <:footer>
        <.td_button
          type="button"
          variant="secondary"
          label="Cancel"
          phx-click={JS.push("close_onboarding_site")}
        />
        <.td_button
          type="submit"
          variant="primary"
          label="Save site"
          glyph="check"
          form="site-form"
        />
      </:footer>
    </.td_modal>
    """
  end

  defp render_index(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/sites"}>
      <:search>
        <form phx-change="search" id="search-form" onsubmit="return false">
          <.td_search
            name="search"
            value={@search}
            placeholder="Search by name or address"
            shortcut="⌘K"
            phx-debounce="200"
          />
        </form>
      </:search>
      <.td_list_page title="Sites" subtitle="Search, filter, and manage your sites.">
        <:actions>
          <.td_button variant="primary" label="Add site" glyph="plus" patch={~p"/org/sites/new"} />
        </:actions>
        <:filters>
          <.td_filter_menu
            id="sites"
            field="activities"
            label="Activity"
            value={@filters.activities}
            options={[
              {"", "Any"}
              | Enum.map(activity_options(), fn {label, _desc, value} -> {to_string(value), label} end)
            ]}
          />
          <.td_filter_menu
            id="sites"
            field="status"
            label="Status"
            value={@filters.status}
            options={[{"", "Any"}, {"active", "Active"}, {"inactive", "Inactive"}]}
          />
        </:filters>

        <.td_modal
          :if={@live_action in [:new, :edit]}
          id="site-modal"
          show
          width={600}
          title={if @live_action == :new, do: "Add a site", else: "Edit site"}
          subtitle="Configure the location identity and activities."
          on_cancel={site_modal_cancel(@back_path)}
        >
          <:body>
            <.site_form
              form={@form}
              gln_check={@gln_check}
              operating_models={@operating_models}
              gs1_glns={@gs1_glns}
              taken_glns={@taken_glns}
              gln_query={@gln_query}
            />
          </:body>
          <:footer>
            <.td_button
              type="button"
              variant="secondary"
              label="Cancel"
              phx-click={site_modal_cancel(@back_path)}
            />
            <.td_button
              type="submit"
              variant="primary"
              label="Save site"
              glyph="check"
              form="site-form"
            />
          </:footer>
        </.td_modal>

        <section id="sites" aria-label="Sites" class="space-y-3 sm:hidden">
          <article
            :for={site <- @sites}
            id={"site-card-#{site.id}"}
            class="group overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-surface shadow-[0_1px_3px_rgba(28,58,19,0.08)] transition-all duration-200"
          >
            <div class="p-4">
              <div class="flex items-start gap-3.5">
                <div class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-thamani-canvas text-thamani-forest ring-1 ring-thamani-stone transition-colors duration-200 group-hover:bg-td-accent-tint">
                  <.icon name="hero-building-office-2" class="size-6" />
                </div>
                <div class="min-w-0 flex-1 pt-0.5">
                  <h2 class="truncate text-base font-semibold leading-6 text-thamani-forest">
                    {site.name}
                  </h2>
                  <p class="mt-0.5 text-sm text-thamani-pewter">
                    {activity_labels(site)}
                  </p>
                </div>
                <.status_badge
                  status={if site.is_active, do: :active, else: :inactive}
                  class="shrink-0"
                />
              </div>

              <dl class="mt-4 grid grid-cols-2 border-t border-thamani-stone/80 pt-4">
                <div class="min-w-0 pr-4">
                  <dt class="text-sm text-thamani-pewter">GLN</dt>
                  <dd class="mt-1 truncate text-sm font-medium tabular-nums text-td-ink">
                    {site.gln}
                  </dd>
                </div>
                <div class="min-w-0 border-l border-thamani-stone/80 pl-4">
                  <dt class="text-sm text-thamani-pewter">Address</dt>
                  <dd class="mt-1 line-clamp-2 text-sm font-medium leading-5 text-td-ink">
                    {site.address}
                  </dd>
                </div>
              </dl>
            </div>

            <div class="flex gap-2 border-t border-thamani-stone bg-thamani-canvas/60 p-3">
              <.button
                variant="ghost-edit"
                patch={~p"/org/sites/#{site.id}/edit"}
                class="min-h-10 flex-1 gap-2 px-4 py-2 text-sm"
                id={"btn-edit-site-#{site.id}"}
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>
              <.button
                type="button"
                phx-click="toggle_active"
                phx-value-id={site.id}
                class="min-h-10 flex-1 px-4 py-2 text-sm"
                variant={if site.is_active, do: "destructive", else: "ghost"}
                id={"btn-toggle-site-#{site.id}"}
              >
                {if site.is_active, do: "Deactivate", else: "Reactivate"}
              </.button>
            </div>
          </article>

          <div :if={@sites == []} id="sites-empty">
            <.blank_state
              icon="hero-building-office-2"
              title={
                if @search != "" or active_filter_count(@filters) > 0,
                  do: "No sites match your search or filters",
                  else: "No sites yet"
              }
            >
              {if @search != "" or active_filter_count(@filters) > 0,
                do: "Try a different search term, or clear the applied filters.",
                else: "Sites you add to your organization will appear here."}
            </.blank_state>
          </div>
        </section>

        <div class="hidden sm:block">
          <.table
            id="sites-table"
            rows={@sites}
            row_id={fn site -> "site-row-#{site.id}" end}
            row_click={fn site -> JS.navigate(~p"/org/sites/#{site.id}") end}
          >
            <:col :let={site} label="Name">{site.name}</:col>
            <:col :let={site} label="Activities">{activity_labels(site)}</:col>
            <:col :let={site} label="GLN"><span class="tabular-nums">{site.gln}</span></:col>
            <:col :let={site} label="Address">{site.address}</:col>
            <:col :let={site} label="Status" mobile="aside">
              <.status_badge status={if site.is_active, do: :active, else: :inactive} />
            </:col>
            <:action :let={site}>
              <.button
                variant="ghost-edit"
                patch={~p"/org/sites/#{site.id}/edit"}
                class="min-h-10 gap-2 px-4 py-2 text-sm"
                id={"btn-edit-site-desktop-#{site.id}"}
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>
            </:action>
            <:action :let={site}>
              <.button
                type="button"
                phx-click="toggle_active"
                phx-value-id={site.id}
                class="px-3 py-1.5 text-xs"
                variant={if site.is_active, do: "destructive", else: "ghost"}
                id={"btn-toggle-site-desktop-#{site.id}"}
              >
                {if site.is_active, do: "Deactivate", else: "Reactivate"}
              </.button>
            </:action>
            <:empty_state>
              <.blank_state
                icon="hero-building-office-2"
                title={
                  if @search != "" or active_filter_count(@filters) > 0,
                    do: "No sites match your search or filters",
                    else: "No sites yet"
                }
              >
                {if @search != "" or active_filter_count(@filters) > 0,
                  do: "Try a different search term, or clear the applied filters.",
                  else: "Sites you add to your organization will appear here."}
              </.blank_state>
            </:empty_state>
          </.table>
        </div>

        <.pagination page={@page_info} path={~p"/org/sites"} />
      </.td_list_page>
    </Layouts.org_shell>
    """
  end
end
