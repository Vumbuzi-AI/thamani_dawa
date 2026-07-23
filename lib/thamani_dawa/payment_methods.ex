defmodule ThamaniDawa.PaymentMethods do
  @moduledoc """
  The approved payment methods shared by lab orders and prescriptions.

  The chosen method is stored as-is on each header's `payment_type` column.
  Whether the order has actually been settled is tracked separately by the
  `has_paid` boolean — selecting a method never implies payment.
  """

  @methods ["Cash", "Mobile Money", "Insurance"]

  @doc "The approved payment methods, in display order."
  def all, do: @methods

  @doc "Whether `value` is one of the approved payment methods."
  def valid?(value), do: value in @methods
end
