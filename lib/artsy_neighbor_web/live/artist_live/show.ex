defmodule ArtsyNeighborWeb.ArtistLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1, button_artsy: 1]

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    artist = Artists.get_artist(id)

    # Get products by this artist
    products_by_artist = Products.list_products()
      |> Enum.filter(fn p -> p.artist_name == artist.nickname end)
      |> Enum.take(8)

    # Prepare gallery images for carousel
    gallery_images = [artist.img2, artist.img3, artist.img4, artist.img5]
      |> Enum.filter(fn x -> x end)
      |> Enum.with_index(2)

    total_slides = length(gallery_images) + 1

    socket =
      socket
        |> assign(:artist, artist)
        |> assign(:page_title, artist.nickname)
        |> assign(:products_by_artist, products_by_artist)
        |> assign(:gallery_images, gallery_images)
        |> assign(:total_slides, total_slides)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>

      <%!-- Top Section: Artist Profile with bg-base-100 --%>
      <div class="bg-base-100">
        <div class="max-w-7xl mx-auto px-4 py-8">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">

            <%!-- Left Column: Image Carousel --%>
            <div>
              <%!-- DaisyUI Carousel --%>
              <div class="carousel carousel-center w-full rounded-lg bg-base-300">
                <%!-- Main Image --%>
                <div id="slide1" class="carousel-item relative w-full aspect-square">
                  <img
                    src={@artist.main_img}
                    alt={@artist.nickname}
                    class="w-full h-full object-cover"
                  />
                  <div class="absolute flex justify-between transform -translate-y-1/2 left-2 right-2 top-1/2">
                    <a href={"#slide#{@total_slides}"} class="btn btn-circle btn-sm opacity-70 hover:opacity-100">❮</a>
                    <a href="#slide2" class="btn btn-circle btn-sm opacity-70 hover:opacity-100">❯</a>
                  </div>
                </div>

                <%!-- Additional Images --%>
                <%= for {img, index} <- @gallery_images do %>
                  <div id={"slide#{index}"} class="carousel-item relative w-full aspect-square">
                    <img
                      src={img}
                      alt={"#{@artist.nickname} - gallery #{index}"}
                      class="w-full h-full object-cover"
                    />
                    <div class="absolute flex justify-between transform -translate-y-1/2 left-2 right-2 top-1/2">
                      <a href={"#slide#{index - 1}"} class="btn btn-circle btn-sm opacity-70 hover:opacity-100">❮</a>
                      <a href={"#slide#{if index < @total_slides, do: index + 1, else: 1}"} class="btn btn-circle btn-sm opacity-70 hover:opacity-100">❯</a>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Carousel Indicators (Dots) --%>
              <div class="flex justify-center w-full py-4 gap-2">
                <a href="#slide1" class="btn btn-xs">1</a>
                <%= for {_img, index} <- @gallery_images do %>
                  <a href={"#slide#{index}"} class="btn btn-xs"><%= index %></a>
                <% end %>
              </div>
            </div>

            <%!-- Right Column: Artist Information --%>
            <div>

              <%!-- Name and Nickname --%>
              <div class="mb-6">
                <h1 class="text-4xl font-bold mb-2 text-base-content"><%= @artist.nickname %></h1>
              </div>

              <%!-- Neighborhood Badge --%>
              <div class="mb-6">
                <div class="badge badge-secondary badge-outline badge-lg">
                  <%= @artist.area_code %>
                </div>
              </div>

              <%!-- Medium Tags --%>
              <div class="mb-6">
                <h2 class="text-sm font-semibold text-base-content/60 mb-2">Mediums</h2>
                <div class="flex flex-wrap gap-2">
                  <%= for medium <- @artist.medium do %>
                    <span class="badge badge-primary">
                      <%= medium %>
                    </span>
                  <% end %>
                </div>
              </div>

              <%!-- Bio --%>
              <div class="rounded-lg bg-base-100 mb-6">
                <h2 class="text-sm font-semibold text-base-content/60 mb-2">About the Artist</h2>
                <p class="text-base-content/80 leading-relaxed">
                  <%= @artist.bio %>
                </p>
              </div>

              <%!-- Contact Buttons --%>
              <div class="flex flex-col items-center gap-3 mb-8">
                <.button_artsy variant="primary" size="wide">
                  Contact Artist
                </.button_artsy>

                <.button_artsy variant="secondary" size="wide">
                  View Shop
                </.button_artsy>
              </div>

            </div>
          </div>
        </div>
      </div>

      <%!-- Bottom Section: Products Gallery with bg-base-200 --%>
      <%!-- <div :if={length(@products_by_artist) > 0} class="bg-red-500 py-12"> --%>
      <div  class="bg-base-200 py-12">
        <div class="max-w-7xl mx-auto px-4">

          <.header>
            Works by <%= @artist.nickname %>
          </.header>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            <.product_card :for={product <- @products_by_artist} product={product} />
          </div>
        </div>
      </div>

    </Layouts.artsy_main>
    """
  end

end
