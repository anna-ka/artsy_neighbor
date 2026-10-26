defmodule ArtsyNeighborWeb.HomeLive do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Categories
  alias Phoenix.LiveView.JS

  import ArtsyNeighborWeb.CustomComponents,
    only: [product_card: 1, collection_card: 1, section_heading: 1, show_more: 1, area_label: 1]

  def mount(_params, _session, socket) do
    products = Products.list_products_with_associations()
    featured_products = Enum.take(products, 4)
    favorite_products = Enum.take(products, -4)

    socket =
      socket
      |> assign(
        hero: hero(),
        categories: Categories.list_popular_categories()
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

      <%!-- Popular categories: the first 4 tiles, the rest opened in place
           by "Show more categories" (no trip to the server) --%>
      <section class="home-section" aria-label="Popular categories">
        <.section_heading>
          Popular categories
          <:link :if={length(@categories) > 4}>
            <.show_more
              id="categories-toggle"
              aria-expanded="false"
              phx-click={toggle_more_categories()}
            >
              <span class="categories-toggle-more">Show more categories ›</span>
              <span class="categories-toggle-fewer" hidden>Show fewer categories ‹</span>
            </.show_more>
          </:link>
        </.section_heading>
        <div id="popular-categories" class="card-grid">
          <.collection_card
            :for={{category, index} <- Enum.with_index(@categories)}
            name={category.name}
            image={category.main_img}
            navigate={~p"/products?#{[category_id: category.id]}"}
            hidden={index >= 4}
          />
        </div>
      </section>

      <div class="grid grid-cols-1 gap-8 mt-16">
        <%!-- Row 4: Featured Products --%>
        <section>
          <h2 class="text-3xl font-bold mb-6">Featured Products</h2>
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
          <h2 class="text-3xl font-bold mb-6">Our favorites</h2>
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

  # "Show more categories" shows the rest of the tiles (all but the
  # first 4) and changes its words to "Show fewer categories"; clicked
  # again, it undoes both.
  defp toggle_more_categories do
    JS.toggle_attribute({"hidden", ""}, to: "#popular-categories > :nth-child(n+5)")
    |> JS.toggle_attribute({"hidden", ""}, to: "#categories-toggle span")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#categories-toggle")
  end

  def handle_event(_event, _, socket) do
    {:noreply, socket}
  end
end
