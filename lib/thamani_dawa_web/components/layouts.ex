defmodule ThamaniDawaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ThamaniDawaWeb, :html

  alias ThamaniDawa.Accounts.Scope

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
    <div class="min-h-screen">
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

  slot :inner_block, required: true

  def lab_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      title="Thamani Dawa"
      section_label="Lab"
      base_path="/lab"
      nav_items={[
        {"Dashboard", "hero-squares-2x2", ~p"/lab"},
        {"Orders", "hero-clipboard-document-list", ~p"/lab/orders"},
        {"Tests", "hero-beaker", ~p"/lab/tests"},
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

  slot :inner_block, required: true

  def pharmacy_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      title="Thamani Dawa"
      section_label="Pharmacy"
      base_path="/pharmacy"
      nav_items={[
        {"Dashboard", "hero-squares-2x2", ~p"/pharmacy"},
        {"Receive stock", "hero-arrow-down-tray", ~p"/pharmacy/receive-stock"},
        {"Prescriptions", "hero-document-text", ~p"/pharmacy/prescriptions"},
        {"Scan", "hero-qr-code", ~p"/pharmacy/scan"}
      ]}
    >
      {render_slot(@inner_block)}
    </.sidebar_shell>
    """
  end

  @doc """
  Renders the authenticated org shell: a sticky top bar plus a
  collapsible sidebar with quick-links to every org section.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, default: ""

  slot :inner_block, required: true

  def org_shell(assigns) do
    ~H"""
    <.sidebar_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
      title="Thamani Dawa (Admin)"
      section_label="Organization"
      base_path="/org"
      nav_items={[
        {"Team", "hero-user-group", ~p"/org/team"},
        {"Sites", "hero-building-office-2", ~p"/org/sites"},
        {"Products", "hero-cube", ~p"/org/products"}
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

  slot :inner_block, required: true

  defp sidebar_shell(assigns) do
    ~H"""
    <div
      id="sidebar-shell"
      class="h-screen flex overflow-hidden"
      style="background: var(--thamani-canvas); font-family: var(--font-thamani-sans, sans-serif);"
      phx-hook=".Sidebar"
    >
      <%!-- Sidebar --%>
      <aside
        id="sidebar-aside"
        class="shrink-0 flex flex-col overflow-y-auto overflow-x-hidden transition-[width] duration-200 ease-in-out border-r"
        style="background: var(--thamani-snow); border-color: var(--thamani-border-nav); width: 288px; padding: 24px 20px;"
      >
        <%!-- Brand row --%>
        <div class="flex items-center gap-3 mb-6">
          <div
            class="flex items-center justify-center shrink-0 font-bold text-[13px]"
            style="width: 44px; height: 44px; border-radius: 12px; background: var(--thamani-lime); border: 1px solid var(--thamani-accent); color: var(--thamani-forest);"
          >
            TD
          </div>
          <div
            id="sidebar-brand-text"
            class="flex flex-col overflow-hidden whitespace-nowrap transition-opacity duration-150"
          >
            <a
              href={~p"/"}
              class="font-bold text-[17px] leading-tight"
              style="color: var(--thamani-forest);"
            >
              {@title}
            </a>
            <span class="text-[13px] font-medium" style="color: var(--thamani-pewter);">
              {@section_label}
            </span>
          </div>
          <button
            id="sidebar-toggle"
            type="button"
            aria-label="Toggle sidebar"
            class="ml-auto shrink-0 flex items-center justify-center rounded-xl transition-colors cursor-pointer"
            style="width: 36px; height: 36px; background: var(--thamani-snow); border: 1px solid var(--thamani-border-nav); color: var(--thamani-forest);"
          >
            <span id="sidebar-toggle-icon" class="inline-flex transition-transform duration-200">
              <.icon name="hero-chevron-left" class="size-4" />
            </span>
          </button>
        </div>

        <%!-- Primary navigation --%>
        <nav class="flex flex-col gap-1">
          <%= for {label, icon, path} <- @nav_items do %>
            <% active =
              if path == @base_path,
                do: @current_path == @base_path,
                else: String.starts_with?(@current_path, path) %>
            <.link
              navigate={path}
              class="flex items-center gap-3 rounded-xl text-[15px] font-semibold transition-all whitespace-nowrap overflow-hidden"
              style={
                if active,
                  do:
                    "background: var(--thamani-lime); color: var(--thamani-forest); padding: 12px; min-height: 48px;",
                  else: "color: var(--thamani-pewter); padding: 12px; min-height: 48px;"
              }
            >
              <.icon name={icon} class="size-5 shrink-0" />
              <span id={"nav-label-#{path}"} class="transition-opacity duration-150">
                {label}
              </span>
            </.link>
          <% end %>
        </nav>

        <%!-- Cross-portal switch: only combined pharmacy/lab staff can hop
             portals; single-role staff never see the other operational side. --%>
        <div
          :if={Scope.pharma_lab?(@current_scope)}
          id="sidebar-portal-switch"
          class="flex flex-col gap-1 mt-4 pt-4"
          style="border-top: 1px solid var(--thamani-border-nav);"
        >
          <span
            id="nav-label-portal-switch-heading"
            class="px-3 text-[11px] font-semibold uppercase tracking-wide transition-opacity duration-150"
            style="color: var(--thamani-subtle);"
          >
            Switch portal
          </span>
          <.link
            :if={@base_path != "/pharmacy"}
            id="portal-link-pharmacy"
            navigate={~p"/pharmacy"}
            class="flex items-center gap-3 rounded-xl text-[15px] font-semibold transition-all whitespace-nowrap overflow-hidden"
            style="color: var(--thamani-pewter); padding: 12px; min-height: 48px;"
          >
            <.icon name="hero-building-storefront" class="size-5 shrink-0" />
            <span id="nav-label-/pharmacy" class="transition-opacity duration-150">Pharmacy</span>
          </.link>
          <.link
            :if={@base_path != "/lab"}
            id="portal-link-lab"
            navigate={~p"/lab"}
            class="flex items-center gap-3 rounded-xl text-[15px] font-semibold transition-all whitespace-nowrap overflow-hidden"
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
          <div
            id="sidebar-account-card"
            class="flex items-center gap-3 overflow-hidden transition-opacity duration-150"
            style="background: #FBFBFF; border: 1px solid #E8EBF3; border-radius: 16px; padding: 14px 16px;"
          >
            <div
              class="rounded-full flex items-center justify-center shrink-0 font-bold text-[15px]"
              style="width: 44px; height: 44px; background: var(--thamani-forest); color: var(--thamani-snow);"
            >
              {String.at(@current_scope.user.name || "U", 0)}
            </div>
            <div
              id="sidebar-profile"
              class="flex flex-col overflow-hidden whitespace-nowrap transition-opacity duration-150"
            >
              <span class="text-[15px] font-bold truncate" style="color: #1F2433;">
                {@current_scope.user.name}
              </span>
              <span class="text-[13px]" style="color: var(--thamani-pewter);">
                {current_site_name(@current_scope)}
              </span>
            </div>
          </div>

          <div
            :if={ThamaniDawa.Accounts.Scope.admin?(@current_scope)}
            id="sidebar-admin-shortcuts"
            class="flex items-center gap-1 overflow-hidden transition-opacity duration-150"
          >
            <.link
              navigate={~p"/org/team"}
              class="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
              style="color: var(--thamani-pewter);"
            >
              Team
            </.link>
            <.link
              navigate={~p"/org/sites"}
              class="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
              style="color: var(--thamani-pewter);"
            >
              Sites
            </.link>
          </div>

          <.link
            href={~p"/logout"}
            method="delete"
            class="px-3 py-2 rounded-xl text-sm font-medium transition-all flex items-center gap-3 group hover:bg-red-50"
            style="color: var(--thamani-error);"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 shrink-0" />
            <span id="nav-label-logout" class="transition-opacity duration-150">
              Log out
            </span>
          </.link>
        </div>
      </aside>

      <%!-- Main content --%>
      <main class="flex-1 overflow-y-auto min-w-0 px-4 py-6 lg:px-8 lg:py-8">
        <div class="mx-auto space-y-4" style="max-width: 1600px;">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
      export default {
        mounted() {
          const sidebar = document.getElementById("sidebar-aside");
          const toggleBtn = document.getElementById("sidebar-toggle");
          const toggleIcon = document.getElementById("sidebar-toggle-icon");
          const brandText = document.getElementById("sidebar-brand-text");
          const profile = document.getElementById("sidebar-profile");
          const accountCard = document.getElementById("sidebar-account-card");
          const adminShortcuts = document.getElementById("sidebar-admin-shortcuts");
          let collapsed = localStorage.getItem("sidebar-collapsed") === "true";

          const apply = () => {
            if (collapsed) {
              sidebar.style.width = "72px";
              sidebar.querySelectorAll("span[id^='nav-label-']").forEach(el => {
                el.style.opacity = "0";
                el.style.width = "0";
                el.style.overflow = "hidden";
              });
              if (brandText) brandText.style.display = "none";
              if (profile) { profile.style.opacity = "0"; profile.style.width = "0"; }
              if (accountCard) accountCard.style.display = "none";
              if (adminShortcuts) adminShortcuts.style.display = "none";
              if (toggleIcon) toggleIcon.style.transform = "rotate(180deg)";
            } else {
              sidebar.style.width = "288px";
              sidebar.querySelectorAll("span[id^='nav-label-']").forEach(el => {
                el.style.opacity = "1";
                el.style.width = "";
                el.style.overflow = "";
              });
              if (brandText) brandText.style.display = "";
              if (profile) { profile.style.opacity = "1"; profile.style.width = ""; }
              if (accountCard) accountCard.style.display = "";
              if (adminShortcuts) adminShortcuts.style.display = "";
              if (toggleIcon) toggleIcon.style.transform = "";
            }
            localStorage.setItem("sidebar-collapsed", collapsed);
          };

          apply();

          toggleBtn && toggleBtn.addEventListener("click", () => {
            collapsed = !collapsed;
            apply();
          });
        }
      }
    </script>
    """
  end

  defp current_site_name(%Scope{user: %{site_id: nil}}), do: "All sites"

  defp current_site_name(%Scope{user: %{site_id: site_id}, organization_id: organization_id}) do
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
