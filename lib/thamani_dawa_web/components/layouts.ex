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
      <%= if @inner_content do %>
        {@inner_content}
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
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
