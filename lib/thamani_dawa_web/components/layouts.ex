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
            <li><.theme_toggle /></li>
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

  slot :inner_block, required: true

  def lab_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      title="Thamani Dawa"
      section_label="Lab"
      base_path="/lab"
    >
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

  slot :inner_block, required: true

  def pharmacy_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      title="Thamani Dawa"
      section_label="Pharmacy"
      base_path="/pharmacy"
    >
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

  slot :inner_block, required: true

  def org_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      title="Thamani Dawa"
      section_label="Organization"
      base_path="/org"
    >
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  @doc "Renders the authenticated platform shell for tenant-less superadmins."
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""

  slot :inner_block, required: true

  def platform_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
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

  slot :inner_block, required: true

  def distributor_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      title="Thamani Dawa"
      section_label="Distributor"
      base_path="/distributor"
    >
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

  slot :inner_block, required: true

  def manufacturer_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      back={@back}
      back_label={@back_label}
      title="Thamani Dawa"
      section_label="Manufacturer"
      base_path="/manufacturer"
    >
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

    ~H"""
    <div
      id="sidebar-shell"
      class="internal-app flex min-h-screen overflow-x-hidden lg:h-screen lg:overflow-hidden"
      style="background: var(--thamani-paper); font-family: var(--font-thamani-sans-display, sans-serif);"
      phx-hook=".Sidebar"
    >
      <button
        id="sidebar-backdrop"
        type="button"
        aria-label="Close navigation"
        class="fixed inset-0 z-[80] bg-slate-950/35 backdrop-blur-[1px] lg:hidden"
      />
      <%!-- Sidebar --%>
      <aside
        id="sidebar-aside"
        class="fixed inset-y-0 left-0 z-[90] flex w-72 -translate-x-full shrink-0 flex-col border-r transition-[transform,width] duration-200 ease-in-out lg:relative lg:z-50 lg:translate-x-0"
        style="background: var(--thamani-sidenav, #F0EFEA); border-color: var(--thamani-border-nav); width: 288px; padding: 20px 16px;"
        aria-label={"#{@section_label} navigation"}
      >
        <%!-- Brand row --%>
        <div id="sidebar-brand-row" class="mb-5 flex items-center justify-between gap-3">
          <div id="sidebar-brand" class="flex min-w-0 items-center gap-3">
            <a
              id="sidebar-brand-link"
              href={~p"/"}
              class="flex h-14 w-40 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-thamani-frosted bg-white px-3 py-2 shadow-[0_1px_2px_rgba(0,0,0,0.06)] transition-all duration-150 hover:bg-white/90"
              aria-label="Thamani Dawa home"
            >
              <img
                id="sidebar-brand-logo"
                src="/images/logo-transparent.png"
                alt=""
                class="h-full w-full shrink-0 object-contain"
              />
            </a>
            <div
              id="sidebar-brand-text"
              class="hidden flex-col overflow-hidden whitespace-nowrap transition-opacity duration-150"
            >
              <a
                href={~p"/"}
                class="font-semibold text-[17px] leading-tight truncate block"
                style="color: var(--thamani-forest);"
              >
                {@title}
              </a>
            </div>
          </div>
          <button
            id="sidebar-toggle"
            type="button"
            aria-label="Collapse sidebar"
            data-tooltip="Collapse sidebar"
            aria-expanded="true"
            aria-controls="sidebar-aside"
            class="hidden size-11 shrink-0 cursor-pointer items-center justify-center rounded-xl text-thamani-snow shadow-sm transition-all duration-150 hover:-translate-y-px hover:shadow-md active:translate-y-0 active:scale-[0.98] focus:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent/60 focus-visible:ring-offset-2 lg:flex"
            style="background: var(--thamani-forest);"
          >
            <span id="sidebar-toggle-collapse-icon" class="inline-flex" aria-hidden="true">
              <.icon name="hero-arrow-left-end-on-rectangle" class="size-5 shrink-0" />
            </span>
            <span id="sidebar-toggle-expand-icon" class="hidden" aria-hidden="true">
              <.icon name="hero-arrow-right-end-on-rectangle" class="size-5 shrink-0" />
            </span>
          </button>
        </div>

        <%!-- Context picker: switch between organization-wide management and
             a specific site. Picking a site lands the user in its operations. --%>
        <form
          :if={
            (not is_nil(@organization_picker_option) and @site_picker_options != []) or
              length(@site_picker_options) > 1
          }
          id="site-switch-form"
          action={~p"/switch-site"}
          method="post"
          class="relative mb-4 flex flex-col"
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
              class="group flex min-h-12 w-full cursor-pointer items-center justify-between gap-2.5 rounded-xl px-3 py-2 text-left text-thamani-forest transition-[background-color,border-color,box-shadow,transform] hover:-translate-y-px hover:bg-white/70 hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent/40"
              style="background: color-mix(in srgb, var(--thamani-stone) 72%, white); border: 1px solid color-mix(in srgb, var(--thamani-forest) 25%, var(--thamani-border-nav));"
            >
              <span class="flex min-w-0 items-center gap-2.5">
                <span class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-white/70 text-thamani-forest shadow-sm ring-1 ring-thamani-border-nav/70">
                  <.icon name={@current_picker_option.icon} class="size-4" />
                </span>
                <span class="flex min-w-0 flex-col">
                  <span class="truncate text-sm font-semibold leading-5">
                    {@current_picker_option.name}
                  </span>
                  <span class="truncate text-[11px] font-normal leading-4 text-thamani-pewter">
                    {@current_picker_option.subtitle}
                  </span>
                </span>
              </span>
              <.icon
                name="hero-chevron-down"
                class="size-4 shrink-0 text-thamani-forest transition-transform group-hover:translate-y-0.5"
              />
            </button>

            <div
              id="site-switch-dropdown"
              class="absolute left-0 top-full z-50 mt-1.5 hidden w-full rounded-xl border border-thamani-stone bg-white p-1 shadow-xl ff-surface-popover"
            >
              <p
                :if={@organization_picker_option}
                id="site-switch-organization-heading"
                class="px-2.5 pb-1 pt-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-thamani-pewter"
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
                class="mx-2.5 mt-1 border-t border-slate-100 pb-1 pt-2.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-thamani-pewter"
              >
                Sites
              </p>
              <p
                :if={!@organization_picker_option && @site_picker_options != []}
                id="site-switch-sites-heading"
                class="px-2.5 pb-1 pt-1.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-thamani-pewter"
              >
                Your sites
              </p>
              <.site_picker_option :for={option <- @site_picker_options} option={option} />
            </div>
          </div>
        </form>

        <%!-- Nav list lives in its own scroll region so a short viewport
             scrolls the links instead of pushing the footer (account card,
             log out) off screen. --%>
        <div id="sidebar-scroll-frame" class="relative flex min-h-0 flex-1">
          <div
            id="sidebar-scroll"
            class="flex min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain"
          >
            <%!-- Primary navigation --%>
            <nav class="flex flex-col gap-0.5">
              <%= for {{group_label, items}, index} <- Enum.with_index(@nav_groups) do %>
                <div
                  :if={group_label}
                  class={[
                    "sidebar-group-label nav-label px-3 pb-1 text-[11px] font-medium uppercase tracking-wide transition-opacity duration-150",
                    index > 0 && "mt-3 border-t border-thamani-border-nav pt-3"
                  ]}
                  style="color: var(--thamani-subtle);"
                >
                  {group_label}
                </div>
                <%= for {label, icon, path} <- items do %>
                  <% active =
                    if path == @base_path,
                      do: @current_path == @base_path,
                      else: @current_path == path or String.starts_with?(@current_path, path <> "/") %>
                  <.link
                    navigate={path}
                    data-tour-target={path}
                    data-tooltip={label}
                    aria-current={active && "page"}
                    class="flex items-center gap-3 rounded-xl text-[14px] font-medium transition-[background-color,color,scale] whitespace-nowrap active:scale-[0.96]"
                    style={
                      if active,
                        do:
                          "background: var(--thamani-forest); color: var(--thamani-snow); padding: 9px 12px; min-height: 40px;",
                        else: "color: var(--thamani-pewter); padding: 9px 12px; min-height: 40px;"
                    }
                  >
                    <.icon name={icon} class="size-5 shrink-0" />
                    <span id={"nav-label-#{path}"} class="nav-label transition-opacity duration-150">
                      {label}
                    </span>
                    <span
                      :if={Map.get(@nav_badges, path, 0) > 0}
                      class="nav-badge bg-warning ml-auto inline-flex items-center justify-center rounded-full text-[11px] font-semibold leading-none"
                      style="min-width: 20px; height: 20px; padding: 0 6px; background: var(--thamani-lime); color: var(--thamani-forest);"
                    >
                      {Map.get(@nav_badges, path)}
                    </span>
                  </.link>
                <% end %>
              <% end %>
            </nav>
          </div>
        </div>

        <%!-- Account card + utilities --%>
        <div
          id="sidebar-footer"
          class="shrink-0 mt-3 pt-3 flex flex-col gap-2"
          style="border-top: 1px solid var(--thamani-border-nav);"
        >
          <div id="sidebar-account-menu" class="relative">
            <button
              id="sidebar-account-card"
              type="button"
              aria-label="Open account menu"
              data-tooltip={@current_scope.user.name}
              phx-click={JS.toggle(to: "#sidebar-account-dropdown")}
              phx-click-away={JS.hide(to: "#sidebar-account-dropdown")}
              class="flex w-full cursor-pointer items-center gap-2.5 text-left transition-colors hover:bg-white/70"
              style="background: var(--thamani-stone); border: 1px solid var(--thamani-border-nav); border-radius: 14px; padding: 8px 10px;"
            >
              <span
                class="flex size-8 min-w-8 shrink-0 items-center justify-center rounded-full text-[13px] font-semibold"
                style="background: var(--thamani-forest); color: var(--thamani-snow);"
              >
                {String.at(@current_scope.user.name || "U", 0)}
              </span>
              <span
                id="sidebar-profile"
                class="flex min-w-0 flex-1 items-center overflow-hidden whitespace-nowrap transition-opacity duration-150"
              >
                <span class="truncate text-[13px] font-semibold" style="color: #1F2433;">
                  {@current_scope.user.name}
                </span>
              </span>
              <.icon
                name="hero-ellipsis-vertical"
                class="nav-label size-4 shrink-0 text-thamani-pewter"
              />
            </button>
            <div
              id="sidebar-account-dropdown"
              class="absolute bottom-full left-0 z-50 mb-1.5 hidden w-full rounded-xl border border-thamani-stone bg-white p-1.5 shadow-xl ff-surface-popover"
            >
              <.link
                :if={@show_product_tour}
                id="start-product-tour"
                navigate={product_tour_path(@base_path)}
                class="flex items-center gap-2 rounded-lg px-3 py-2.5 text-sm font-medium text-thamani-forest transition-colors hover:bg-thamani-stone/60"
              >
                <.icon name="hero-map" class="size-4 shrink-0" /> Product tour
              </.link>
              <.link
                id="sidebar-logout"
                href={~p"/logout"}
                method="delete"
                class="flex items-center gap-2 rounded-lg px-3 py-2.5 text-sm font-medium text-red-600 transition-colors hover:bg-red-50"
              >
                <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 shrink-0" /> Log out
              </.link>
            </div>
          </div>
        </div>
      </aside>

      <%!-- Main content --%>
      <main
        class="min-w-0 flex-1 overscroll-contain lg:overflow-y-auto"
        style="background: var(--thamani-paper);"
      >
        <header
          id="mobile-app-bar"
          class="sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-thamani-border-nav bg-thamani-snow/95 px-4 backdrop-blur lg:hidden"
        >
          <button
            id="mobile-sidebar-toggle"
            type="button"
            aria-label="Open navigation"
            aria-controls="sidebar-aside"
            aria-expanded="false"
            class="flex size-11 shrink-0 items-center justify-center rounded-lg text-thamani-forest transition-[background-color,scale] hover:bg-thamani-lime active:scale-[0.96] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </header>
        <div class="mx-auto space-y-5 px-4 py-5 sm:px-6 lg:px-8 lg:py-8" style="max-width: 1600px;">
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
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
      export default {
        mounted() {
          const getSidebar = () => document.getElementById("sidebar-aside");
          const getMobileToggle = () => document.getElementById("mobile-sidebar-toggle");

          this.updateScrollAffordance = () => {
            const scroll = document.getElementById("sidebar-scroll");
            const frame = document.getElementById("sidebar-scroll-frame");
            if (!scroll || !frame) return;

            const remaining = scroll.scrollHeight - scroll.clientHeight - scroll.scrollTop;
            frame.classList.toggle("can-scroll-up", scroll.scrollTop > 2);
            frame.classList.toggle("can-scroll-down", remaining > 2);
          };

          this.sidebarScroll = document.getElementById("sidebar-scroll");
          this.sidebarScroll?.addEventListener("scroll", this.updateScrollAffordance, {passive: true});
          this.sidebarResizeObserver = new ResizeObserver(this.updateScrollAffordance);
          if (this.sidebarScroll) this.sidebarResizeObserver.observe(this.sidebarScroll);

          const hideTooltip = () => {
            document.getElementById("sidebar-floating-tooltip")?.remove();
          };

          const showTooltip = (target) => {
            const sidebar = getSidebar();
            const label = target?.dataset.tooltip;
            if (!sidebar?.classList.contains("sidebar-collapsed") || !label) return;

            hideTooltip();
            const rect = target.getBoundingClientRect();
            const tooltip = document.createElement("div");
            tooltip.id = "sidebar-floating-tooltip";
            tooltip.setAttribute("role", "tooltip");
            tooltip.textContent = label;
            tooltip.style.left = `${rect.right + 12}px`;
            tooltip.style.top = `${rect.top + rect.height / 2}px`;
            document.body.appendChild(tooltip);
          };

          const apply = () => {
            const sidebar = getSidebar();
            if (sidebar) {
              const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
              sidebar.classList.toggle("sidebar-collapsed", collapsed);
              if (!collapsed) hideTooltip();
              const toggle = document.getElementById("sidebar-toggle");
              toggle?.setAttribute("aria-expanded", String(!collapsed));
              toggle?.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
              toggle?.setAttribute("data-tooltip", collapsed ? "Expand sidebar" : "Collapse sidebar");
            }
          };

          apply();
          requestAnimationFrame(this.updateScrollAffordance);

          this.handleTooltipOver = (e) => showTooltip(e.target.closest("#sidebar-aside [data-tooltip]"));
          this.handleTooltipOut = (e) => {
            if (e.target.closest("#sidebar-aside [data-tooltip]")) hideTooltip();
          };
          this.handleTooltipFocus = (e) => showTooltip(e.target.closest("#sidebar-aside [data-tooltip]"));
          this.handleTooltipBlur = hideTooltip;

          this.handleGlobalClick = (e) => {
            const toggleBtn = e.target.closest("#sidebar-toggle");
            if (toggleBtn) {
              e.preventDefault();
              e.stopPropagation();
              const current = localStorage.getItem("sidebar-collapsed") === "true";
              const next = !current;
              localStorage.setItem("sidebar-collapsed", String(next));
              apply();
              return;
            }

            const backdrop = e.target.closest("#sidebar-backdrop");
            if (backdrop) {
              this.el.classList.remove("sidebar-mobile-open");
              getMobileToggle()?.setAttribute("aria-expanded", "false");
              return;
            }

            const mobileToggle = e.target.closest("#mobile-sidebar-toggle");
            if (mobileToggle) {
              const open = !this.el.classList.contains("sidebar-mobile-open");
              this.el.classList.toggle("sidebar-mobile-open", open);
              mobileToggle.setAttribute("aria-expanded", String(open));
              return;
            }

            const sidebarLink = e.target.closest("#sidebar-aside a");
            if (sidebarLink) {
              this.el.classList.remove("sidebar-mobile-open");
              getMobileToggle()?.setAttribute("aria-expanded", "false");
            }
          };

          document.addEventListener("click", this.handleGlobalClick);
          document.addEventListener("mouseover", this.handleTooltipOver);
          document.addEventListener("mouseout", this.handleTooltipOut);
          document.addEventListener("focusin", this.handleTooltipFocus);
          document.addEventListener("focusout", this.handleTooltipBlur);
        },
        updated() {
          const sidebar = document.getElementById("sidebar-aside");
          if (sidebar) {
            const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
            sidebar.classList.toggle("sidebar-collapsed", collapsed);
          }
          requestAnimationFrame(this.updateScrollAffordance);
        },
        destroyed() {
          if (this.handleGlobalClick) {
            document.removeEventListener("click", this.handleGlobalClick);
          }
          document.removeEventListener("mouseover", this.handleTooltipOver);
          document.removeEventListener("mouseout", this.handleTooltipOut);
          document.removeEventListener("focusin", this.handleTooltipFocus);
          document.removeEventListener("focusout", this.handleTooltipBlur);
          this.sidebarScroll?.removeEventListener("scroll", this.updateScrollAffordance);
          this.sidebarResizeObserver?.disconnect();
          document.getElementById("sidebar-floating-tooltip")?.remove();
        }
      }
    </script>
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
          distributor_item_groups()

        [{:manufacturer, _items}] ->
          manufacturer_item_groups()

        [{_portal, items}] ->
          [{"Operations", items}]

        ops_groups ->
          Enum.map(ops_groups, fn {portal, items} ->
            {Portals.portal_label(portal), items}
          end)
      end

    labeled_ops ++ management_groups(scope, ops_groups, site)
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

  defp pharmacy_items(multi_site?) do
    [
      {"Dashboard", "hero-squares-2x2", ~p"/pharmacy"},
      {"Quick sale", "hero-bolt", ~p"/pharmacy/quick-sale"},
      {"Prescriptions", "hero-document-text", ~p"/pharmacy/prescriptions"},
      {"Patients", "hero-user-group", ~p"/pharmacy/patients"},
      {"Stock", "hero-cube", ~p"/pharmacy/stock"},
      {"Receive stock", "hero-arrow-down-tray", ~p"/pharmacy/receive-stock"},
      {"Requisitions", "hero-clipboard-document-list", ~p"/pharmacy/requisitions"},
      {"Scan", "hero-qr-code", ~p"/pharmacy/scan"},
      {"Transactions", "hero-banknotes", ~p"/pharmacy/transactions"}
    ]
    |> reject_single_site_requisitions(multi_site?)
  end

  defp lab_items(multi_site?) do
    [
      {"Dashboard", "hero-squares-2x2", ~p"/lab"},
      {"Patients", "hero-user-group", ~p"/lab/patients"},
      {"Orders", "hero-clipboard-document-list", ~p"/lab/orders"},
      {"Tests", "hero-beaker", ~p"/lab/tests"},
      {"Stock", "hero-cube", ~p"/lab/stock"},
      {"Receive stock", "hero-arrow-down-tray", ~p"/lab/receive-stock"},
      {"Requisitions", "hero-clipboard-document-list", ~p"/lab/requisitions"},
      {"Scan", "hero-qr-code", ~p"/lab/scan"},
      {"Transactions", "hero-banknotes", ~p"/lab/transactions"}
    ]
    |> reject_single_site_requisitions(multi_site?)
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
         {"Shipments", "hero-truck", ~p"/manufacturer/shipments"}
       ]},
      {"Compliance",
       [
         {"EPCIS events", "hero-signal", ~p"/manufacturer/epcis"}
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
         {"Sites", "hero-building-office-2", ~p"/org/sites"}
       ]},
      {"Account",
       [
         {"API keys", "hero-key", ~p"/manufacturer/api-keys"},
         {"TNT reporting", "hero-globe-alt", ~p"/manufacturer/epcis"},
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
         {"TNT reporting", "hero-globe-alt", ~p"/distributor/epcis"},
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
         {"Team", "hero-user-group", ~p"/org/team"}
       ]},
      {"Account",
       [
         {"API keys", "hero-key", ~p"/org/api-keys"},
         {"TNT reporting", "hero-globe-alt", ~p"/org/epcis"},
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
      Site.pharmacy?(site) and Site.lab?(site) -> "hero-building-office-2"
      Site.pharmacy?(site) -> "hero-building-storefront"
      Site.lab?(site) -> "hero-beaker"
      true -> "hero-building-office-2"
    end
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
      class={[
        "flex min-h-11 w-full cursor-pointer items-center justify-between gap-2.5 rounded-lg px-2.5 py-2 text-left transition-colors",
        @option.active? && "bg-thamani-forest/10 text-thamani-forest",
        not @option.active? && "text-slate-700 hover:bg-thamani-stone/60 hover:text-thamani-forest"
      ]}
    >
      <span class="flex min-w-0 items-center gap-2.5">
        <span class={[
          "flex size-7 shrink-0 items-center justify-center rounded-md",
          @option.active? && "bg-white/70",
          not @option.active? && "bg-thamani-stone/60 group-hover:bg-white"
        ]}>
          <.icon name={@option.icon} class="size-3.5" />
        </span>
        <span class="flex min-w-0 flex-col">
          <span class="truncate text-[13px] font-semibold leading-4">{@option.name}</span>
          <span class="truncate text-[11px] font-normal leading-4 text-thamani-pewter">
            {@option.subtitle}
          </span>
        </span>
      </span>
      <.icon
        :if={@option.active?}
        name="hero-check"
        class="size-4 shrink-0 text-thamani-forest"
      />
    </button>
    """
  end

  defp site_activity_summary(%Site{activities: activities}) do
    labels =
      Enum.flat_map(activities || [], fn
        :pharmacy -> ["Pharmacy"]
        :laboratory -> ["Lab"]
        :distribution -> ["Distribution"]
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
    <div class="min-h-screen flex items-center justify-center bg-base-200 px-4">
      <div class="card w-full max-w-md bg-base-100 shadow-xl">
        <div class="card-body">
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
        class="fixed inset-0 z-40 cursor-default bg-slate-950/45 backdrop-blur-[1px]"
      ></button>
      <section
        data-tour-card
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        class="fixed z-[100] w-[min(390px,calc(100vw-2rem))] rounded-2xl border border-white/20 bg-thamani-forest p-5 text-white shadow-2xl transition-[top,left] duration-200"
      >
        <span
          data-tour-arrow
          class="absolute left-[-7px] top-1/2 hidden size-3.5 -translate-y-1/2 rotate-45 border-b border-l border-white/20 bg-thamani-forest"
        ></span>
        <div class="flex items-start justify-between gap-4">
          <div>
            <p
              data-tour-progress
              class="text-xs font-semibold uppercase tracking-[0.16em] text-thamani-lime"
            >
            </p>
            <h2 id={"#{@id}-title"} data-tour-title class="mt-2 text-xl font-semibold"></h2>
          </div>
          <button
            type="button"
            data-tour-dismiss
            aria-label="Close product tour"
            class="rounded-lg p-1 text-white/70 transition-colors hover:bg-white/10 hover:text-white"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <p data-tour-description class="mt-3 text-[15px] leading-6 text-white/85"></p>
        <div class="mt-5 flex items-center justify-between gap-3">
          <button
            type="button"
            data-tour-back
            class="rounded-full px-4 py-2 text-sm font-medium text-white/80 transition-colors hover:bg-white/10 disabled:invisible"
          >Back</button>
          <button
            type="button"
            data-tour-dismiss
            class="rounded-full px-3 py-2 text-sm font-medium text-white/70 transition-colors hover:bg-white/10 hover:text-white"
          >Skip tour</button>
          <button
            type="button"
            data-tour-next
            class="rounded-full bg-thamani-lime px-5 py-2 text-sm font-semibold text-thamani-forest transition-all hover:brightness-95 active:scale-[0.98]"
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
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
