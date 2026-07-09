defmodule ThamaniDawaWeb.PageComponents do
  @moduledoc """
  Layout components for public marketing and legal pages.

  Imported globally via `html_helpers/0` in `ThamaniDawaWeb`, so all components
  are available in every template and LiveView without additional imports.

  ## Components

  - `page_footer/1`    — Shared site footer with active-link pattern matching
  - `legal_hero/1`     — Dark hero band used by Privacy and Terms pages
  - `legal_toc/1`      — Numbered table of contents
  - `legal_section/1`  — Numbered prose section scaffold (anchor + badge + h2 + slot)
  - `legal_page_nav/1` — "← Back / Back to top ↑" navigation strip
  """

  use Phoenix.Component
  import ThamaniDawaWeb.CoreComponents

  # ============================================================
  # page_footer
  # ============================================================

  @doc """
  Renders the shared site footer.

  Accepts `active_link` to highlight the current page's link in the Legal column.
  Pattern-matched to apply `font-weight: 500; color: var(--thamani-snow)` to the active link.

  ## Examples

      <.page_footer active_link={:privacy} />
      <.page_footer active_link={:terms} />
      <.page_footer />
  """
  attr :active_link, :atom,
    values: [:privacy, :terms, :contact, :none],
    default: :none,
    doc: "which legal link is the current page (highlights it in the footer)"

  def page_footer(assigns) do
    ~H"""
    <footer style="background: var(--thamani-forest); padding: 64px 24px 40px; border-top: 1px solid rgba(252,252,247,0.08);">
      <div class="max-w-6xl mx-auto">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-10 md:gap-16 mb-16">
          <%!-- Brand --%>
          <div class="col-span-2 md:col-span-1">
            <a
              href="/"
              style="font-size: 18px; font-weight: 500; color: var(--thamani-snow); text-decoration: none; letter-spacing: -0.01em;"
            >
              Thamani Dawa
            </a>
            <p
              class="mt-3"
              style="font-size: 14px; line-height: 1.65; color: rgba(252,252,247,0.45); max-width: 200px;"
            >
              Seamless pharmacy management for Kenya.
            </p>
          </div>

          <%!-- Product --%>
          <div>
            <p
              class="mb-5"
              style="font-size: 11px; font-weight: 500; color: rgba(252,252,247,0.35); letter-spacing: 0.1em; text-transform: uppercase;"
            >
              Product
            </p>
            <ul class="space-y-3">
              <li>
                <a
                  href="/login"
                  style="font-size: 14px; color: rgba(252,252,247,0.6); text-decoration: none;"
                >
                  Log In
                </a>
              </li>
              <li>
                <a
                  href="/signup"
                  style="font-size: 14px; color: rgba(252,252,247,0.6); text-decoration: none;"
                >
                  Sign Up
                </a>
              </li>
              <li>
                <a
                  href="/#features"
                  style="font-size: 14px; color: rgba(252,252,247,0.6); text-decoration: none;"
                >
                  Features
                </a>
              </li>
            </ul>
          </div>

          <%!-- Company --%>
          <div>
            <p
              class="mb-5"
              style="font-size: 11px; font-weight: 500; color: rgba(252,252,247,0.35); letter-spacing: 0.1em; text-transform: uppercase;"
            >
              Company
            </p>
            <ul class="space-y-3">
              <li>
                <a
                  href="/contact"
                  style="font-size: 14px; color: rgba(252,252,247,0.6); text-decoration: none;"
                >
                  Contact
                </a>
              </li>
            </ul>
          </div>

          <%!-- Legal — active link is pattern-matched --%>
          <div>
            <p
              class="mb-5"
              style="font-size: 11px; font-weight: 500; color: rgba(252,252,247,0.35); letter-spacing: 0.1em; text-transform: uppercase;"
            >
              Legal
            </p>
            <ul class="space-y-3">
              <li>
                <a href="/privacy" style={footer_legal_link_style(@active_link == :privacy)}>
                  <%= if @active_link == :privacy do %>
                    Privacy Policy ←
                  <% else %>
                    Privacy Policy
                  <% end %>
                </a>
              </li>
              <li>
                <a href="/terms" style={footer_legal_link_style(@active_link == :terms)}>
                  <%= if @active_link == :terms do %>
                    Terms of Service ←
                  <% else %>
                    Terms of Service
                  <% end %>
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div class="pt-8" style="border-top: 1px solid rgba(252,252,247,0.08);">
          <p style="font-size: 13px; color: rgba(252,252,247,0.35);">
            © 2025 Thamani Dawa. All rights reserved. · Licensed healthcare software · Kenya
          </p>
        </div>
      </div>
    </footer>
    """
  end

  # Pattern-matched helper: active link gets bright colour + weight; inactive is muted
  defp footer_legal_link_style(true),
    do: "font-size: 14px; color: var(--thamani-snow); text-decoration: none; font-weight: 500;"

  defp footer_legal_link_style(false),
    do: "font-size: 14px; color: rgba(252,252,247,0.6); text-decoration: none;"

  # ============================================================
  # legal_hero
  # ============================================================

  @doc """
  Renders the dark Forest-green hero band used on Privacy and Terms pages.

  ## Examples

      <.legal_hero
        title="Privacy Notice"
        subtitle="This notice describes how Thamani Dawa collects, uses, and protects your personal information."
        date_label="Last updated: April 17, 2026"
      />

      <.legal_hero
        title="Terms of Service"
        subtitle="Please read these Terms carefully before using the platform."
        date_label="Effective: April 17, 2026"
      />
  """
  attr :title, :string, required: true, doc: "main page heading"
  attr :subtitle, :string, required: true, doc: "subtitle paragraph under the heading"
  attr :badge_label, :string, default: "Legal", doc: "pill badge text"

  attr :date_label, :string,
    required: true,
    doc: "date string, e.g. 'Last updated: April 17, 2026'"

  attr :back_href, :string, default: "/", doc: "href for the back link"

  def legal_hero(assigns) do
    ~H"""
    <section style="background: var(--thamani-forest); padding: 72px 24px 64px;">
      <div class="max-w-3xl mx-auto">
        <a
          href={@back_href}
          style="font-size: 13px; color: rgba(252,252,247,0.45); text-decoration: none; display: inline-flex; align-items: center; gap: 6px; margin-bottom: 32px;"
        >
          ← Home
        </a>
        <div class="flex items-center gap-3 mb-5">
          <span
            class="thamani-badge"
            style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px;"
          >
            {@badge_label}
          </span>
          <span style="font-size: 12px; color: rgba(252,252,247,0.45);">
            {@date_label}
          </span>
        </div>
        <h1 style="font-size: clamp(32px, 4vw, 48px); font-weight: 350; letter-spacing: -0.72px; line-height: 1.1; color: var(--thamani-snow); text-wrap: balance; margin-bottom: 16px;">
          {@title}
        </h1>
        <p style="font-size: 17px; line-height: 1.65; color: rgba(252,252,247,0.6); max-width: 560px;">
          {@subtitle}
        </p>
      </div>
    </section>
    """
  end

  # ============================================================
  # legal_toc
  # ============================================================

  @doc """
  Renders a numbered table of contents for legal pages.

  Accepts a list of `{anchor, label}` string tuples.
  Renders each as a green pill-number + underlined anchor link.

  ## Examples

      <.legal_toc entries={[
        {"what-we-collect", "What information do we collect?"},
        {"how-we-process",  "How do we process your information?"}
      ]} />
  """
  attr :entries, :list,
    required: true,
    doc: "list of {anchor_string, label_string} tuples"

  def legal_toc(assigns) do
    ~H"""
    <div style="margin-bottom: 56px;">
      <p style="font-size: 11px; font-weight: 500; color: var(--thamani-subtle); letter-spacing: 0.09em; text-transform: uppercase; margin-bottom: 16px;">
        Table of Contents
      </p>
      <ol style="list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px;">
        <%= for {{anchor, label}, idx} <- Enum.with_index(@entries, 1) do %>
          <li style="display: flex; align-items: baseline; gap: 10px;">
            <span style="font-size: 11px; font-weight: 500; color: var(--thamani-snow); background: var(--thamani-forest); border-radius: 1000px; padding: 2px 8px; flex-shrink: 0; font-variant-numeric: tabular-nums;">
              {idx}
            </span>
            <a
              href={"##{anchor}"}
              style="font-size: 15px; color: var(--thamani-forest); text-decoration: underline; text-underline-offset: 3px;"
            >
              {label}
            </a>
          </li>
        <% end %>
      </ol>
    </div>
    """
  end

  # ============================================================
  # legal_section
  # ============================================================

  @doc """
  Renders a numbered prose section for legal pages.

  Wraps the repeated pattern: scroll anchor div → section-number badge →
  h2 title → inner content slot.

  ## Examples

      <.legal_section id="what-we-collect" number={1} title="What Information Do We Collect?">
        <p>...</p>
        <ul>...</ul>
      </.legal_section>
  """
  attr :id, :string, required: true, doc: "DOM id used as scroll anchor"
  attr :number, :any, required: true, doc: "section number displayed in the badge"
  attr :title, :string, required: true, doc: "section heading text"

  slot :inner_block, required: true

  def legal_section(assigns) do
    ~H"""
    <div id={@id} style="margin-bottom: 56px; scroll-margin-top: 80px;">
      <div class="flex items-center gap-3 mb-4">
        <span class="thamani-badge">{@number}</span>
        <h2 style="font-size: 22px; font-weight: 400; color: var(--thamani-forest); letter-spacing: -0.3px; margin: 0;">
          {@title}
        </h2>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ============================================================
  # legal_page_nav
  # ============================================================

  @doc """
  Renders the "← Back to Thamani Dawa / Back to top ↑" navigation strip
  at the bottom of legal pages.

  ## Examples

      <.legal_page_nav />
      <.legal_page_nav back_href="/" back_label="← Back to Thamani Dawa" />
  """
  attr :back_href, :string, default: "/", doc: "href for the back link"
  attr :back_label, :string, default: "← Back to Thamani Dawa", doc: "back link text"

  def legal_page_nav(assigns) do
    ~H"""
    <div style="border-top: 1px solid var(--thamani-stone); padding-top: 32px; display: flex; align-items: center; justify-content: space-between;">
      <a
        href={@back_href}
        style="font-size: 14px; color: var(--thamani-pewter); text-decoration: underline; text-underline-offset: 3px;"
      >
        {@back_label}
      </a>
      <a
        href="#"
        style="font-size: 14px; color: var(--thamani-pewter); text-decoration: underline; text-underline-offset: 3px;"
      >
        Back to top ↑
      </a>
    </div>
    """
  end

  # ============================================================
  # page_navbar
  # ============================================================

  @doc """
  Renders the main pill-shaped navigation bar for the public pages.
  Accepts `@current_scope` to determine authentication state and route
  the avatar to the dashboard.
  """
  attr :current_scope, :map, default: nil, doc: "The current scope for the user, if authenticated"

  def page_navbar(assigns) do
    ~H"""
    <div class="fixed top-6 left-0 w-full z-50 px-4 sm:px-8 pointer-events-none">
      <header
        class="max-w-5xl mx-auto flex items-center justify-between px-4 sm:px-6 h-[64px] pointer-events-auto shadow-sm"
        style="background: var(--thamani-snow); border: 1.5px solid var(--thamani-stone); border-radius: 1000px;"
      >
        <%!-- Left side: Avatar + Brand --%>
        <div class="flex items-center gap-4">
          <a
            href={dashboard_path(@current_scope)}
            class="flex items-center justify-center w-[34px] h-[34px] rounded-full transition-transform hover:scale-105 active:scale-95"
            style="background: var(--thamani-stone); color: var(--thamani-forest);"
            aria-label="Go to Dashboard"
          >
            <.icon name="hero-user-solid" class="w-[20px] h-[20px]" />
          </a>
          <a
            href="/"
            class="hidden sm:flex"
            style="font-size: 17px; font-weight: 500; color: var(--thamani-forest); text-decoration: none; letter-spacing: -0.01em; align-items: center; gap: 6px;"
          >
            Thamani Dawa
            <span style="width: 5px; height: 5px; border-radius: 50%; background: var(--thamani-lime);"></span>
          </a>
        </div>

        <%!-- Center: Nav Links --%>
        <nav class="hidden md:flex items-center gap-8">
          <a
            href="/#features"
            style="font-size: 14px; font-weight: 500; color: var(--thamani-forest); text-decoration: none;"
          >Features</a>

          <a
            href="/contact"
            style="font-size: 14px; font-weight: 500; color: var(--thamani-forest); text-decoration: none;"
          >Contact</a>
        </nav>

        <%!-- Right: Actions --%>
        <div class="flex items-center gap-3">
          <%= if @current_scope do %>
            <.thamani_btn
              variant="primary"
              href={dashboard_path(@current_scope)}
              style="padding: 8px 20px; font-size: 14px;"
            >
              Dashboard
            </.thamani_btn>
            <.link
              href="/logout"
              method="delete"
              class="whitespace-nowrap"
              style="font-size: 14px; font-weight: 500; color: var(--thamani-pewter); text-decoration: none; margin-left: 8px;"
            >
              Log out
            </.link>
          <% else %>
            <.thamani_btn
              variant="ghost_inv"
              href="/login"
              style="padding: 8px 20px; font-size: 14px; border-color: var(--thamani-stone);"
            >
              Log in
            </.thamani_btn>
            <.thamani_btn variant="primary" href="/signup" style="padding: 8px 20px; font-size: 14px;">
              Sign up
            </.thamani_btn>
          <% end %>
        </div>
      </header>
    </div>
    """
  end

  def dashboard_path(nil), do: "/login"

  def dashboard_path(scope) do
    cond do
      ThamaniDawa.Accounts.Scope.admin?(scope) -> "/org/team"
      ThamaniDawa.Accounts.Scope.pharmacist?(scope) -> "/pharmacy"
      ThamaniDawa.Accounts.Scope.lab_technician?(scope) -> "/lab"
      true -> "/login"
    end
  end
end
