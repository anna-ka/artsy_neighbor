defmodule ArtsyNeighborWeb.ProductOptionLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Product option {@product_option.id}
        <:subtitle>This is a product_option record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/product_options"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/product_options/#{@product_option}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit product_option
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@product_option.name}</:item>
        <:item title="Descr">{@product_option.descr}</:item>
        <:item title="Values">{@product_option.values}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Product option")
     |> assign(:product_option, Products.get_product_option!(id))}
  end
end
