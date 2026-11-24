defmodule ThamaniDawaWeb.CarePortal do
  @moduledoc """
  Pharmacy and lab share one screen per job. The portal is which door
  the person came through: it picks the shell, the path, and the stock.
  """

  use ThamaniDawaWeb, :verified_routes

  alias ThamaniDawa.Sites.Site

  def on_mount(portal, _params, _session, socket) when portal in [:pharmacy, :lab] do
    {:cont, Phoenix.Component.assign(socket, :portal, portal)}
  end

  def inventory_type(:lab), do: :lab_consumable
  def inventory_type(_portal), do: :medicine

  def site?(:lab, site), do: Site.lab?(site)
  def site?(_portal, site), do: Site.pharmacy?(site)

  def patients(:lab), do: ~p"/lab/patients"
  def patients(_portal), do: ~p"/pharmacy/patients"
  def patient(:lab, id), do: ~p"/lab/patients/#{id}"
  def patient(_portal, id), do: ~p"/pharmacy/patients/#{id}"

  def patients_tab(portal, tab, search) do
    search = String.trim(search || "")

    cond do
      portal == :lab and search != "" -> ~p"/lab/patients?tab=#{tab}&search=#{search}"
      portal == :lab -> ~p"/lab/patients?tab=#{tab}"
      search != "" -> ~p"/pharmacy/patients?tab=#{tab}&search=#{search}"
      true -> ~p"/pharmacy/patients?tab=#{tab}"
    end
  end

  def requisitions(:lab), do: ~p"/lab/requisitions"
  def requisitions(_portal), do: ~p"/pharmacy/requisitions"
  def requisition(:lab, id), do: ~p"/lab/requisitions/#{id}"
  def requisition(_portal, id), do: ~p"/pharmacy/requisitions/#{id}"
  def requisitions_new(:lab), do: ~p"/lab/requisitions/new"
  def requisitions_new(_portal), do: ~p"/pharmacy/requisitions/new"

  def requisitions_query(:lab, query), do: ~p"/lab/requisitions?#{query}"
  def requisitions_query(_portal, query), do: ~p"/pharmacy/requisitions?#{query}"

  def stock_takes(:lab), do: ~p"/lab/stock-takes"
  def stock_takes(_portal), do: ~p"/pharmacy/stock-takes"
  def stock_take(:lab, id), do: ~p"/lab/stock-takes/#{id}"
  def stock_take(_portal, id), do: ~p"/pharmacy/stock-takes/#{id}"
  def stock_takes_new(:lab), do: ~p"/lab/stock-takes/new"
  def stock_takes_new(_portal), do: ~p"/pharmacy/stock-takes/new"

  def disposals(:lab), do: ~p"/lab/disposals"
  def disposals(_portal), do: ~p"/pharmacy/disposals"
  def disposal(:lab, id), do: ~p"/lab/disposals/#{id}"
  def disposal(_portal, id), do: ~p"/pharmacy/disposals/#{id}"

  def disposals_new(:lab, kind), do: ~p"/lab/disposals/new?#{%{kind: kind}}"
  def disposals_new(_portal, kind), do: ~p"/pharmacy/disposals/new?#{%{kind: kind}}"

  def disposals_index(:lab, kind), do: ~p"/lab/disposals?#{%{kind: kind}}"
  def disposals_index(_portal, kind), do: ~p"/pharmacy/disposals?#{%{kind: kind}}"
end
