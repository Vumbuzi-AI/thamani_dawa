defmodule ThamaniDawaWeb.BatchFormComponents do
  @moduledoc """
  Shared "receive stock" form, used by both `ThamaniDawaWeb.ReceiveStockLive`
  (pharmacy) and `ThamaniDawaWeb.LabReceiveStockLive` (lab) — they write to
  the same `ThamaniDawa.Batches` context and only differ in which products
  populate the product picker (passed in via the `products` assign) and
  where they redirect to after a successful receipt.
  """

  use Phoenix.Component

  import ThamaniDawaWeb.CoreComponents

  attr :form, Phoenix.HTML.Form, required: true
  attr :products, :list, required: true
  attr :suppliers, :list, required: true
  attr :sites, :list, required: true
  attr :site_locked, :boolean, default: false
  attr :gs1_decode_error, :string, default: nil

  def batch_form(assigns) do
    ~H"""
    <div class="card bg-base-200 mb-4">
      <div class="card-body">
        <h2 class="font-semibold mb-2">Paste a GS1 code</h2>
        <form id="receive-stock-gs1-form" phx-submit="decode_gs1" class="flex gap-2 items-end">
          <div class="flex-1">
            <.input
              name="raw_gs1"
              label="Raw GS1 element string"
              placeholder="(01)0...(10)LOT1(17)261231"
            />
          </div>
          <.button class="mb-2">Decode &amp; prefill</.button>
        </form>
        <p :if={@gs1_decode_error} id="gs1-decode-error" class="mt-2 text-error">
          {@gs1_decode_error}
        </p>
      </div>
    </div>

    <form phx-submit="save">
      <.input
        field={@form[:product_id]}
        type="select"
        label="Product"
        options={Enum.map(@products, &{product_label(&1), &1.id})}
        prompt="Choose a product"
        required
      />

      <.input
        :if={@site_locked}
        field={@form[:site_id]}
        type="hidden"
      />
      <.input
        :if={not @site_locked}
        field={@form[:site_id]}
        type="select"
        label="Site"
        options={Enum.map(@sites, &{&1.name, &1.id})}
        prompt="Choose a site"
        required
      />

      <.input field={@form[:gtin]} label="GTIN" />
      <.input field={@form[:batch_no]} label="Batch / lot no." required />
      <.input field={@form[:serial]} label="Serial" />
      <.input field={@form[:manufacture_date]} type="date" label="Manufacture date" />
      <.input field={@form[:expiry_date]} type="date" label="Expiry" required />
      <.input field={@form[:quantity]} type="number" label="Quantity" required />
      <.input field={@form[:cost_per_unit]} type="number" label="Cost per unit" step="any" />

      <.input
        field={@form[:supplier_id]}
        type="select"
        label="Supplier"
        options={Enum.map(@suppliers, &{&1.name, &1.id})}
        prompt="No supplier"
      />

      <.button variant="primary" class="mt-2">Receive stock</.button>
    </form>
    """
  end

  defp product_label(product) do
    product.generic_name || product.brand_name || "(unnamed)"
  end
end
