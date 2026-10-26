defmodule ArtsyNeighborWeb.HomeLive do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Categories
  alias Phoenix.LiveView.JS

  import ArtsyNeighborWeb.CustomComponents,
    only: [product_card: 1, category_card: 1, area_label: 1]

  def mount(_params, _session, socket) do
    products = Products.list_products_with_associations()
    featured_products = Enum.take(products, 4)
    favorite_products = Enum.take(products, -4)

    socket =
      socket
      |> assign(
        hero: hero(),
        categories: Categories.list_categories(),
        show_more_categories: false
      )
      |> stream(:featured_products, featured_products)
      |> stream(:favorite_products, favorite_products)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main
      flash={@flash}
      nav_categories={@nav_categories}
      current_scope={@current_scope}
      has_unread={@has_unread_messages}
      pending_reviews_as_buyer={@pending_reviews_as_buyer}
      pending_reviews_as_vendor={@pending_reviews_as_vendor}
      top_space={false}
    >
      <section class="home-hero" aria-label="Welcome">
        <.hero_picture hero={@hero} />

        <div class="home-hero-words">
          <h1>Greater Victoria is brimming with art.</h1>
          <p>
            Explore the local art scene, support the artistic life of our community,
            or offer your own work to your neighbours.
          </p>
          <div class="home-hero-actions">
            <.button
              id="how-it-works-button"
              aria-expanded="false"
              aria-controls="how-it-works"
              phx-click={toggle_how_it_works()}
            >
              How it works
            </.button>
          </div>
          <ol id="how-it-works" class="how-steps" hidden>
            <li>
              <strong>Find a work you love</strong>
              <span>Browse by category, or visit an artist's page.</span>
            </li>
            <li>
              <strong>Request to buy</strong>
              <span>The artist confirms, and you arrange the details together in messages.</span>
            </li>
            <li>
              <strong>Pick it up from the artist</strong>
              <span>Or have it delivered, if the artist offers delivery.</span>
            </li>
          </ol>
        </div>
      </section>

      <div class="grid grid-cols-1 gap-8 mt-16">
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
            <button
              :if={length(@categories) > 3}
              phx-click="toggle_more_categories"
              class="text-lg font-medium cursor-pointer hover:underline"
            >
              {if @show_more_categories, do: "See less categories ↑", else: "See more categories ➔"}
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
          <div
            class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6"
            id="featured-products"
            phx-update="stream"
          >
            <.product_card
              :for={{dom_id, product} <- @streams.featured_products}
              product={product}
              dom_id={dom_id}
            />
          </div>
        </section>

        <%!-- Row 5: Our favorites (placeholder) --%>
        <section>
          <.link navigate={~p"/products"}>
            <h2 class="text-3xl font-bold mb-6">Our favorites</h2>
          </.link>
          <div
            class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6"
            id="favorite-products"
            phx-update="stream"
          >
            <.product_card
              :for={{dom_id, product} <- @streams.favorite_products}
              product={product}
              dom_id={dom_id}
            />
          </div>
        </section>
      </div>
    </Layouts.artsy_main>
    """
  end

  # The hero picture: linked to the work's page (credit included) while
  # the work is for sale; otherwise the same picture and credit, unlinked.
  # No credit when the work (or its artist) can't be found at all.
  attr :hero, :map, required: true

  defp hero_picture(%{hero: %{work: %{for_sale: true}}} = assigns) do
    ~H"""
    <.link navigate={~p"/products/#{@hero.work.product}"} class="home-hero-art">
      <img src={@hero.image} alt={@hero.alt} />
      <.hero_credit product={@hero.work.product} />
    </.link>
    """
  end

  defp hero_picture(assigns) do
    ~H"""
    <div class="home-hero-art">
      <img src={@hero.image} alt={@hero.alt} />
      <.hero_credit :if={@hero.work && @hero.work.product.artist} product={@hero.work.product} />
    </div>
    """
  end

  attr :product, :map, required: true

  defp hero_credit(assigns) do
    assigns = assign(assigns, :area, area_label(assigns.product.artist.area_code))

    ~H"""
    <span class="home-hero-credit">
      <em>{@product.title}</em> (detail) · {@product.artist.nickname} · {@area}
    </span>
    """
  end

  # The hero setting from config/config.exs, plus the work it shows.
  defp hero do
    setting = Application.fetch_env!(:artsy_neighbor, :home_hero)

    %{
      image: setting[:image],
      alt: setting[:alt],
      work: Products.get_hero_work(setting[:product_id])
    }
  end

  # "How it works" opens and closes the three steps without a trip to
  # the server. JS attribute changes survive LiveView's page updates.
  defp toggle_how_it_works do
    JS.toggle_attribute({"hidden", ""}, to: "#how-it-works")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#how-it-works-button")
  end

  def handle_event("toggle_more_categories", _, socket) do
    {:noreply, assign(socket, :show_more_categories, !socket.assigns.show_more_categories)}
  end

  def handle_event(_event, _, socket) do
    {:noreply, socket}
  end
end
