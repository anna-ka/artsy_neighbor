defmodule ArtsyNeighborWeb.ArtistLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1, button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do

    {:ok, assign(socket, return_to: nil, return_label: nil)}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    # IO.inspect(params, label: "params")

    case Artists.get_artist(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Artist not found.")
         |> push_navigate(to: ~p"/artists")}

      artist ->
        collections = Products.list_collections_for_artist(artist.id)

        # For the ribbon: when multiple collections exist, exclude the first product
        # from each collection (already visible as the collection card background).
        ribbon_products =
          if length(collections) > 1 do
            featured_ids =
              collections
              |> Enum.map(fn c -> List.first(c.products) end)
              |> Enum.filter(& &1)
              |> MapSet.new(& &1.id)

            collections
            |> Enum.flat_map(& &1.products)
            |> Enum.reject(fn p -> MapSet.member?(featured_ids, p.id) end)
          else
            []
          end

        artist_images = Enum.sort_by(artist.artist_images, & &1.position)
        total_slides = length(artist_images)

        socket =
          socket
          |> assign(:return_to, Map.get(params, "return_to"))
          |> assign(:return_label, Map.get(params, "return_label"))
          |> assign(:artist, artist)
          |> assign(:page_title, artist.nickname)
          |> assign(:collections, collections)
          |> assign(:ribbon_products, ribbon_products)
          |> assign(:artist_images, artist_images)
          |> assign(:total_slides, total_slides)

        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>

    <%!-- <pre class="text-xs bg-warning p-2"><%= inspect(@return_to) %>
    <%= inspect(@return_label) %>
    </pre> --%>

      <div>
      <.back :if={@return_to && @return_label} navigate={@return_to}>
        {@return_label}
      </.back>
      </div>

      <%!-- Top Section: Artist Profile with bg-base-100 --%>
      <div class="bg-base-100">
        <div class="max-w-7xl mx-auto px-4 py-8">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">

            <%!-- Left Column: Image Carousel --%>
            <div>
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
            <div>

              <%!-- Name and Nickname --%>
              <div class="mb-6">
                <h1 class="text-4xl font-bold mb-2 text-base-content"><%= @artist.nickname %></h1>
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
              <div class="flex flex-col items-center gap-3 mb-8">
                <.button_artsy variant="primary" size="wide">
                  Contact Artist
                </.button_artsy>

                <.button_artsy variant="secondary" size="wide" navigate={~p"/artists/#{@artist}/store"}>
                  View Shop
                </.button_artsy>
              </div>

            </div>
          </div>
        </div>
      </div>

      <%!-- Bottom Section: Works --%>
      <div class="bg-base-200 py-12">
        <div class="max-w-7xl mx-auto px-4">

          <.header>
            Collections by <%= @artist.nickname %>
          </.header>

          <%= if length(@collections) == 1 do %>
            <%!-- Single collection: flat product grid, no heading --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
              <.product_card :for={product <- hd(@collections).products} product={product} />
            </div>
          <% else %>
            <%!-- Multiple collections: one card per collection, like category cards --%>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
              <%= for collection <- @collections do %>
                <% first_img =
                    collection.products
                    |> List.first()
                    |> case do
                      nil -> nil
                      p -> p.product_images |> List.first() |> case do
                        nil -> nil
                        img -> img.path
                      end
                    end %>
                <div
                  style={"background-image: url(#{first_img || "/images/placeholder-category.jpg"})"}
                  class="rounded-lg h-64 flex items-end justify-center pb-10 bg-cover bg-center bg-gray-200">
                  <button class="btn rounded-xl bg-white text-black hover:bg-gray-100 font-semibold">
                    <%= collection.name %>
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>

        </div>
      </div>

      <%!-- Ribbon: more works (excludes featured collection images shown above) --%>
      <div :if={length(@ribbon_products) > 0} class="bg-base-100 py-12">
        <div class="max-w-7xl mx-auto px-4">
          <h2 class="text-2xl font-bold text-base-content mb-6">More Works</h2>
          <div class="relative flex items-center">
            <button
              class="btn btn-circle btn-sm absolute left-0 z-10 shadow"
              onclick="this.nextElementSibling.scrollBy({left: -320, behavior: 'smooth'})">
              ❮
            </button>
            <div class="flex overflow-x-auto scroll-smooth gap-4 py-2 px-10">
              <div :for={product <- @ribbon_products} class="flex-none w-64">
                <.product_card product={product} />
              </div>
            </div>
            <button
              class="btn btn-circle btn-sm absolute right-0 z-10 shadow"
              onclick="this.previousElementSibling.scrollBy({left: 320, behavior: 'smooth'})">
              ❯
            </button>
          </div>
        </div>
      </div>

    </Layouts.artsy_main>
    """
  end

  defp delivery_option_label("pickup"),          do: "Pickup"
  defp delivery_option_label("artist_delivery"), do: "Artist delivers"
  defp delivery_option_label("shipping"),        do: "Shipping"
  defp delivery_option_label("other"),           do: "Other"
  defp delivery_option_label(other),             do: other

end
