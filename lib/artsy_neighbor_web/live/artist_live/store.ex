defmodule ArtsyNeighborWeb.ArtistLive.Store do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1, button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do

    #get collections for the artist
    artist = Artists.get_artist(id)
    case artist do
      nil ->
         {:noreply,
         socket
        |> put_flash(:error, "Artist not found.")
        |> push_navigate(to: ~p"/artists")}
      artist ->
        categories = ArtsyNeighbor.Categories.list_categories() |> Enum.map(fn cat -> {cat.name, cat.id} end)
        collections = Products.list_collections_for_artist_no_preloads(artist.id) |> Enum.map(fn c -> {c.name, c.id} end)
        #products = Products.get_products_by_artist(artist.id)
        products = Products.filter_artist_products(artist.id, params)
        artist_images = Enum.sort_by(artist.artist_images, & &1.position)
        total_slides = length(artist_images)

        socket =
          socket
          |> assign(:artist, artist)
          |> assign(:artist_images, artist_images)
          |> assign(:total_slides, total_slides)
          |> assign(:collections, collections)
          |> assign(:products, products)
          |> assign(:categories, categories)
          |> assign(form: to_form(params))

          {:noreply, socket}
      end

  end

  def handle_event("filter", params, socket) do
  IO.inspect(params, label: "Filter form submitted with params")
    # socket =
    #   socket
    #   |> assign(form: to_form(params))
    #   |> stream(:products, Products.filter_products(params), reset: true)


    params =
      params
      |> Map.take(["search", "category_id", "collection_id", "artist", "sort_by"])
      |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

    socket = push_patch(socket, to: ~p"/artists/#{socket.assigns.artist}/store?#{params}")

   {:noreply, socket}
 end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>

    <!-- top section -->
     <section>

     <%!-- <pre class="text-xs bg-warning p-2"><%= inspect(@return_to) %>
    <%= inspect(@return_label) %>
    </pre> --%>

      <%!-- <div>
      <.back :if={@return_to && @return_label} navigate={@return_to}>
        {@return_label}
      </.back>
      </div> --%>

      <%!-- Top Section: Artist Profile with bg-base-100 --%>
      <div class="bg-base-100">
        <div class="max-w-7xl mx-auto px-4 py-8">
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">

            <%!-- Left Column: Image Carousel --%>
             <div class="lg:col-span-1">
              <%!-- DaisyUI Carousel --%>
              <div class="carousel carousel-center w-full rounded-lg bg-base-300">
                <%= for {img, index} <- Enum.with_index(@artist_images, 1) do %>
                  <div id={"slide#{index}"} class="carousel-item relative w-full aspect-square">
                    <img
                      src={img.path}
                      alt={"#{@artist.nickname} - image #{index}"}
                      class="w-full h-full object-cover"
                    />
                    <div class="absolute flex justify-between transform -translate-y-1/2 left-2 right-2 top-1/2">
                      <a href={"#slide#{if index == 1, do: @total_slides, else: index - 1}"} class="btn btn-circle btn-sm opacity-70 hover:opacity-100">❮</a>
                      <a href={"#slide#{if index == @total_slides, do: 1, else: index + 1}"} class="btn btn-circle btn-sm opacity-70 hover:opacity-100">❯</a>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Carousel Indicators (Dots) --%>
              <div class="flex justify-center w-full py-4 gap-2">
                <%= for {_img, index} <- Enum.with_index(@artist_images, 1) do %>
                  <a href={"#slide#{index}"} class="btn btn-xs"><%= index %></a>
                <% end %>
              </div>
            </div>

            <%!-- Right Column: Artist Information --%>
             <div class="lg:col-span-2">

              <%!-- Name and Nickname --%>
              <div class="mb-6">
                <h1 class="text-4xl font-bold mb-2 text-base-content"><%= @artist.nickname %> Store</h1>
              </div>

              <%!-- Announcement Banner --%>
              <div :if={@artist.announcement_active && @artist.announcement not in [nil, ""]}
                   class="alert alert-info mb-6 text-sm">
                <%= @artist.announcement %>
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

              <%!-- Delivery Options --%>
              <div :if={@artist.delivery_options != []} class="mb-6">
                <h2 class="text-sm font-semibold text-base-content/60 mb-2">Delivery Options</h2>
                <ul class="space-y-1">
                  <%= for option <- @artist.delivery_options do %>
                    <li class="text-sm text-base-content/80">
                      <span class="font-medium"><%= delivery_option_label(option) %></span>
                      <%= if (get_in(@artist.delivery_info, [option]) || "") != "" do %>
                        <span class="text-base-content/60"> — <%= get_in(@artist.delivery_info, [option]) %></span>
                      <% end %>
                    </li>
                  <% end %>
                </ul>
              </div>

              <%!-- Social Media / Online Presence --%>
              <div :if={@artist.homepage || @artist.instagram || @artist.facebook} class="mb-6">
                <h2 class="text-sm font-semibold text-base-content/60 mb-2">Online</h2>
                <div class="flex flex-wrap gap-3">
                  <a :if={@artist.homepage} href={@artist.homepage} target="_blank" rel="noopener" class="btn btn-ghost btn-sm">
                    🌐 Website
                  </a>
                  <a :if={@artist.instagram} href={@artist.instagram} target="_blank" rel="noopener" class="btn btn-ghost btn-sm">
                    📷 Instagram
                  </a>
                  <a :if={@artist.facebook} href={@artist.facebook} target="_blank" rel="noopener" class="btn btn-ghost btn-sm">
                    📘 Facebook
                  </a>
                </div>
              </div>

              <%!-- Contact Buttons --%>
              <div :if={nil} class="flex flex-col items-center gap-3 mb-8">
                <.button_artsy variant="primary" size="wide">
                  Contact Artist
                </.button_artsy>

                <.button_artsy :if={nil}  variant="secondary" size="wide" navigate={~p"/artists/#{@artist}/store"}>
                  View Shop
                </.button_artsy>
              </div>

            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Bottom Section with products -->


    <section class="my-6"> <!-- filter form-->
      <%!-- FCC FORM --%>
      <.filter_form form={@form} categories={@categories} collections={@collections} artist_id={@artist.id}/>
    </section> <!-- filter form-->


    <section>
      <div class="bg-base-200 py-12"> <%!-- Bottom Section: Works --%>

       <%!--  flat product grid, no heading --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
              <.product_card :for={product <- @products} product={product} />
            </div>

      </div> <%!-- Bottom Section: Works --%>

    </section>
    </Layouts.artsy_main>
    """
  end


  @doc """
  Renders the product filtering form. Expect "form" in the assigns.

  """

  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true
  attr :collections, :list, required: true
  attr :artist_id, :integer, required: true

 def filter_form(assigns) do
  ~H"""
    <.form for={@form} id="filter-form" phx-change="filter" phx-submit="filter">
        <div class="flex flex-wrap gap-4 items-end">

          <%!-- Search --%>
          <div class="flex-1 min-w-48">
            <.input field={@form[:search]}
              type="text"
              label="Search"
              placeholder="Search products..."
              autocomplete="off"
              phx-debounce="1000"/>
          </div>

          <%!-- Filter by Category --%>
          <div class="min-w-48">
            <.input field={@form[:category_id]} type="select" label="Category" prompt="All categories" options={@categories} />
          </div>

          <%!-- Filter by Artist --%>
          <div class="min-w-48">
            <.input field={@form[:collection_id]} type="select" label="Collection" prompt="All collections by artist" options={@collections} />
          </div>

          <%!-- Sort By --%>
          <div class="min-w-48">
            <.input
              field={@form[:sort_by]}
              type="select"
              label="Sort by"
              prompt="Default"
              options={[
                {"Price: Low to High", "price_asc"},
                {"Price: High to Low", "price_desc"},
                {"Collection", "collection"},
                {"Category", "category"}
              ]}
            />
          </div>

          <%!-- Reset --%>
          <div>
            <.link patch={~p"/artists/#{@artist_id}/store"} class="btn btn-ghost">Clear</.link>

          </div>

        </div>
      </.form>
  """
 end

  defp delivery_option_label("pickup"),          do: "Pickup at the artist's studio"
  defp delivery_option_label("artist_delivery"), do: "Artist delivers"
  defp delivery_option_label("shipping"),        do: "Shipping"
  defp delivery_option_label("other"),           do: "Other"
  defp delivery_option_label(other),             do: other

end
