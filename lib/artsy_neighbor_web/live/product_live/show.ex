defmodule ArtsyNeighborWeb.ProductLive.Show do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1, button_artsy: 1]

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    product = Products.get_product(id)

    # Get other products by this artist
    products_by_artist = Products.list_products()
      |> Enum.filter(fn p -> p.artist_name == product.artist_name && p.id != product.id end)
      |> Enum.take(4)

    # Get similar products (same category, different artist)
    similar_products = Products.list_products()
      |> Enum.filter(fn p -> p.category == product.category && p.id != product.id && p.artist_name != product.artist_name end)
      |> Enum.take(4)

    socket =
      socket
        |> assign(:product, product)
        |> assign(:page_title, product.title)
        |> assign(:products_by_artist, products_by_artist)
        |> assign(:similar_products, similar_products)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 py-8 bg-base-100">



        <%!-- Main Section: Two Columns --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-12 items-start">

          <%!-- Left Column: Image Gallery --%>
          <div>
            <%!-- Main Image --%>
            <div class="relative aspect-square w-full rounded-lg overflow-hidden bg-base-300 flex items-center justify-center mb-4 group">
              <img
                src={@product.image}
                alt={@product.title}
                class="w-full h-full object-contain"
              />

              <%!-- Left Arrow --%>
              <button class="absolute left-2 top-1/2 -translate-y-1/2 bg-base-100/80 hover:bg-base-100 text-base-content rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </button>

              <%!-- Right Arrow --%>
              <button class="absolute right-2 top-1/2 -translate-y-1/2 bg-base-100/80 hover:bg-base-100 text-base-content rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
              </button>
            </div>

            <%!-- Thumbnail Gallery --%>
            <div class="grid grid-cols-4 gap-2">
              <%= for _i <- 1..4 do %>
                <div class="aspect-square rounded-lg overflow-hidden bg-base-100 cursor-pointer hover:opacity-75 transition-opacity border-2 border-transparent hover:border-primary flex items-center justify-center">
                  <img
                    src={@product.image}
                    alt={"#{@product.title} - thumbnail"}
                    class="w-full h-full object-contain"
                  />
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Right Column: Product Information --%>
          <div>

          <%!--  Title and Artist --%>
          <div class="mb-5">
            <h1 class="text-4xl font-bold mb-2 text-base-content"><%= @product.title %></h1>
            <p class="text-xl text-base-content/70">by <%= @product.artist_name %></p>
          </div>

          <div > <%!-- Price --%>
            <div class="rounded-lg  mb-5 bg-base-100">
              <%!-- <h2 class="text-sm font-semibold text-base-content/60 mb-2">Price</h2> --%>
              <p class="text-3xl font-bold text-base-content">
                CA$<%= :erlang.float_to_binary(@product.price, decimals: 2) %>
              </p>
            </div>

            <div class="flex flex-col lg:flex-col items-center gap-4 mb-12">
                <.button_artsy variant="primary" size="block" navigate>
                  Buy
                </.button_artsy>

                <!--div class="text-base-content/80">
                  or
                </div-->

                <.button_artsy variant="secondary" size="block" navigate>
                  Message Seller
                </.button_artsy>
            </div>
          </div>

          <div >

            <%!-- Category & Subcategory --%>
            <%!-- <div class="rounded-lg p-6 bg-base-100">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Category</h2>
              <p class="text-lg text-base-content"><%= @product.category %> · <%= @product.subcategory %></p>
            </div> --%>

            <%!-- Materials (placeholder) --%>
            <div class="rounded-lg bg-base-100 space-y-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Materials: oil on canvas.</h2>
            </div>

            <%!-- Dimensions (placeholder) --%>
            <div class="rounded-lg bg-base-100">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Dimensions: 8 1/10 × 29 1/2 in | 46 × 75 cm.</h2>
            </div>


            <%!-- Product Description (placeholder) --%>
            <div class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">About this item</h2>
              <p class="text-base-content/80 leading-relaxed">
                This beautiful <%= String.downcase(@product.category) %> piece showcases exceptional craftsmanship
                and artistic vision. Each detail has been carefully considered to create a unique work of art
                that will enhance any space.
              </p>
            </div>

            <%!-- Delivery Information --%>
            <div class="bg-base-100 mt-6 pt-6 border-t border-base-content/20">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Delivery Information</h2>
              <p class="text-base-content/80 leading-relaxed">
                Pick up at the artist studio. Contact the seller to check about delivery/shipping options and cost.
              </p>
            </div>

            <%!-- Return policy --%>
            <div class="bg-base-100 mt-6 pt-6 border-t border-base-content/20">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Delivery Information</h2>
              <p class="text-base-content/80 leading-relaxed">
                Items in original packaging can be returned if in original condition.
              </p>
            </div>


            </div>


          </div>
        </div>

        <%!-- More by This Artist Section --%>
        <div :if={length(@products_by_artist) > 0} class="mb-12">
          <h2 class="text-2xl font-bold mb-6 text-base-content">More by <%= @product.artist_name %></h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            <.product_card :for={product <- @products_by_artist} product={product} />
          </div>
        </div>

        <%!-- You May Also Like Section --%>
        <div :if={length(@similar_products) > 0} class="mb-12">
          <h2 class="text-2xl font-bold mb-6 text-base-content">You May Also Like</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            <.product_card :for={product <- @similar_products} product={product} />
          </div>
        </div>

      </div>
    </Layouts.artsy_main>
    """
  end

end
