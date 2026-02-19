defmodule ArtsyNeighborWeb.HomeLive do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Categories
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1, category_card: 1]


  def mount(_params, _session, socket) do
    products = Products.list_products_with_associations()
    featured_products = Enum.take(products, 4)
    favorite_products = Enum.take(products, -4)

    socket =
      socket
      |> assign(
        homekey: "homevalue",
        categories: Categories.list_categories(),
        show_more_categories: false
        )
      |> stream(:featured_products, featured_products)
      |> stream(:favorite_products, favorite_products)

    IO.inspect(socket, label: "HomeLive mount socket")

    {:ok, socket}
  end



  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
    <div class="grid grid-cols-1 gap-8">

    <%!-- Row 1: Hero Section --%>
     <section class="hero">

      <div style={"background-image: url(#{~p"/images/artist-hero.jpg"})"} class="mt-8 w-full h-96 bg-cover bg-center rounded-lg"></div>
      <h1 class="text-4xl font-bold mt-6 text-white">Discover Unique Art from Local Artists</h1>
    </section>

    <%!-- Rows 2-3: Top Categories (3 images in a row) --%>
    <section>
      <h2 class="text-3xl font-bold mb-6">Top Categories</h2>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">

      <.category_card :for={category <- Enum.take(@categories, 3)} category={category} />

      </div>


      <%!-- More categories --%>
      <div :if={@show_more_categories} class="grid grid-cols-1 md:grid-cols-3 gap-6 mt-6">
        <.category_card :for={category <- Enum.slice(@categories, 3, 6)} category={category} />
      </div>

      <div class="flex justify-between items-center mt-6">
        <button :if={length(@categories) > 3}
          phx-click="toggle_more_categories"
          class="text-lg font-medium cursor-pointer hover:underline">
          <%= if @show_more_categories, do: "See less categories ↑", else: "See more categories ➔" %>
        </button>
        <.link navigate={~p"/categories"} class="text-lg font-medium hover:underline">
          See all categories →
        </.link>
      </div>

    </section>

    <%!-- Row 4: Featured Products --%>
    <section>
    <.link navigate={~p"/products"}>
      <h2 class="text-3xl font-bold mb-6">Featured Products</h2>
    </.link>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6" id="featured-products" phx-update="stream">

      <.product_card :for={{dom_id, product} <- @streams.featured_products} product={product} dom_id={dom_id}/>

      </div>
    </section>

    <%!-- Row 5: Our favorites (placeholder) --%>
    <section>
    <.link navigate={~p"/products"}>
      <h2 class="text-3xl font-bold mb-6">Our favorites</h2>
    </.link>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6" id="favorite-products" phx-update="stream">

      <.product_card :for={{dom_id, product} <- @streams.favorite_products} product={product} dom_id={dom_id}/>

      </div>
    </section>

    </div>
    </Layouts.artsy_main>
    """
  end

  def handle_event("toggle_more_categories", _, socket) do
    {:noreply, assign(socket, :show_more_categories, !socket.assigns.show_more_categories)}
  end

  def handle_event(_event, _, socket) do
    {:noreply, socket}
  end



end
