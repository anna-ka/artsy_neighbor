defmodule ArtsyNeighborWeb.ProductImageLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Product image {@product_image.id}
        <:subtitle>This is a product_image record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/product_images"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/product_images/#{@product_image}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit product_image
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Path">{@product_image.path}</:item>
        <:item title="Position">{@product_image.position}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Product image")
     |> assign(:product_image, Products.get_product_image!(id))}
  end
end
