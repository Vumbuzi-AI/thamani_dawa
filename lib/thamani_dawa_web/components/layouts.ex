defmodule ThamaniDawaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.CoreComponents
  alias ThamaniDawaWeb.Portals
  alias ThamaniDawaWeb.SiteScoping

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the authenticated app shell: a nav gated by role (Team/Sites for
  admins, Pharmacy for admin+pharmacist, Lab for admin+lab_technician),
  current site name, theme toggle, and logout. Every authenticated LiveView
  wraps its content in this instead of the generic `app/1`.

  ## Examples

      <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.app_shell>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, required: true

  slot :inner_block, required: true

  def app_shell(assigns) do
    ~H"""
    <div class="internal-app min-h-screen">
      <header class="navbar bg-base-200 px-4 sm:px-6 lg:px-8">
        <div class="flex-1 flex items-center gap-4">
          <a href={~p"/"} class="font-semibold">Thamani Dawa</a>
          <span class="text-sm text-base-content/70">{current_site_name(@current_scope)}</span>
        </div>
        <nav class="flex-none">
          <ul class="flex items-center gap-2">
            <li :if={Scope.admin?(@current_scope)}>
              <.link navigate={~p"/org/team"} class="btn btn-ghost btn-sm">Team</.link>
            </li>
            <li :if={Scope.admin?(@current_scope)}>
              <.link navigate={~p"/org/sites"} class="btn btn-ghost btn-sm">Sites</.link>
            </li>
            <li :if={Scope.admin?(@current_scope)}>
              <.link navigate={~p"/org/products"} class="btn btn-ghost btn-sm">Products</.link>
            </li>
            <li :if={Scope.pharmacy_access?(@current_scope)}>
              <.link navigate={~p"/pharmacy"} class="btn btn-ghost btn-sm">Pharmacy</.link>
            </li>
            <li :if={Scope.lab_access?(@current_scope)}>
              <.link navigate={~p"/lab"} class="btn btn-ghost btn-sm">Lab</.link>
            </li>
            <li>
              <.link href={~p"/logout"} method="delete" class="btn btn-ghost btn-sm">Log out</.link>
            </li>
          </ul>
        </nav>
      </header>

      <main class="px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-5xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Renders the authenticated lab shell: a sticky Forest Depths top bar plus a
  collapsible Forest Depths sidebar with quick-links to every lab section.
  Active links are highlighted with a Lime Pulse pill background — no borders.

  ## Examples

      <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab/orders">
        <h1>Content</h1>
      </Layouts.lab_shell>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  def lab_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      crumb={@crumb}
      crumb_parent={@crumb_parent}
      title="Thamani Dawa"
      section_label="Lab"
      base_path="/lab"
    >
      <:tools>{render_slot(@tools)}</:tools>
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  @doc """
  Renders the authenticated pharmacy shell
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  def pharmacy_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      crumb={@crumb}
      crumb_parent={@crumb_parent}
      title="Thamani Dawa"
      section_label="Pharmacy"
      base_path="/pharmacy"
    >
      <:tools>{render_slot(@tools)}</:tools>
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  defp pending_batches_count(scope, portal_type) do
    batches =
      scope.organization_id
      |> Batches.list_pending_batches()
      |> SiteScoping.for_current_site(scope)

    case portal_type do
      :pharmacy ->
        sites_by_id =
          scope.organization_id
          |> ThamaniDawa.Sites.list_sites()
          |> Map.new(&{&1.id, &1})

        Enum.count(batches, fn batch ->
          site = sites_by_id[batch.site_id]
          site && Site.pharmacy?(site)
        end)

      :lab ->
        sites_by_id =
          scope.organization_id
          |> ThamaniDawa.Sites.list_sites()
          |> Map.new(&{&1.id, &1})

        Enum.count(batches, fn batch ->
          site = sites_by_id[batch.site_id]
          site && Site.lab?(site)
        end)

      :all ->
        length(batches)
    end
  end

  @doc """
  Renders the authenticated org shell: a sticky top bar plus a
  collapsible sidebar with quick-links to every org section.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  def org_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      crumb={@crumb}
      crumb_parent={@crumb_parent}
      title="Thamani Dawa"
      section_label="Organization"
      base_path="/org"
    >
      <:tools>{render_slot(@tools)}</:tools>
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  @doc "Renders the authenticated platform shell for tenant-less superadmins."
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""

  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  def platform_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      crumb={@crumb}
      crumb_parent={@crumb_parent}
      title="Thamani Dawa"
      section_label="Platform"
      base_path="/platform"
      show_product_tour={false}
      nav_groups={[
        {nil,
         [
           {"Dashboard", "hero-squares-2x2", ~p"/platform"},
           {"Audit activity", "hero-clipboard-document-list", ~p"/platform/audit"},
           {"Recalls", "hero-exclamation-triangle", ~p"/platform/recalls"}
         ]}
      ]}
    >
      <:tools>{render_slot(@tools)}</:tools>
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  @doc """
  Renders the authenticated distributor shell: the shared sidebar with links to
  the shipment workflow, mobile app users, serialisation billing, and the
  distributor's inventory and trading-partner records.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  def distributor_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      crumb={@crumb}
      crumb_parent={@crumb_parent}
      title="Thamani Dawa"
      section_label="Distributor"
      base_path="/distributor"
    >
      <:tools>{render_slot(@tools)}</:tools>
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  @doc """
  Renders the authenticated manufacturer shell: the shared sidebar with links
  to the manufacturer's product catalogue, serialisation/SSCC generation, and
  EPCIS reporting.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  def manufacturer_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      crumb={@crumb}
      crumb_parent={@crumb_parent}
      title="Thamani Dawa"
      section_label="Manufacturer"
      base_path="/manufacturer"
    >
      <:tools>{render_slot(@tools)}</:tools>
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, required: true
  attr :title, :string, required: true
  attr :section_label, :string, required: true
  attr :base_path, :string, required: true

  attr :nav_groups, :list,
    default: nil,
    doc: """
    optional `{group_label | nil, [{label, icon, path}]}` override — used by
    the platform shell. Every organization sidebar derives its groups from
    the current site's activities × the user's roles instead.
    """

  attr :nav_badges, :map, default: nil
  attr :show_product_tour, :boolean, default: true
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil
  attr :crumb, :string, default: nil
  attr :crumb_parent, :string, default: nil

  slot :tools
  slot :inner_block, required: true

  defp sidebar_shell(assigns) do
    scope = assigns.current_scope
    multi_site? = multi_site?(scope)

    nav_groups = assigns.nav_groups || unified_nav_groups(scope, multi_site?)

    site_picker_options = site_picker_options(scope)

    assigns =
      assigns
      |> assign(:nav_groups, nav_groups)
      |> then(&assign(&1, :back_label, back_label(&1)))
      |> assign(:nav_badges, assigns.nav_badges || unified_nav_badges(scope, nav_groups))
      |> assign(:site_picker_options, site_picker_options)
      |> assign(:organization_picker_option, Enum.find(site_picker_options, &(&1.value == "")))
      |> assign(:site_picker_options, Enum.reject(site_picker_options, &(&1.value == "")))
      |> assign(:current_picker_option, current_picker_option(scope, site_picker_options))
      |> assign(:account_context, account_context(scope))
      |> assign(:org_settings_path, org_settings_path(scope, assigns.base_path))

    ~H"""
    <.td_app_shell
      id="sidebar-shell"
      crumb_root={@current_picker_option && @current_picker_option.name}
      crumb={@crumb || active_nav_label(@nav_groups, @current_path, @base_path) || @section_label}
      crumb_parent={@crumb_parent}
      nav_label={"#{@section_label} navigation"}
      help_path={if(@show_product_tour, do: product_tour_path(@base_path))}
    >
      <:tools :if={@tools != []}>
        {render_slot(@tools)}
      </:tools>
      <:side>
        <%!-- Site switcher (Doop TD SiteSwitcher, brief 4.4): 44px row, 28px
             tile with the context glyph, caret-up-down. Picking a site lands
             the user in its operations; single-context users see it static. --%>
        <form
          :if={
            (not is_nil(@organization_picker_option) and @site_picker_options != []) or
              length(@site_picker_options) > 1
          }
          id="site-switch-form"
          action={~p"/switch-site"}
          method="post"
          class="td-switch-form"
        >
          <input type="hidden" name="_method" value="patch" />
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input type="hidden" name="return_to" value={@current_path} />
          <input
            type="hidden"
            id="site-switch-input"
            name="site_id"
            value={@current_scope.current_site_id || ""}
          />

          <div class="relative">
            <button
              type="button"
              id="site-switch-trigger"
              phx-click={JS.toggle(to: "#site-switch-dropdown")}
              phx-click-away={JS.hide(to: "#site-switch-dropdown")}
              aria-label="Change working context"
              aria-controls="site-switch-dropdown"
              aria-haspopup="menu"
              data-tooltip={@current_picker_option && @current_picker_option.name}
              class="td-switch"
            >
              <.site_switch_face option={@current_picker_option} />
            </button>

            <div id="site-switch-dropdown" class="td-popover td-switch-menu hidden">
              <p
                :if={@organization_picker_option}
                id="site-switch-organization-heading"
                class="td-popover-label"
              >
                Organization
              </p>
              <.site_picker_option
                :if={@organization_picker_option}
                option={@organization_picker_option}
              />
              <p
                :if={@organization_picker_option && @site_picker_options != []}
                id="site-switch-sites-heading"
                class="td-popover-label"
              >
                Sites
              </p>
              <p
                :if={!@organization_picker_option && @site_picker_options != []}
                id="site-switch-sites-heading"
                class="td-popover-label"
              >
                Your sites
              </p>
              <.site_picker_option :for={option <- @site_picker_options} option={option} />
            </div>
          </div>
        </form>
        <div
          :if={
            @current_picker_option &&
              not ((not is_nil(@organization_picker_option) and @site_picker_options != []) or
                     length(@site_picker_options) > 1)
          }
          class="td-switch-form"
        >
          <div
            class="td-switch is-static"
            data-tooltip={@current_picker_option && @current_picker_option.name}
          >
            <.site_switch_face option={@current_picker_option} static />
          </div>
        </div>

        <%!-- Nav list lives in its own scroll region so a short viewport
             scrolls the links instead of pushing the footer (account card,
             log out) off screen. --%>
        <div id="sidebar-scroll-frame" class="relative flex min-h-0 flex-1">
          <div
            id="sidebar-scroll"
            class="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain"
          >
            <nav class="td-nav">
              <%= for {group_label, items} <- @nav_groups do %>
                <div
                  :if={group_label && group_label != "Distributor"}
                  class="sidebar-group-label nav-label td-nav-group-label"
                >
                  {group_label}
                </div>
                <div :if={group_label == "Distributor"} id="distributor-nav-group">
                  <button
                    id="distributor-nav-toggle"
                    type="button"
                    aria-controls="distributor-nav-items"
                    aria-expanded="false"
                    class="sidebar-group-label nav-label td-nav-group-label td-nav-group-toggle"
                  >
                    Distributor <.td_icon name="caret-down" class="td-nav-group-caret" />
                  </button>
                </div>
                <div
                  id={if(group_label == "Distributor", do: "distributor-nav-items")}
                  class={["td-nav", group_label == "Distributor" && "hidden"]}
                >
                  <%= for {label, icon, path} <- items do %>
                    <% active = nav_active?(path, @current_path, @base_path) %>
                    <.td_nav_item
                      label={label}
                      icon={icon}
                      active={active}
                      count={Map.get(@nav_badges, path, 0)}
                      label_id={"nav-label-#{path}"}
                      navigate={path}
                      data-tour-target={path}
                      data-tooltip={label}
                    />
                  <% end %>
                </div>
              <% end %>
            </nav>
          </div>
        </div>

        <%!-- Sidebar bottom (SHELL-ACCOUNT, Doop cgzlu47zzw): just the
             account chip. Its upward menu holds the theme, the product tour
             and log out; the old Dark mode and Product tour rows are gone. --%>
        <div id="sidebar-footer" class="td-sd-foot">
          <.td_account_chip
            name={@current_scope.user.name}
            role={account_role_label(@current_scope, @section_label)}
            seed={@current_scope.user.email}
          >
            <:menu>
              <div class="td-am-hd" role="presentation">
                <.td_orb seed={@current_scope.user.email} size={32} />
                <div>
                  <span class="td-am-name">{@current_scope.user.name}</span>
                  <span class="td-am-role">{account_role_label(@current_scope, @section_label)}</span>
                  <span :if={@account_context} class="td-am-ctx">{@account_context}</span>
                </div>
              </div>
              <.td_menu_item
                id="account-settings"
                role="menuitem"
                label="Account settings"
                icon="user"
                phx-click={
                  JS.hide(to: "#sidebar-account-dropdown")
                  |> ThamaniDawaWeb.CoreComponents.show_modal("account-settings-modal")
                }
              />
              <.td_menu_item
                :if={@org_settings_path}
                id="account-org-settings"
                role="menuitem"
                label="Org settings"
                icon="gear"
                navigate={@org_settings_path}
              />
              <div class="td-am-div" role="separator"></div>
              <.td_menu_item
                :if={@show_product_tour}
                id="account-help-docs"
                role="menuitem"
                label="Help & docs"
                icon="book-open"
                navigate={product_tour_path(@base_path)}
              />
              <.td_menu_item
                :if={@show_product_tour}
                id="start-product-tour"
                role="menuitem"
                label="Product tour"
                icon="signpost"
                navigate={product_tour_path(@base_path)}
              />
              <.td_menu_item
                id="account-mobile-app"
                role="menuitem"
                label="Get the mobile app"
                icon="device-mobile"
                phx-click={
                  JS.hide(to: "#sidebar-account-dropdown")
                  |> ThamaniDawaWeb.CoreComponents.show_modal("mobile-app-modal")
                }
              />
              <button
                type="button"
                id="account-shortcuts"
                class="td-menu-item"
                role="menuitem"
                phx-click={
                  JS.hide(to: "#sidebar-account-dropdown") |> JS.focus(to: "#td-global-search")
                }
              >
                <.td_icon name="keyboard" />
                <span>Keyboard shortcuts</span>
                <kbd class="td-am-kbd">⌘K</kbd>
              </button>
              <div class="td-am-div" role="separator"></div>
              <span class="td-am-label" role="presentation">Appearance</span>
              <div id="account-theme" phx-update="ignore" role="group" aria-label="Appearance">
                <button
                  :for={
                    {pref, label, icon} <- [
                      {"system", "System", "desktop"},
                      {"light", "Light", "sun"},
                      {"dark", "Dark", "moon"}
                    ]
                  }
                  type="button"
                  id={"account-theme-#{pref}"}
                  class="td-menu-item td-am-theme"
                  role="menuitemradio"
                  aria-checked="false"
                  data-phx-theme={pref}
                  phx-click={JS.dispatch("phx:set-theme")}
                >
                  <.td_icon name={icon} />
                  <span>{label}</span>
                  <span class="td-am-check"><.td_icon name="check" /></span>
                </button>
              </div>
              <div class="td-am-div" role="separator"></div>
              <.td_menu_item
                id="sidebar-logout"
                role="menuitem"
                tone="danger"
                label="Log out"
                icon="sign-out"
                phx-click={
                  JS.hide(to: "#sidebar-account-dropdown")
                  |> ThamaniDawaWeb.CoreComponents.show_modal("sidebar-logout-confirm")
                }
              />
            </:menu>
          </.td_account_chip>
          <.live_component
            module={ThamaniDawaWeb.AccountSettingsComponent}
            id="account-settings"
            current_scope={@current_scope}
            role_label={account_role_label(@current_scope, @section_label)}
            context={@account_context}
            return_to={@current_path}
          />
          <.td_modal
            id="sidebar-logout-confirm"
            title="Log out?"
            on_cancel={ThamaniDawaWeb.CoreComponents.hide_modal("sidebar-logout-confirm")}
          >
            <:body>
              <p class="td-note">You will need to sign in again to continue.</p>
            </:body>
            <:footer>
              <.td_button
                type="button"
                variant="secondary"
                label="Cancel"
                phx-click={ThamaniDawaWeb.CoreComponents.hide_modal("sidebar-logout-confirm")}
              />
              <.td_button
                id="sidebar-logout-confirm-link"
                variant="danger-confirm"
                label="Log out"
                href={~p"/logout"}
                method="delete"
              />
            </:footer>
          </.td_modal>
          <.td_modal
            id="mobile-app-modal"
            title="Get the mobile app"
            subtitle="For the team that packs and scans shipments."
            on_cancel={ThamaniDawaWeb.CoreComponents.hide_modal("mobile-app-modal")}
          >
            <:body>
              <div class="td-mobile-app">
                <.td_icon name="qr-code" class="size-10" />
                <div>
                  <p class="td-mobile-app-tt">Scan with the phone camera</p>
                  <p class="td-note">
                    Opens the Thamani Dawa app listing. Mobile users sign in with the PIN you set for them.
                  </p>
                </div>
              </div>
            </:body>
            <:footer>
              <.td_button
                type="button"
                variant="primary"
                label="Done"
                phx-click={ThamaniDawaWeb.CoreComponents.hide_modal("mobile-app-modal")}
              />
            </:footer>
          </.td_modal>
        </div>
      </:side>
      <:content>
        <%!-- Page-level back affordance. Lives outside the page's header card
               on purpose: separation comes from whitespace, not another box. --%>
        <.link
          :if={is_binary(@back)}
          navigate={@back}
          class="group inline-flex items-center gap-2 text-[13px] font-medium transition-colors hover:text-thamani-forest"
          style="color: var(--thamani-pewter);"
        >
          <.icon
            name="hero-arrow-left"
            class="size-3.5 shrink-0 transition-transform duration-150 group-hover:-translate-x-0.5"
          />
          {@back_label}
        </.link>
        {render_slot(@inner_block)}
        <.flash_group flash={@flash} />
      </:content>
    </.td_app_shell>
    """
  end

  # ------------------------------------------------------------------
  # Unified sidebar content. One nav, derived from context: the current
  # site's activities decide which operations panels exist, the user's
  # roles decide which of those panels they can work, and admins layer
  # org management on top. No portal or role picker — the site picker
  # above is the only context switch.
  # ------------------------------------------------------------------

  defp multi_site?(%Scope{organization_id: nil}), do: false

  defp multi_site?(%Scope{organization_id: organization_id}) do
    Sites.multi_site?(organization_id)
  end

  defp unified_nav_groups(%Scope{organization_id: nil}, _multi_site?), do: []

  defp unified_nav_groups(%Scope{} = scope, multi_site?) do
    site = Portals.current_site(scope)
    ops_groups = operations_groups(scope, site, multi_site?)

    labeled_ops =
      case ops_groups do
        [{:distributor, _items}] ->
          [{"Distributor", distributor_items()}]

        [{:manufacturer, _items}] ->
          manufacturer_item_groups()

        [{:lab, _items}] ->
          lab_item_groups(multi_site?)

        [{:pharmacy, _items}] ->
          pharmacy_item_groups(multi_site?)

        [{_portal, items}] ->
          [{"Operations", items}]

        ops_groups ->
          Enum.map(ops_groups, fn {portal, items} ->
            {Portals.portal_label(portal), items}
          end)
      end

    labeled_ops ++ visible_account_groups(scope, ops_groups, site)
  end

  # Management (Account, org settings, TNT) only appears in the unsited
  # admin context. Sited admins still need API keys, so that one item
  # stays in an Account group (APIKEYS-1).
  defp visible_account_groups(%Scope{} = scope, ops_groups, site) do
    case management_groups(scope, ops_groups, site) do
      [] -> sited_admin_account_groups(scope, ops_groups)
      groups -> groups
    end
  end

  defp sited_admin_account_groups(scope, ops_groups) do
    cond do
      not Scope.admin?(scope) ->
        []

      Enum.any?(ops_groups, &match?({:distributor, _}, &1)) ->
        [{"Account", [{"API keys", "hero-key", ~p"/distributor/api-keys"}]}]

      Enum.any?(ops_groups, &match?({:manufacturer, _}, &1)) ->
        [{"Account", [{"API keys", "hero-key", ~p"/manufacturer/api-keys"}]}]

      true ->
        []
    end
  end

  # Operations panels, in stable display order. Each appears when the
  # context offers it AND the user's roles grant it.
  defp operations_groups(%Scope{} = scope, site, multi_site?) do
    []
    |> put_ops_group(:pharmacy, ops_visible?(scope, :pharmacy, site), pharmacy_items(multi_site?))
    |> put_ops_group(:lab, ops_visible?(scope, :lab, site), lab_items(multi_site?))
    |> put_ops_group(
      :distributor,
      ops_visible?(scope, :distributor, site),
      distributor_items()
    )
    |> put_ops_group(
      :manufacturer,
      ops_visible?(scope, :manufacturer, site),
      manufacturer_items()
    )
    |> put_ops_group(:org, org_ops_visible?(scope, site), org_items(multi_site?))
  end

  defp put_ops_group(groups, _portal, false, _items), do: groups
  defp put_ops_group(groups, portal, true, items), do: groups ++ [{portal, items}]

  defp ops_visible?(scope, :distributor, site) do
    Portals.portal_role?(scope, :distributor) and Portals.distributor_organization?(scope) and
      in_context?(scope, :distributor, site)
  end

  defp ops_visible?(scope, :manufacturer, site) do
    Portals.portal_role?(scope, :manufacturer) and Portals.manufacturer_organization?(scope) and
      in_context?(scope, :manufacturer, site)
  end

  defp ops_visible?(scope, portal, site) do
    Portals.portal_role?(scope, portal) and in_context?(scope, portal, site)
  end

  # No site picked: staff fall back to their role grants (they may not have
  # been assigned a site yet), while an admin is in the org context whose
  # operations come from the org group instead.
  defp in_context?(%Scope{} = scope, _portal, nil), do: not Scope.admin?(scope)

  defp in_context?(_scope, portal, site), do: Portals.site_offers_portal?(site, portal)

  defp org_ops_visible?(%Scope{} = scope, site), do: Scope.admin?(scope) and is_nil(site)

  # Doop shell Pls-onxlMw (brief 4.1): Lab / Inventory / Payments groups with
  # Phosphor icons. Pharmacy uses the same groups and adds Quick sale and
  # Prescriptions after Dashboard.
  defp pharmacy_items(multi_site?) do
    Enum.flat_map(pharmacy_item_groups(multi_site?), fn {_label, items} -> items end)
  end

  defp pharmacy_item_groups(multi_site?) do
    [
      {"Pharmacy",
       [
         {"Dashboard", "squares-four", ~p"/pharmacy"},
         {"Quick sale", "lightning", ~p"/pharmacy/quick-sale"},
         {"Prescriptions", "prescription", ~p"/pharmacy/prescriptions"},
         {"Patients", "users", ~p"/pharmacy/patients"}
       ]},
      {"Inventory",
       [
         {"Stock", "package", ~p"/pharmacy/stock"},
         {"Receive stock", "tray-arrow-down", ~p"/pharmacy/receive-stock"},
         {"Requisitions", "clipboard-text", ~p"/pharmacy/requisitions"},
         {"Scan", "barcode", ~p"/pharmacy/scan"}
       ]
       |> reject_single_site_requisitions(multi_site?)},
      {"Payments", [{"Transactions", "money", ~p"/pharmacy/transactions"}]}
    ]
  end

  defp lab_items(multi_site?) do
    Enum.flat_map(lab_item_groups(multi_site?), fn {_label, items} -> items end)
  end

  defp lab_item_groups(multi_site?) do
    [
      {"Lab",
       [
         {"Dashboard", "squares-four", ~p"/lab"},
         {"Orders", "flask", ~p"/lab/orders"},
         {"Patients", "users", ~p"/lab/patients"},
         {"Tests", "test-tube", ~p"/lab/tests"}
       ]},
      {"Inventory",
       [
         {"Stock", "package", ~p"/lab/stock"},
         {"Receive stock", "tray-arrow-down", ~p"/lab/receive-stock"},
         {"Requisitions", "clipboard-text", ~p"/lab/requisitions"},
         {"Scan", "barcode", ~p"/lab/scan"}
       ]
       |> reject_single_site_requisitions(multi_site?)},
      {"Payments", [{"Transactions", "money", ~p"/lab/transactions"}]}
    ]
  end

  defp distributor_items do
    Enum.flat_map(distributor_item_groups(), fn {_label, items} -> items end)
  end

  defp distributor_item_groups do
    [
      {"Overview",
       [
         {"Dashboard", "hero-squares-2x2", ~p"/distributor"}
       ]},
      {"Inventory",
       [
         {"Receiving", "hero-arrow-down-tray", ~p"/distributor/receiving"},
         {"Inventory", "hero-archive-box", ~p"/distributor/products"}
       ]},
      {"Sales & distribution",
       [
         {"Shipments", "hero-truck", ~p"/distributor/shipments"},
         {"Customers", "hero-user-group", ~p"/distributor/customers"},
         {"Returns", "hero-arrow-uturn-left", ~p"/distributor/returns"}
       ]}
    ]
  end

  defp manufacturer_items do
    Enum.flat_map(manufacturer_item_groups(), fn {_label, items} -> items end)
  end

  defp manufacturer_item_groups do
    [
      {"Overview",
       [
         {"Dashboard", "hero-squares-2x2", ~p"/manufacturer"}
       ]},
      {"Products",
       [
         {"Products", "hero-archive-box", ~p"/manufacturer/products"},
         {"Inventory", "hero-cube", ~p"/manufacturer/inventory"},
         {"Shipments", "hero-truck", ~p"/manufacturer/shipments"},
         {"Aggregation", "hero-squares-plus", ~p"/manufacturer/aggregations"},
         {"Mobile users", "device-mobile-camera", ~p"/manufacturer/mobile-users"}
       ]},
      {"Compliance",
       [
         {"TNT reporting", "broadcast", ~p"/manufacturer/epcis"}
       ]}
    ]
  end

  defp org_items(multi_site?) do
    [
      {"Dashboard", "hero-squares-2x2", ~p"/org/dashboard"},
      {"Requisitions", "hero-clipboard-document-list", ~p"/org/requisitions"},
      {"Transactions", "hero-banknotes", ~p"/org/earnings"}
    ]
    |> reject_single_site_requisitions(multi_site?)
  end

  defp reject_single_site_requisitions(items, true), do: items

  defp reject_single_site_requisitions(items, false) do
    Enum.reject(items, fn {_label, _icon, path} -> String.ends_with?(path, "/requisitions") end)
  end

  # Org management (sites, products, team, billing, reporting) is
  # org-wide, not this-site's business — only offered when the admin is in
  # the "Manage organization" context (no specific site picked), not while
  # drilled into one site's operations.
  defp management_groups(%Scope{} = scope, ops_groups, site) do
    cond do
      not Scope.admin?(scope) or not is_nil(site) -> []
      Enum.any?(ops_groups, &match?({:distributor, _}, &1)) -> distributor_admin_groups()
      Enum.any?(ops_groups, &match?({:manufacturer, _}, &1)) -> manufacturer_admin_groups()
      true -> org_management_groups()
    end
  end

  defp manufacturer_admin_groups do
    [
      {"Reference data",
       [
         {"Mobile users", "device-mobile-camera", ~p"/manufacturer/mobile-users"},
         {"Sites", "hero-building-office-2", ~p"/org/sites"}
       ]},
      {"Account",
       [
         {"API keys", "hero-key", ~p"/manufacturer/api-keys"},
         {"TNT reporting", "broadcast", ~p"/manufacturer/epcis"},
         {"Org settings", "hero-cog-6-tooth", ~p"/manufacturer/settings"}
       ]}
    ]
  end

  defp distributor_admin_groups do
    [
      {"Reference data",
       [
         {"Mobile users", "hero-device-phone-mobile", ~p"/distributor/mobile-users"},
         {"Sites", "hero-building-office-2", ~p"/org/sites"}
       ]},
      {"Account",
       [
         {"Billing", "hero-credit-card", ~p"/distributor/billing"},
         {"API keys", "hero-key", ~p"/distributor/api-keys"},
         {"TNT reporting", "broadcast", ~p"/distributor/epcis"},
         {"Org settings", "hero-cog-6-tooth", ~p"/distributor/settings"}
       ]}
    ]
  end

  defp org_management_groups do
    [
      {"Organization",
       [
         {"Sites", "hero-building-office-2", ~p"/org/sites"},
         {"Products", "hero-cube", ~p"/org/products"},
         {"Suppliers", "hero-truck", ~p"/org/suppliers"},
         {"Team", "hero-user-group", ~p"/org/team"},
         {"Mobile users", "hero-device-phone-mobile", ~p"/org/mobile-users"}
       ]},
      {"Account",
       [
         {"API keys", "hero-key", ~p"/org/api-keys"},
         {"TNT reporting", "broadcast", ~p"/org/epcis"},
         {"Org settings", "hero-cog-6-tooth", ~p"/org/settings"}
       ]}
    ]
  end

  defp unified_nav_badges(%Scope{} = scope, nav_groups) do
    paths = nav_paths(nav_groups)

    %{}
    |> maybe_badge(paths, ~p"/pharmacy/receive-stock", fn ->
      pending_batches_count(scope, :pharmacy)
    end)
    |> maybe_badge(paths, ~p"/lab/receive-stock", fn ->
      pending_batches_count(scope, :lab)
    end)
    |> maybe_badge(paths, ~p"/org/requisitions", fn ->
      ThamaniDawa.Requisitions.count_pending(scope.organization_id)
    end)
  end

  defp nav_paths(nav_groups) do
    nav_groups
    |> Enum.flat_map(fn {_label, items} ->
      Enum.map(items, fn {_label, _icon, path} -> path end)
    end)
  end

  defp maybe_badge(badges, paths, path, fun) do
    if path in paths, do: Map.put(badges, path, fun.()), else: badges
  end

  # Site picker options: the organization (admins only) plus the sites
  # this scope is allowed to be stationed at — assigned sites whose
  # activities their roles support.
  defp site_picker_options(%Scope{organization_id: nil}), do: []

  defp site_picker_options(%Scope{} = scope) do
    org_option(scope) ++ site_options(scope)
  end

  defp org_option(%Scope{} = scope) do
    if Scope.admin?(scope) do
      [
        %{
          id: "site-switch-org",
          name: "All sites",
          subtitle: Organizations.get_organization!(scope.organization_id).name,
          icon: "hero-squares-2x2",
          active?: is_nil(scope.current_site_id),
          value: ""
        }
      ]
    else
      []
    end
  end

  # An admin administers every site in the org, not just whichever ones
  # they happen to have a `UserSite` row for (that assignment model is for
  # operational staff). Staff see their assigned sites, filtered down to
  # the ones their roles can actually work — nobody is offered a site
  # they'd land in with an empty nav.
  defp site_options(%Scope{} = scope) do
    sites =
      if Scope.admin?(scope) do
        Sites.list_sites(scope.organization_id)
      else
        scope.user.sites
      end

    sites
    |> Enum.filter(&Portals.site_usable?(scope, &1))
    |> Enum.map(fn site ->
      %{
        id: "site-switch-option-#{site.id}",
        name: site.name,
        subtitle: site_activity_summary(site),
        icon: site_context_icon(site),
        active?: site.id == scope.current_site_id,
        value: to_string(site.id)
      }
    end)
  end

  defp site_context_icon(site) do
    cond do
      Site.distribution?(site) -> "hero-archive-box"
      Site.manufacturer?(site) -> "hero-cog-8-tooth"
      Site.pharmacy?(site) and Site.lab?(site) -> "hero-building-office-2"
      Site.pharmacy?(site) -> "hero-building-storefront"
      Site.lab?(site) -> "hero-beaker"
      true -> "hero-building-office-2"
    end
  end

  attr :option, :map, required: true
  attr :static, :boolean, default: false

  defp site_switch_face(assigns) do
    ~H"""
    <span class="td-ss-tile"><.td_icon name={CoreComponents.phosphor_name(@option.icon)} /></span>
    <span class="td-ss-tx nav-label">
      <span class="td-ss-n">{@option.name}</span>
      <span class="td-ss-s">{@option.subtitle}</span>
    </span>
    <span :if={!@static} class="td-ss-cv nav-label"><.td_icon name="caret-up-down" /></span>
    """
  end

  # Active nav item: exact match for the section root, prefix match below it.
  # Stock stays active on the stock-take and disposal screens it launches.
  defp nav_active?(path, current_path, base_path) do
    cond do
      path == base_path ->
        current_path == base_path

      current_path == path or String.starts_with?(current_path, path <> "/") ->
        true

      String.ends_with?(path, "/stock") ->
        prefix = String.replace_suffix(path, "/stock", "")

        Enum.any?(
          ["/stock-takes", "/disposals"],
          &String.starts_with?(current_path, prefix <> &1)
        )

      true ->
        false
    end
  end

  defp account_role_label(_scope, section_label), do: section_label

  # "Org · Site" under the name in the account menu.
  defp account_context(%Scope{organization_id: nil}), do: nil

  defp account_context(%Scope{} = scope) do
    org = Organizations.get_organization!(scope.organization_id).name

    case scope.current_site_id do
      nil -> org
      _ -> "#{org} · #{current_site_name(scope)}"
    end
  rescue
    Ecto.NoResultsError -> nil
  end

  defp org_settings_path(%Scope{organization_id: nil}, _base_path), do: nil

  defp org_settings_path(%Scope{} = scope, base_path) do
    cond do
      not Scope.admin?(scope) -> nil
      base_path in ["/distributor", "/manufacturer"] -> base_path <> "/settings"
      base_path == "/org" -> "/org/settings"
      true -> nil
    end
  end

  defp active_nav_label(nav_groups, current_path, base_path) do
    Enum.find_value(nav_groups, fn {_group, items} ->
      Enum.find_value(items, fn {label, _icon, path} ->
        if nav_active?(path, current_path, base_path), do: label
      end)
    end)
  end

  attr :option, :map, required: true

  defp site_picker_option(assigns) do
    ~H"""
    <button
      id={@option.id}
      type="button"
      onclick={
        "document.getElementById('site-switch-input').value = '" <>
          @option.value <>
          "'; document.getElementById('site-switch-form').requestSubmit();"
      }
      class={["td-ss-option", @option.active? && "is-active"]}
    >
      <span class="td-ss-tile"><.td_icon name={CoreComponents.phosphor_name(@option.icon)} /></span>
      <span class="td-ss-tx">
        <span class="td-ss-n">{@option.name}</span>
        <span class="td-ss-s">{@option.subtitle}</span>
      </span>
      <.td_icon :if={@option.active?} name="check" class="size-4 td-ss-check" />
    </button>
    """
  end

  defp site_activity_summary(%Site{activities: activities}) do
    labels =
      Enum.flat_map(activities || [], fn
        :pharmacy -> ["Pharmacy"]
        :laboratory -> ["Lab"]
        :distribution -> ["Distributor"]
        :manufacturing -> ["Manufacturer"]
        _ -> []
      end)

    case labels do
      [] -> "Site"
      [only] -> only
      many -> Enum.join(many, " + ")
    end
  end

  defp current_picker_option(%Scope{} = scope, options) do
    Enum.find(options, & &1.active?) ||
      %{
        name: current_site_name(scope),
        subtitle: "",
        icon: "hero-building-office-2"
      }
  end

  defp current_site_name(%Scope{current_site_id: nil}), do: "Organization"

  defp current_site_name(%Scope{current_site_id: site_id, organization_id: organization_id}) do
    ThamaniDawa.Sites.get_site!(organization_id, site_id).name
  rescue
    Ecto.NoResultsError -> "Unknown site"
  end

  @doc """
  Renders a minimal, unauthenticated centered-card layout — used by signup,
  accept-invite, and login, which have no nav to show.

  ## Examples

      <Layouts.unauthenticated flash={@flash}>
        <h1>Log in</h1>
      </Layouts.unauthenticated>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def unauthenticated(assigns) do
    ~H"""
    <div
      class="flex min-h-screen items-center justify-center px-4"
      style="background: var(--color-td-canvas); font-family: Inter, sans-serif;"
    >
      <div
        class="w-full max-w-md rounded-xl border p-6"
        style="background: var(--color-td-surface); border-color: var(--color-td-hairline);"
      >
        <div>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :navigation, :boolean,
    default: true,
    doc: "whether to render the standard application navigation"

  attr :inner_content, :any, default: nil
  slot :inner_block, required: false

  def app(assigns) do
    ~H"""
    <.page_navbar :if={@navigation} current_scope={@current_scope} />

    <main class="w-full">
      {@inner_content || render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc false
  attr :inner_content, :any, default: nil
  slot :inner_block, required: false

  def landing(assigns) do
    ~H"""
    {@inner_content || render_slot(@inner_block)}
    <.site_footer />
    """
  end

  @doc false
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :inner_content, :any, default: nil
  slot :inner_block, required: false

  def contact(assigns) do
    ~H"""
    <div class="contact-page">
      <.marketing_nav />
      <main class="w-full">
        {@inner_content || render_slot(@inner_block)}
      </main>
      <.site_footer />
      <.flash_group flash={@flash} />
    </div>
    """
  end

  defp marketing_nav(assigns) do
    ~H"""
    <header class="site-header">
      <div class="nav-shell">
        <a class="brand" href="/" aria-label="Thamani Dawa home">
          <img src="/images/logo-transparent.png" alt="" width="56" height="56" />
        </a>
        <nav class="desktop-nav" aria-label="Primary navigation">
          <a href="/#features">Features</a>
          <a href="/#results">Why Thamani</a>
          <a href="/contact" aria-current="page">Contact</a>
        </nav>
        <div class="desktop-actions">
          <a class="button button-small button-light login-cta" href="/login">Log in</a>
          <a class="button button-small button-dark" href="/signup">Get started</a>
        </div>
        <button
          class="menu-button"
          type="button"
          aria-label="Open menu"
          aria-controls="mobile-menu"
          aria-expanded="false"
        >
          <span></span><span></span><span></span>
        </button>
      </div>
    </header>
    <dialog class="mobile-menu" id="mobile-menu" aria-label="Site menu">
      <div class="menu-top">
        <a class="brand" href="/" aria-label="Thamani Dawa home">
          <img src="/images/logo-transparent.png" alt="" width="56" height="56" />
        </a>
        <button class="menu-close" type="button" aria-label="Close menu"><span></span><span></span></button>
      </div>
      <div class="menu-groups">
        <div>
          <p>Product</p><a href="/#features">Features</a><a href="/login">Log in</a><a href="/signup">Create account</a>
        </div>
        <div>
          <p>Company</p><a href="/#results">Why Thamani</a><a href="/contact">Contact</a>
        </div>
        <div>
          <p>Legal</p><a href="/privacy">Privacy policy</a><a href="/terms">Terms of service</a>
        </div>
      </div>
    </dialog>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc "Renders a reusable guided tour overlay for a staff portal."
  attr :id, :string, required: true
  attr :tour_key, :string, required: true
  attr :auto_start, :boolean, default: false
  attr :steps, :list, required: true

  def product_tour(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="ProductTour"
      phx-update="ignore"
      data-tour-key={@tour_key}
      data-auto-start={to_string(@auto_start)}
      data-tour-steps={Jason.encode!(@steps)}
      class="hidden"
    >
      <button
        type="button"
        data-tour-dismiss
        aria-label="Close product tour"
        class="fixed inset-0 z-40 cursor-default bg-td-ink/45 backdrop-blur-[1px]"
      ></button>
      <section
        data-tour-card
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        class="fixed z-[100] w-[min(390px,calc(100vw-2rem))] rounded-2xl border border-white/20 bg-thamani-forest p-5 text-td-on-accent shadow-2xl transition-[top,left] duration-200"
      >
        <span
          data-tour-arrow
          class="absolute left-[-7px] top-1/2 hidden size-3.5 -translate-y-1/2 rotate-45 border-b border-l border-white/20 bg-thamani-forest"
        ></span>
        <div class="flex items-start justify-between gap-4">
          <div>
            <p
              data-tour-progress
              class="text-xs font-semibold uppercase tracking-[0.16em] text-td-on-accent"
            >
            </p>
            <h2 id={"#{@id}-title"} data-tour-title class="mt-2 text-xl font-semibold"></h2>
          </div>
          <button
            type="button"
            data-tour-dismiss
            aria-label="Close product tour"
            class="rounded-lg p-1 text-white/70 transition-colors hover:bg-td-surface/10 hover:text-white"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <p data-tour-description class="mt-3 text-[15px] leading-6 text-white/85"></p>
        <div class="mt-5 flex items-center justify-between gap-3">
          <button
            type="button"
            data-tour-back
            class="rounded-full px-4 py-2 text-sm font-medium text-white/80 transition-colors hover:bg-td-surface/10 disabled:invisible"
          >Back</button>
          <button
            type="button"
            data-tour-dismiss
            class="rounded-full px-3 py-2 text-sm font-medium text-white/70 transition-colors hover:bg-td-surface/10 hover:text-white"
          >Skip tour</button>
          <button
            type="button"
            data-tour-next
            class="rounded-full bg-td-accent-tint px-5 py-2 text-sm font-semibold text-thamani-forest transition-all hover:brightness-95 active:scale-[0.98]"
          >Next</button>
        </div>
      </section>
    </div>
    """
  end

  # Label for the page-level back link. An explicit `back_label` always wins;
  # otherwise the destination is matched against the nav items so `/org/sites`
  # reads "Back to Sites" without every page restating it.
  defp back_label(%{back_label: label}) when is_binary(label), do: label

  # Destination matched against the sidebar's nav items so `/org/sites`
  # reads "Back to Sites" without every page restating it.
  defp back_label(%{back: back, nav_groups: nav_groups}) when is_binary(back) do
    item =
      nav_groups
      |> Enum.flat_map(fn {_label, items} -> items end)
      |> Enum.find(fn {_label, _icon, path} -> path == back end)

    case item do
      {label, _icon, _path} -> "Back to #{label}"
      nil -> "Back"
    end
  end

  defp back_label(_assigns), do: nil

  defp product_tour_path("/org"), do: ~p"/org/dashboard?tour=1"
  defp product_tour_path("/pharmacy"), do: ~p"/pharmacy?tour=1"
  defp product_tour_path("/lab"), do: ~p"/lab?tour=1"
  defp product_tour_path("/distributor"), do: ~p"/distributor?tour=1"
  defp product_tour_path("/manufacturer"), do: ~p"/manufacturer?tour=1"

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="td-theme">
      <button
        type="button"
        class="td-icon-btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="desktop" class="size-4" />
      </button>
      <button
        type="button"
        class="td-icon-btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="sun" class="size-4" />
      </button>
      <button
        type="button"
        class="td-icon-btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="moon" class="size-4" />
      </button>
    </div>
    """
  end
end
