defmodule ThamaniDawa.Emails.TemplateTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Emails.Template

  describe "render/1 HTML template CTA safety" do
    test "renders CTA button for valid https URL" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Go to dashboard", url: "https://thamanidawa.example/dashboard"}
        })

      assert html =~ ~s(href="https://thamanidawa.example/dashboard")
      assert html =~ "Go to dashboard"
    end

    test "renders CTA button for valid http URL" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Local dev", url: "http://localhost:4000/dashboard"}
        })

      assert html =~ ~s(href="http://localhost:4000/dashboard")
      assert html =~ "Local dev"
    end

    test "renders CTA button for valid relative URL" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Relative link", url: "/dashboard"}
        })

      assert html =~ ~s(href="/dashboard")
      assert html =~ "Relative link"
    end

    test "omits CTA button for unsafe javascript: scheme" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Click me", url: "javascript:alert(1)"}
        })

      refute html =~ "javascript:"
      refute html =~ "Click me"
    end

    test "omits CTA button for unsafe data: scheme" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Data URI", url: "data:text/html,<script>alert(1)</script>"}
        })

      refute html =~ "data:text"
      refute html =~ "Data URI"
    end

    test "omits CTA button for protocol-relative // URLs" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "External unsafe", url: "//evil.com/phish"}
        })

      refute html =~ "//evil.com/phish"
      refute html =~ "External unsafe"
    end

    test "renders CTA button for the test-harness [TOKEN]...[TOKEN] placeholder" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Confirm", url: "[TOKEN]abc123[TOKEN]"}
        })

      assert html =~ ~s(href="[TOKEN]abc123[TOKEN]")
      assert html =~ "Confirm"
    end

    test "omits CTA button for a bare hostname without a scheme" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Bare host", url: "evil.com/phish"}
        })

      refute html =~ ~s(href="evil.com/phish")
      refute html =~ "Bare host"
    end
  end

  describe "render_text/1 plain text CTA safety" do
    test "includes CTA link for safe URL" do
      text =
        Template.render_text(%{
          title: "Welcome",
          cta: %{label: "Go to dashboard", url: "https://thamanidawa.example/dashboard"}
        })

      assert text =~ "Go to dashboard: https://thamanidawa.example/dashboard"
    end

    test "omits CTA link for unsafe URL scheme" do
      text =
        Template.render_text(%{
          title: "Welcome",
          cta: %{label: "Click me", url: "javascript:alert(1)"}
        })

      refute text =~ "javascript:"
      refute text =~ "Click me"
    end

    test "ends with the Thamani Dawa sign-off" do
      text = Template.render_text(%{title: "Welcome"})

      assert text =~ "— The Thamani Dawa Team"
    end
  end

  describe "rich/1" do
    test "wraps a :bold segment in <strong>, escaping its content" do
      assert Template.rich(["Hi ", {:bold, "Jane"}, "!"]) ==
               {:safe, "Hi <strong>Jane</strong>!", "Hi Jane!"}
    end

    test "escapes a plain (non-bold) segment the same as any other body text" do
      assert {:safe, html, plain} = Template.rich([{:bold, "<script>"}, " & friends"])
      assert html == "<strong>&lt;script&gt;</strong> &amp; friends"
      assert plain == "<script> & friends"
    end

    test "render/1 emits a rich intro/body paragraph's HTML unescaped, but as the safe markup rich/1 built" do
      html =
        Template.render(%{
          title: "Welcome",
          intro: Template.rich(["Hi ", {:bold, "Jane"}, ","]),
          body: [Template.rich(["Assigned to ", {:bold, "Medpoint CBD"}, "."])]
        })

      assert html =~ "Hi <strong>Jane</strong>,"
      assert html =~ "Assigned to <strong>Medpoint CBD</strong>."
    end

    test "render_text/1 renders a rich paragraph as plain text, with no <strong> tags" do
      text =
        Template.render_text(%{
          title: "Welcome",
          intro: Template.rich(["Hi ", {:bold, "Jane"}, ","])
        })

      assert text =~ "Hi Jane,"
      refute text =~ "<strong>"
    end
  end

  describe "logo" do
    test "render/1 uses the real logo image, not a placeholder mark" do
      html = Template.render(%{title: "Welcome"})

      assert html =~ ~s(<img src="http)
      assert html =~ "/images/logo.png"
      assert html =~ ~s(alt="Thamani Dawa")
    end
  end

  describe "brand color" do
    test "the CTA button uses brand forest, not a neutral dark" do
      html =
        Template.render(%{
          title: "Welcome",
          cta: %{label: "Go", url: "https://thamanidawa.example"}
        })

      assert html =~ "background-color:#1c3a13"
    end

    test "headings use brand forest" do
      html = Template.render(%{title: "Welcome"})

      assert html =~ "color:#1c3a13"
    end
  end
end
