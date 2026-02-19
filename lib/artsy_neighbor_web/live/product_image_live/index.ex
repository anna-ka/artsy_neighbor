defmodule ArtsyNeighborWeb.ProductImageLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Product images
        <:actions>
          <.button variant="primary" navigate={~p"/product_images/new"}>
            <.icon name="hero-plus" /> New Product image
          </.button>
        </:actions>
      </.header>

      <.table
        id="product_images"
        rows={@streams.product_images}
        row_click={fn {_id, product_image} -> JS.navigate(~p"/product_images/#{product_image}") end}
      >
        <:col :let={{_id, product_image}} label="Path">{product_image.path}</:col>
        <:col :let={{_id, product_image}} label="Position">{product_image.position}</:col>
        <:action :let={{_id, product_image}}>
          <div class="sr-only">
            <.link navigate={~p"/product_images/#{product_image}"}>Show</.link>
          </div>
          <.link navigate={~p"/product_images/#{product_image}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, product_image}}>
          <.link
            phx-click={JS.push("delete", value: %{id: product_image.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Product images")
     |> stream(:product_images, list_product_images())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product_image = Products.get_product_image!(id)
    {:ok, _} = Products.delete_product_image(product_image)

    {:noreply, stream_delete(socket, :product_images, product_image)}
  end

  defp list_product_images() do
    Products.list_product_images()
  end
end
