defmodule ThamaniDawaWeb.ErrorHTML do
  @moduledoc """
  HTML pages for requests the router cannot finish.

  404, 403, and 500 have their own copy. Any other HTML status uses the
  same page with Phoenix's status name, so a browser never gets a bare
  status string.
  """
  use ThamaniDawaWeb, :html

  embed_templates "error_html/*"

  def render(template, assigns) do
    code = template |> String.split(".") |> List.first()
    title = Phoenix.Controller.status_message_from_template(template)

    assigns =
      Map.merge(assigns, %{
        code: code,
        title: title,
        detail: "That request could not be completed."
      })

    ~H"""
    <.error_page code={@code} title={@title} detail={@detail} />
    """
  end

  attr :code, :string, required: true
  attr :title, :string, required: true
  attr :detail, :string, required: true

  defp error_page(assigns) do
    ~H"""
    <main class="flex min-h-screen flex-col bg-thamani-canvas text-thamani-forest">
      <header class="px-6 py-5 sm:px-8">
        <a href={~p"/"} class="inline-flex items-center gap-2" aria-label="Thamani Dawa home">
          <img src={~p"/images/logo-transparent.png"} alt="" width="36" height="36" class="size-9" />
          <span class="text-sm font-medium tracking-tight">Thamani Dawa</span>
        </a>
      </header>
      <div class="flex flex-1 flex-col items-center justify-center px-6 pb-24 text-center">
        <p class="text-sm font-medium tracking-tight text-thamani-pewter tabular-nums">{@code}</p>
        <h1 class="mt-3 max-w-md text-3xl font-medium tracking-tight sm:text-4xl">{@title}</h1>
        <p class="mt-3 max-w-md text-sm leading-6 text-thamani-pewter">{@detail}</p>
        <div class="mt-8">
          <.button variant="primary" href={~p"/"}>Back to home</.button>
        </div>
      </div>
    </main>
    """
  end
end
