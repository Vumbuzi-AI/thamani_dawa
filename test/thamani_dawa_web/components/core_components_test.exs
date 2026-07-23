defmodule ThamaniDawaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import ThamaniDawaWeb.CoreComponents

  describe "status_semantic/1" do
    test "maps warning statuses" do
      assert status_semantic(:pending) == :warning
      assert status_semantic(:pending_review) == :warning
      assert status_semantic(:under_review) == :warning
    end

    test "maps success statuses" do
      assert status_semantic(:completed) == :success
      assert status_semantic(:verified) == :success
      assert status_semantic(:approved) == :success
      assert status_semantic(:received) == :success
    end

    test "maps info statuses" do
      assert status_semantic(:in_progress) == :info
      assert status_semantic(:collected) == :info
      assert status_semantic(:partially_dispensed) == :info
    end

    test "maps danger statuses" do
      assert status_semantic(:cancelled) == :danger
      assert status_semantic(:rejected) == :danger
      assert status_semantic(:flagged) == :danger
    end

    test "falls back to neutral for anything unmapped" do
      assert status_semantic(:draft) == :neutral
      assert status_semantic(:something_unexpected) == :neutral
    end
  end

  describe "status_badge/1" do
    test "renders the humanized status text alongside the semantic color" do
      html = render_component(&status_badge/1, status: :partially_dispensed)

      assert html =~ "Partially dispensed"
      assert html =~ "bg-sky-100"
    end

    test "renders success styling for a success-mapped status" do
      html = render_component(&status_badge/1, status: :verified)

      assert html =~ "Verified"
      assert html =~ "bg-emerald-100"
    end
  end

  describe "blank_state/1" do
    test "renders the title and description" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.blank_state title="No prescriptions yet">
          Prescriptions appear here once a patient visit creates one.
        </.blank_state>
        """)

      assert html =~ "No prescriptions yet"
      assert html =~ "Prescriptions appear here"
      assert html =~ "border-dashed"
    end
  end

  describe "header/1" do
    test "renders without a toolbar divider when no :toolbar slot is given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header>Prescriptions</.header>
        """)

      assert html =~ "Prescriptions"
      refute html =~ "border-b border-thamani-stone"
    end

    test "renders the toolbar inside the same card, below a divider" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.header icon="hero-cube">
          Product catalog
          <:toolbar>
            <span id="toolbar-marker">toolbar content</span>
          </:toolbar>
        </.header>
        """)

      assert html =~ "Product catalog"
      assert html =~ "toolbar content"
      assert html =~ "border-b border-thamani-stone"
      assert html =~ "rounded-2xl border border-thamani-stone bg-thamani-snow shadow-sm"
    end
  end

  describe "search_input/1" do
    test "renders a text input with the given name, value, and placeholder" do
      html =
        render_component(&search_input/1,
          name: "search",
          value: "amox",
          placeholder: "Search products"
        )

      assert html =~ ~s(name="search")
      assert html =~ ~s(value="amox")
      assert html =~ "Search products"
    end
  end

  describe "filter_drawer/1" do
    test "renders the trigger with an active-count badge and its groups" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.filter_drawer id="test-filters" apply_event="apply_filters" active_count={2}>
          <:group label="Category">
            <select name="filters[category]"><option>A</option></select>
          </:group>
        </.filter_drawer>
        """)

      assert html =~ "Filters"
      assert html =~ "rounded-full bg-thamani-forest text-xs font-semibold text-white"
      assert html =~ "Category"
      assert html =~ "bg-thamani-lime"
    end

    test "renders chips with a clear-all link when chips are given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.filter_drawer id="test-filters" apply_event="apply_filters">
          <:group label="Category">
            <select name="filters[category]"><option>A</option></select>
          </:group>
          <:chip label="Category: Antibiotics" clear="clear_chip" />
        </.filter_drawer>
        """)

      assert html =~ "Category: Antibiotics"
      assert html =~ "Clear all"
    end

    test "hides the Apply button in instant mode" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.filter_drawer id="test-filters" apply_event="filter" instant={true}>
          <:group label="Period">
            <select name="period"><option>A</option></select>
          </:group>
        </.filter_drawer>
        """)

      refute html =~ "Apply filters"
    end
  end
end
