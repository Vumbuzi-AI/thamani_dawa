defmodule ThamaniDawa.Distributor.Pricing do
  @moduledoc """
  Serialisation pricing in KES.

  **The defaults below are placeholders pending confirmation** — override
  them per environment with:

      config :thamani_dawa, ThamaniDawa.Distributor.Pricing,
        prepay_tiers: [{1, "2.00"}, {10_000, "1.50"}, {100_000, "1.00"}],
        flex_rate: "2.50",
        vat_rate: "0.16",
        minimum_prepay_quantity: 100,
        flex_cycle_days: 30,
        buffer_limit: 500

  `prepay_tiers` is a list of `{minimum_quantity, price_per_serial}`; the
  highest tier whose minimum the billed quantity reaches applies to the
  whole purchase.
  """

  alias ThamaniDawa.Distributor.VatStatus

  @defaults [
    prepay_tiers: [{1, "2.00"}, {10_000, "1.50"}, {100_000, "1.00"}],
    flex_rate: "2.50",
    vat_rate: "0.16",
    minimum_prepay_quantity: 100,
    flex_cycle_days: 30,
    buffer_limit: 500
  ]

  @type price_quote :: %{
          quantity: non_neg_integer(),
          unit_price: Decimal.t(),
          amount_excl_vat: Decimal.t(),
          vat_amount: Decimal.t(),
          amount: Decimal.t(),
          vat_applicable: boolean()
        }

  @doc "Price per serial for a prepay purchase of `quantity` serials."
  def unit_price(:prepay, quantity) do
    [lowest | _] = tiers = Enum.sort_by(setting(:prepay_tiers), &elem(&1, 0))
    {_minimum, price} = Enum.find(Enum.reverse(tiers), lowest, &(quantity >= elem(&1, 0)))
    Decimal.new(price)
  end

  def unit_price(:flex, _quantity), do: Decimal.new(setting(:flex_rate))

  @doc "Computes the full price breakdown for billing `quantity` serials."
  @spec total(map(), :prepay | :flex, non_neg_integer()) :: price_quote()
  def total(organization, kind, quantity) do
    unit_price = unit_price(kind, quantity)
    amount_excl_vat = unit_price |> Decimal.mult(quantity) |> Decimal.round(2)
    vat_applicable = VatStatus.applicable?(organization)

    vat_amount =
      if vat_applicable,
        do: amount_excl_vat |> Decimal.mult(vat_rate()) |> Decimal.round(2),
        else: Decimal.new("0.00")

    %{
      quantity: quantity,
      unit_price: unit_price,
      amount_excl_vat: amount_excl_vat,
      vat_amount: vat_amount,
      amount: Decimal.add(amount_excl_vat, vat_amount),
      vat_applicable: vat_applicable
    }
  end

  @doc "Human-readable rate, e.g. `\"KES 1.50 per serial\"`."
  def rate_label(kind, quantity \\ 1),
    do: "KES #{Decimal.to_string(unit_price(kind, quantity), :normal)} per serial"

  @doc "The prepay tiers as `{minimum_quantity, %Decimal{}}` for display."
  def prepay_tiers do
    :prepay_tiers
    |> setting()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {minimum, price} -> {minimum, Decimal.new(price)} end)
  end

  def vat_rate, do: Decimal.new(setting(:vat_rate))
  def minimum_prepay_quantity, do: setting(:minimum_prepay_quantity)
  def flex_cycle_days, do: setting(:flex_cycle_days)
  def buffer_limit, do: setting(:buffer_limit)

  defp setting(key) do
    :thamani_dawa
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, Keyword.fetch!(@defaults, key))
  end
end
