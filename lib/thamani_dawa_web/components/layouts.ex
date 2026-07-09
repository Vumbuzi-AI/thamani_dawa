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
            <li :if={Scope.admin?(@current_scope) or Scope.pharmacist?(@current_scope)}>
              <.link navigate={~p"/pharmacy"} class="btn btn-ghost btn-sm">Pharmacy</.link>
            </li>
            <li :if={Scope.admin?(@current_scope) or Scope.lab_technician?(@current_scope)}>
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
        {"Verification queue", "hero-check-badge", ~p"/lab/verification-queue"},
        {"Receive stock", "hero-arrow-down-tray", ~p"/lab/receive-stock"},
        {"Scan", "hero-qr-code", ~p"/lab/scan"}
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
      class="min-h-screen"
      style="background: #fcfcf7; font-family: var(--font-thamani-sans, sans-serif);"
      phx-hook=".Sidebar"
    >
      <%!-- Top navigation bar --%>
      <header
        id="sidebar-topbar"
        class="sticky top-0 z-30 flex items-center gap-3 px-4"
        style="background: #1c3a13; height: 56px;"
      >
        <%!-- Sidebar toggle --%>
        <button
          id="sidebar-toggle"
          type="button"
          aria-label="Toggle sidebar"
          class="flex items-center justify-center rounded-lg p-1.5 transition-colors cursor-pointer"
          style="color: rgba(252,252,247,0.7);"
        >
          <.icon name="hero-bars-3" class="size-5" />
        </button>

        <a
          href={~p"/"}
          class="font-semibold text-sm tracking-wide"
          style="color: #fcfcf7;"
        >
          {@title}
        </a>

        <div class="flex-1" />

        <nav class="flex items-center gap-1">
          <.link
            :if={ThamaniDawa.Accounts.Scope.admin?(@current_scope)}
            navigate={~p"/org/team"}
            class="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
            style="color: rgba(252,252,247,0.7);"
          >
            Team
          </.link>
          <.link
            :if={ThamaniDawa.Accounts.Scope.admin?(@current_scope)}
            navigate={~p"/org/sites"}
            class="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
            style="color: rgba(252,252,247,0.7);"
          >
            Sites
          </.link>
          <.link
            :if={
              ThamaniDawa.Accounts.Scope.admin?(@current_scope) or
                ThamaniDawa.Accounts.Scope.pharmacist?(@current_scope)
            }
            navigate={~p"/pharmacy"}
            class="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
            style="color: rgba(252,252,247,0.7);"
          >
            Pharmacy
          </.link>
        </nav>
      </header>

      <div class="flex" style="min-height: calc(100vh - 56px);">
        <%!-- Sidebar --%>
        <aside
          id="sidebar-aside"
          class="shrink-0 flex flex-col py-6 px-2 overflow-hidden transition-[width] duration-200 ease-in-out"
          style="background: #1c3a13; width: 224px;"
        >
          <%!-- Section label — hidden when collapsed --%>
          <p
            id="sidebar-label"
            class="px-3 mb-4 text-xs font-medium uppercase tracking-widest whitespace-nowrap overflow-hidden transition-opacity duration-150"
            style="color: rgba(211,250,153,0.6);"
          >
            {@section_label}
          </p>

          <nav class="flex flex-col gap-0.5">
            <%= for {label, icon, path} <- @nav_items do %>
              <% active =
                if path == @base_path,
                  do: @current_path == @base_path,
                  else: String.starts_with?(@current_path, path) %>
              <.link
                navigate={path}
                class={[
                  "group flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-all whitespace-nowrap overflow-hidden"
                ]}
                style={
                  if active,
                    do: "background: #d3fa99; color: #1c3a13; font-weight: 500;",
                    else: "color: rgba(252,252,247,0.88);"
                }
              >
                <.icon name={icon} class="size-4 shrink-0" />
                <span id={"nav-label-#{path}"} class="transition-opacity duration-150">
                  {label}
                </span>
              </.link>
            <% end %>
          </nav>

          <div
            class="mt-auto pt-4 flex flex-col gap-2 overflow-hidden transition-all duration-150"
            style="border-top: 1px solid rgba(252,252,247,0.08);"
          >
            <div class="px-3 flex items-center gap-3">
              <div
                class="size-8 rounded-full flex items-center justify-center shrink-0 text-sm font-semibold"
                style="background: rgba(252,252,247,0.1); color: #d3fa99;"
              >
                {String.at(@current_scope.user.name || "U", 0)}
              </div>
              <div
                id="sidebar-profile"
                class="flex flex-col transition-opacity duration-150 whitespace-nowrap overflow-hidden"
              >
                <span class="text-sm font-medium" style="color: #fcfcf7;">{@current_scope.user.name}</span>
                <span class="text-xs" style="color: rgba(252,252,247,0.5);">
                  {current_site_name(@current_scope)}
                </span>
              </div>
            </div>

            <.link
              href={~p"/logout"}
              method="delete"
              class="mx-2 mt-1 px-3 py-2 rounded-lg text-sm font-medium transition-all flex items-center gap-3 group hover:bg-red-500/10"
              style="color: rgba(252,252,247,0.65);"
            >
              <.icon
                name="hero-arrow-right-start-on-rectangle"
                class="size-4 shrink-0 group-hover:text-red-400 transition-colors"
              />
              <span
                id="nav-label-logout"
                class="transition-opacity duration-150 group-hover:text-red-400"
              >
                Log out
              </span>
            </.link>
          </div>
        </aside>

        <%!-- Main content --%>
        <main class="flex-1 px-6 py-8 overflow-auto min-w-0" style="background: #fcfcf7;">
          <div class="mx-auto max-w-5xl space-y-4">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Sidebar">
      export default {
        mounted() {
          const sidebar = document.getElementById("sidebar-aside");
          const toggleBtn = document.getElementById("sidebar-toggle");
          const label = document.getElementById("sidebar-label");
          const profile = document.getElementById("sidebar-profile");
          let collapsed = localStorage.getItem("sidebar-collapsed") === "true";

          const apply = () => {
            if (collapsed) {
              sidebar.style.width = "56px";
              sidebar.querySelectorAll("span[id^='nav-label-']").forEach(el => {
                el.style.opacity = "0";
                el.style.width = "0";
                el.style.overflow = "hidden";
              });
              if (label) { label.style.opacity = "0"; label.style.height = "0"; label.style.marginBottom = "0"; }
              if (profile) { profile.style.opacity = "0"; profile.style.width = "0"; }
            } else {
              sidebar.style.width = "224px";
              sidebar.querySelectorAll("span[id^='nav-label-']").forEach(el => {
                el.style.opacity = "1";
                el.style.width = "";
                el.style.overflow = "";
              });
              if (label) { label.style.opacity = "1"; label.style.height = ""; label.style.marginBottom = ""; }
              if (profile) { profile.style.opacity = "1"; profile.style.width = ""; }
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
