defmodule ThamaniDawaWeb.DatePickerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import ThamaniDawaWeb.CoreComponents

  test "renders the TD trigger with a readable date and an ISO hidden value" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.date_picker id="expiry" name="batch[expiry_date]" label="Expiry date" value={~D[2026-11-23]} required />
      """)

    assert html =~ ~s(phx-hook="ThamaniDawaWeb.CoreComponents.DatePicker")
    assert html =~ ~s(name="batch[expiry_date]")
    assert html =~ ~s(value="2026-11-23")
    assert html =~ "23 Nov 2026"
    assert html =~ ~s(id="expiry-trigger")
    assert html =~ ~s(aria-haspopup="dialog")
    refute html =~ ~s(type="date")
  end

  test "shows the placeholder when empty and passes bounds to the hook" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.date_picker id="dob" name="dob" label="Date of birth" max="today" />
      """)

    assert html =~ "Choose a date"
    assert html =~ "is-placeholder"
    assert html =~ ~s(data-max="today")
  end

  test "<.input type=date> renders the picker, never the native calendar" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.input type="date" id="from" name="filters[date_from]" value="2026-01-05" label="From" />
      """)

    assert html =~ "td-dp-trigger"
    assert html =~ ~s(value="2026-01-05")
    assert html =~ "5 Jan 2026"
    refute html =~ ~s(type="date")
  end

  test "<.td_input type=date> renders the picker with field errors" do
    assigns = %{
      form:
        to_form(%{"production_date" => "2026-03-01"}, as: :serial_generation, errors: [production_date: {"can't be blank", []}])
    }

    html =
      rendered_to_string(~H"""
      <ThamaniDawaWeb.TDComponents.td_input field={@form[:production_date]} type="date" label="Production date" />
      """)

    assert html =~ "td-dp-trigger"
    assert html =~ ~s(name="serial_generation[production_date]")
    assert html =~ "1 Mar 2026"
    refute html =~ ~s(type="date")
  end
end
