defmodule ThamaniDawaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Sites.Site
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
    assigns =
      assign(assigns, :nav_badges, %{
        ~p"/lab/receive-stock" => pending_batches_count(assigns.current_scope, :lab)
      })

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
      nav_badges={@nav_badges}
      nav_items={[
        {"Dashboard", "hero-squares-2x2", ~p"/lab"},
        {"Patients", "hero-user-group", ~p"/lab/patients"},
        {"Orders", "hero-clipboard-document-list", ~p"/lab/orders"},
        {"Tests", "hero-beaker", ~p"/lab/tests"},
        {"Stock", "hero-cube", ~p"/lab/stock"},
        {"Receive stock", "hero-arrow-down-tray", ~p"/lab/receive-stock"},
        {"Scan", "hero-qr-code", ~p"/lab/scan"}
      ]}
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
    assigns =
      assign(assigns, :nav_badges, %{
        ~p"/pharmacy/receive-stock" => pending_batches_count(assigns.current_scope, :pharmacy)
      })

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
      nav_badges={@nav_badges}
      nav_items={[
        {"Dashboard", "hero-squares-2x2", ~p"/pharmacy"},
        {"Patients", "hero-user-group", ~p"/pharmacy/patients"},
        {"Prescriptions", "hero-document-text", ~p"/pharmacy/prescriptions"},
        {"Stock", "hero-cube", ~p"/pharmacy/stock"},
        {"Receive stock", "hero-arrow-down-tray", ~p"/pharmacy/receive-stock"},
        {"Stock take", "hero-clipboard-document-check", ~p"/pharmacy/stock-takes"},
        {"Scan", "hero-qr-code", ~p"/pharmacy/scan"}
      ]}
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
      nav_items={[
        {"Dashboard", "hero-squares-2x2", ~p"/org/dashboard"},
        {"Sites", "hero-building-office-2", ~p"/org/sites"},
        {"Team", "hero-user-group", ~p"/org/team"},
        {"Products", "hero-cube", ~p"/org/products"},
        {"Suppliers", "hero-truck", ~p"/org/suppliers"}
      ]}
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
  attr :nav_items, :list, required: true
  attr :nav_badges, :map, default: %{}
  attr :back, :any, default: nil
  attr :back_label, :string, default: nil

  slot :inner_block, required: true

  defp sidebar_shell(assigns) do
    assigns = assign(assigns, :back_label, back_label(assigns))

    ~H"""
    <div
      id="sidebar-shell"
      class="internal-app flex min-h-screen overflow-x-hidden lg:h-screen lg:overflow-hidden"
      style="background: var(--surface-1); font-family: var(--font-thamani-sans, sans-serif);"
      phx-hook=".Sidebar"
    >
      <button
        id="sidebar-backdrop"
        type="button"
        aria-label="Close navigation"
        class="fixed inset-0 z-40 hidden bg-slate-950/35 backdrop-blur-[1px] lg:hidden"
      />
      <%!-- Sidebar --%>
      <aside
        id="sidebar-aside"
        class="fixed inset-y-0 left-0 z-50 flex w-72 -translate-x-full shrink-0 flex-col border-r transition-[transform,width] duration-200 ease-in-out lg:relative lg:translate-x-0"
        style="background: var(--thamani-sidenav, #EFEFF0); border-color: var(--thamani-border-nav); width: 288px; padding: 24px 20px;"
        aria-label={"#{@section_label} navigation"}
      >
        <%!-- Brand row --%>
        <div id="sidebar-brand-row" class="flex items-center gap-3 mb-6">
          <a
            href={~p"/"}
            class="flex items-center justify-center shrink-0 rounded-lg overflow-hidden hover:opacity-80 transition-opacity"
          >
            <img
              src="/images/logo.png"
              alt="Thamani Dawa"
              class="w-11 h-11 object-cover"
            />
          </a>
          <div
            id="sidebar-brand-text"
            class="flex flex-col overflow-hidden whitespace-nowrap transition-opacity duration-150"
          >
            <a
              href={~p"/"}
              class="font-semibold text-[17px] leading-tight truncate block"
              style="color: var(--thamani-forest);"
            >
              {@title}
            </a>
            <span class="text-[13px] truncate block" style="color: var(--thamani-pewter);">
              {@section_label}
            </span>
          </div>
        </div>

        <%!-- Primary navigation --%>
        <nav class="flex flex-col gap-1">
          <%= for {label, icon, path} <- @nav_items do %>
            <% active =
              if path == @base_path,
                do: @current_path == @base_path,
                else: @current_path == path or String.starts_with?(@current_path, path <> "/") %>
            <.link
              navigate={path}
              data-tooltip={label}
              aria-current={active && "page"}
              class="flex items-center gap-3 rounded-xl text-[15px] font-medium transition-[background-color,color,scale] whitespace-nowrap active:scale-[0.96]"
              style={
                if active,
                  do:
                    "background: var(--thamani-forest); color: var(--thamani-snow); padding: 12px; min-height: 48px;",
                  else: "color: var(--thamani-pewter); padding: 12px; min-height: 48px;"
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
        </nav>

        <%!-- Cross-portal switch: only combined pharmacy/lab staff currently
             stationed at a combined pharmacy+lab site can hop portals. A
             pharma_lab user sent to a lab-only (or pharmacy-only) site only
             ever sees that one side, matching what the site actually offers. --%>
        <div
          :if={Scope.pharma_lab?(@current_scope) and combined_site?(@current_scope)}
          id="sidebar-portal-switch"
          class="flex flex-col gap-1 mt-4 pt-4"
          style="border-top: 1px solid var(--thamani-border-nav);"
        >
          <span
            id="nav-label-portal-switch-heading"
            class="px-3 text-[11px] font-medium uppercase tracking-wide transition-opacity duration-150"
            style="color: var(--thamani-subtle);"
          >
            Switch portal
          </span>
          <.link
            :if={@base_path != "/pharmacy"}
            id="portal-link-pharmacy"
            navigate={~p"/pharmacy"}
            class="flex items-center gap-3 rounded-xl text-[15px] font-medium transition-[background-color,color,scale] whitespace-nowrap overflow-hidden active:scale-[0.96]"
            style="color: var(--thamani-pewter); padding: 12px; min-height: 48px;"
          >
            <.icon name="hero-building-storefront" class="size-5 shrink-0" />
            <span id="nav-label-/pharmacy" class="transition-opacity duration-150">Pharmacy</span>
          </.link>
          <.link
            :if={@base_path != "/lab"}
            id="portal-link-lab"
            navigate={~p"/lab"}
            class="flex items-center gap-3 rounded-xl text-[15px] font-medium transition-[background-color,color,scale] whitespace-nowrap overflow-hidden active:scale-[0.96]"
            style="color: var(--thamani-pewter); padding: 12px; min-height: 48px;"
          >
            <.icon name="hero-beaker" class="size-5 shrink-0" />
            <span id="nav-label-/lab" class="transition-opacity duration-150">Lab</span>
          </.link>
        </div>

        <%!-- Account card + utilities --%>
        <div
          class="mt-auto pt-4 flex flex-col gap-3"
          style="border-top: 1px solid var(--thamani-border-nav);"
        >
          <%!-- Collapse sidebar toggle --%>
          <button
            id="sidebar-toggle"
            type="button"
            aria-label="Collapse sidebar"
            data-tooltip="Collapse sidebar"
            class="flex items-center gap-3 w-full rounded-xl text-xs font-medium transition-all duration-150 cursor-pointer active:scale-[0.98] focus:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent/40 hover:bg-slate-100/80"
            style="background: var(--thamani-stone); border: 1px solid var(--thamani-border-nav); color: var(--thamani-pewter); padding: 10px 14px; min-height: 42px;"
          >
            <span id="sidebar-toggle-icon" class="inline-flex transition-transform duration-200">
              <.icon name="hero-chevron-left" class="size-4 shrink-0" />
            </span>
            <span class="nav-label text-[13px] font-medium transition-opacity duration-150 text-thamani-pewter truncate">
              Collapse sidebar
            </span>
          </button>
          <form
            :if={length(@current_scope.user.sites) > 1}
            id="site-switch-form"
            action={~p"/switch-site"}
            method="post"
            class="relative flex flex-col gap-1"
          >
            <input type="hidden" name="_method" value="patch" />
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="return_to" value={@current_path} />
            <input
              type="hidden"
              id="site-switch-input"
              name="site_id"
              value={@current_scope.current_site_id}
            />

            <span
              class="px-1 text-[11px] font-medium uppercase tracking-wide"
              style="color: var(--thamani-subtle);"
            >
              Current site
            </span>

            <button
              type="button"
              id="site-switch-trigger"
              phx-click={JS.toggle(to: "#site-switch-dropdown")}
              phx-click-away={JS.hide(to: "#site-switch-dropdown")}
              class="flex items-center justify-between gap-2 w-full rounded-xl px-3 py-2.5 text-sm font-medium text-thamani-forest transition-colors cursor-pointer"
              style="background: var(--thamani-stone); border: 1px solid var(--thamani-border-nav);"
            >
              <div class="flex items-center gap-2 min-w-0 truncate">
                <.icon name="hero-building-office-2" class="size-4 shrink-0 text-thamani-forest/70" />
                <span class="truncate">{current_site_name(@current_scope)}</span>
              </div>
              <.icon name="hero-chevron-down" class="size-4 shrink-0 text-thamani-pewter" />
            </button>

            <div
              id="site-switch-dropdown"
              class="absolute bottom-full left-0 mb-1.5 w-full z-50 hidden rounded-xl bg-white shadow-xl border border-thamani-stone p-1.5 ff-surface-popover"
            >
              <button
                :for={site <- @current_scope.user.sites}
                type="button"
                onclick={"
                  document.getElementById('site-switch-input').value = '#{site.id}';
                  document.getElementById('site-switch-form').requestSubmit();
                "}
                class={[
                  "flex items-center justify-between w-full rounded-lg px-3 py-2 text-xs font-medium text-left transition-colors cursor-pointer",
                  site.id == @current_scope.current_site_id &&
                    "bg-thamani-forest/10 text-thamani-forest font-semibold",
                  site.id != @current_scope.current_site_id &&
                    "text-slate-700 hover:bg-thamani-stone/60 hover:text-thamani-forest"
                ]}
              >
                <div class="flex items-center gap-2 truncate min-w-0">
                  <.icon name="hero-building-office-2" class="size-3.5 shrink-0 opacity-60" />
                  <span class="truncate">{site.name}</span>
                </div>
                <.icon
                  :if={site.id == @current_scope.current_site_id}
                  name="hero-check"
                  class="size-4 shrink-0 text-thamani-forest"
                />
              </button>
            </div>
          </form>

          <div
            id="sidebar-account-card"
            data-tooltip={@current_scope.user.name}
            class="flex items-center gap-3 transition-opacity duration-150"
            style="background: var(--thamani-stone); border: 1px solid var(--thamani-border-nav); border-radius: 16px; padding: 14px 16px;"
          >
            <div
              class="rounded-full flex items-center justify-center shrink-0 aspect-square font-semibold text-[15px]"
              style="width: 44px; height: 44px; min-width: 44px; min-height: 44px; border-radius: 9999px; background: var(--thamani-forest); color: var(--thamani-snow);"
            >
              {String.at(@current_scope.user.name || "U", 0)}
            </div>
            <div
              id="sidebar-profile"
              class="flex flex-col overflow-hidden whitespace-nowrap transition-opacity duration-150"
            >
              <span class="text-[15px] font-semibold truncate" style="color: #1F2433;">
                {@current_scope.user.name}
              </span>
              <span class="text-[13px]" style="color: var(--thamani-pewter);">
                {current_site_name(@current_scope)}
              </span>
            </div>
          </div>

          <.link
            id="sidebar-logout"
            data-tooltip="Log out"
            href={~p"/logout"}
            method="delete"
            class="px-3 py-2 rounded-xl text-sm font-medium transition-[background-color,scale] flex items-center gap-3 group hover:bg-red-50 active:scale-[0.96]"
            style="color: var(--thamani-error);"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 shrink-0" />
            <span id="nav-label-logout" class="nav-label transition-opacity duration-150">
              Log out
            </span>
          </.link>
        </div>
      </aside>

      <%!-- Main content --%>
      <main class="min-w-0 flex-1 lg:overflow-y-auto">
        <header
          id="mobile-app-bar"
          class="sticky top-0 z-30 flex h-16 items-center justify-between border-b border-thamani-border-nav bg-thamani-snow/95 px-4 backdrop-blur lg:hidden"
        >
          <button
            id="mobile-sidebar-toggle"
            type="button"
            aria-label="Open navigation"
            aria-controls="sidebar-aside"
            aria-expanded="false"
            class="flex size-11 items-center justify-center rounded-lg text-thamani-forest transition-[background-color,scale] hover:bg-thamani-lime active:scale-[0.96] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <div class="min-w-0 text-center">
            <p class="truncate text-sm font-semibold text-thamani-forest">{@title}</p>
            <p class="truncate text-xs text-thamani-pewter">{@section_label}</p>
          </div>
          <div class="size-11" aria-hidden="true" />
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

          const apply = () => {
            const sidebar = getSidebar();
            if (sidebar) {
              const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
              sidebar.classList.toggle("sidebar-collapsed", collapsed);
            }
          };

          apply();

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
        },
        updated() {
          const sidebar = document.getElementById("sidebar-aside");
          if (sidebar) {
            const collapsed = localStorage.getItem("sidebar-collapsed") === "true";
            sidebar.classList.toggle("sidebar-collapsed", collapsed);
          }
        },
        destroyed() {
          if (this.handleGlobalClick) {
            document.removeEventListener("click", this.handleGlobalClick);
          }
        }
      }
    </script>
    """
  end

  defp current_site_name(%Scope{current_site_id: nil}), do: "All sites"

  defp current_site_name(%Scope{current_site_id: site_id, organization_id: organization_id}) do
    ThamaniDawa.Sites.get_site!(organization_id, site_id).name
  rescue
    Ecto.NoResultsError -> "Unknown site"
  end

  defp combined_site?(%Scope{current_site_id: nil}), do: false

  defp combined_site?(%Scope{current_site_id: site_id, organization_id: organization_id}) do
    site = ThamaniDawa.Sites.get_site!(organization_id, site_id)
    Site.pharmacy?(site) and Site.lab?(site)
  rescue
    Ecto.NoResultsError -> false
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

  attr :inner_content, :any, default: nil
  slot :inner_block, required: false

  def app(assigns) do
    ~H"""
    <.page_navbar current_scope={@current_scope} />

    <main class="w-full">
      {@inner_content || render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
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

  # Label for the page-level back link. An explicit `back_label` always wins;
  # otherwise the destination is matched against the nav items so `/org/sites`
  # reads "Back to Sites" without every page restating it.
  defp back_label(%{back_label: label}) when is_binary(label), do: label

  defp back_label(%{back: back, nav_items: nav_items}) when is_binary(back) do
    case Enum.find(nav_items, fn {_label, _icon, path} -> path == back end) do
      {label, _icon, _path} -> "Back to #{label}"
      nil -> "Back"
    end
  end

  defp back_label(_assigns), do: nil

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
