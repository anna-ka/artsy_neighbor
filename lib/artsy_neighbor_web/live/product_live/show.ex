defmodule ArtsyNeighborWeb.ProductLive.Show do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Conversations
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1, button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, return_to: nil, return_label: nil)}
  end

  def handle_params(%{"id" => id}=params, _uri, socket) do
    case Products.get_product_with_associations(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Product not found.")
         |> push_navigate(to: ~p"/products")}

      product ->
        images = Products.list_images_for_product(product.id)

        products_by_artist =
          Products.get_products_by_artist(product.artist_id)
          |> Enum.reject(fn p -> p.id == product.id end)
          |> Enum.take(4)

        similar_products =
          Products.get_products_by_category(product.category_id)
          |> Enum.reject(fn p -> p.id == product.id || p.artist_id == product.artist_id end)
          |> Enum.take(4)

        socket =
          socket
          |> assign(:return_to, Map.get(params, "return_to"))
          |> assign(:return_label, Map.get(params, "return_label"))
          |> assign(:product, product)
          |> assign(:images, images)
          |> assign(:current_image_index, 0)
          |> assign(:page_title, product.title)
          |> assign(:products_by_artist, products_by_artist)
          |> assign(:similar_products, similar_products)

        {:noreply, socket}
    end
  end

  def handle_event("prev_image", _, socket) do
    count = length(socket.assigns.images)
    new_index = rem(socket.assigns.current_image_index - 1 + count, count)
    {:noreply, assign(socket, :current_image_index, new_index)}
  end

  def handle_event("next_image", _, socket) do
    count = length(socket.assigns.images)
    new_index = rem(socket.assigns.current_image_index + 1, count)
    {:noreply, assign(socket, :current_image_index, new_index)}
  end

  def handle_event("select_image", %{"index" => index}, socket) do
    {:noreply, assign(socket, :current_image_index, String.to_integer(index))}
  end

  @doc """
    Handles the "Message Seller" button click.
    Finds or creates a conversation between the current user (buyer) and the artist (seller), then navigates to that conversation's page.
  """
  def handle_event("message_seller", _params, socket) do
    artist_id = socket.assigns.product.artist_id
    buyer_id = socket.assigns.current_scope.user.id
    {:ok, conversation} = Conversations.find_or_create_conversation(buyer_id, artist_id)
    {:noreply, push_navigate(socket, to: ~p"/messages/#{conversation.id}")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread_messages}>

      <div>
        <.back :if={@return_to && @return_label} navigate={@return_to}>
          {@return_label}
        </.back>
      </div>

      <div class="max-w-7xl mx-auto px-4 py-8 bg-base-100">



        <%!-- Main Section: Two Columns --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-12 items-start">

          <%!-- Left Column: Image Gallery --%>
          <div>
            <%!-- Main Image --%>
            <div class="relative aspect-square w-full rounded-lg overflow-hidden bg-base-300 flex items-center justify-center mb-4 group">
              <img
                src={Enum.at(@images, @current_image_index, %{path: "/images/placeholder-product.jpg"}).path}
                alt={@product.title}
                class="w-full h-full object-contain"
              />

              <%!-- Left Arrow --%>
              <button
                :if={length(@images) > 1}
                phx-click="prev_image"
                class="absolute left-2 top-1/2 -translate-y-1/2 bg-base-100/80 hover:bg-base-100 text-base-content rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
              </button>

              <%!-- Right Arrow --%>
              <button
                :if={length(@images) > 1}
                phx-click="next_image"
                class="absolute right-2 top-1/2 -translate-y-1/2 bg-base-100/80 hover:bg-base-100 text-base-content rounded-full p-2 opacity-0 group-hover:opacity-100 transition-opacity">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
              </button>
            </div>

            <%!-- Thumbnail Gallery --%>
            <div class="grid grid-cols-4 gap-2">
              <%= for {image, idx} <- Enum.with_index(@images) do %>
                <div
                  phx-click="select_image"
                  phx-value-index={idx}
                  class={["aspect-square rounded-lg overflow-hidden bg-base-100 cursor-pointer hover:opacity-75 transition-opacity border-2 flex items-center justify-center",
                    if(idx == @current_image_index, do: "border-primary", else: "border-transparent hover:border-primary")
                  ]}>
                  <img
                    src={image.path}
                    alt={"#{@product.title} - thumbnail #{idx + 1}"}
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
            <p class="text-xl text-base-content/70">by <%= @product.artist.nickname %></p>
            <div :if={@product.unique_work} class="flex items-center gap-1 mt-2 text-sm text-base-content/60">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-secondary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
              </svg>
              <span>Unique work — one of a kind</span>
            </div>
          </div>

          <div > <%!-- Price --%>
            <div class="rounded-lg  mb-5 bg-base-100">
              <%!-- <h2 class="text-sm font-semibold text-base-content/60 mb-2">Price</h2> --%>
              <p class="text-3xl font-bold text-base-content">
                CA$<%= Decimal.to_string(@product.price) %>
              </p>
            </div>

            <%= if @current_scope.user do %>
              <div class="flex flex-col lg:flex-col items-center gap-4 mb-12">
                <.button_artsy variant="primary" size="block" navigate>
                  Buy
                </.button_artsy>

                <!--div class="text-base-content/80">
                  or
                </div-->

                <.button_artsy variant="secondary" size="block" phx-click="message_seller">
                  Message Seller
                </.button_artsy>
            </div>

            <% else %>
            <div class="flex flex-col lg:flex-col items-center gap-4 mb-12">
               <.button_artsy variant="primary" size="block" navigate={~p"/users/log-in"}>
                  Register to Buy or to Message Seller
                </.button_artsy>
            </div>

            <% end %>



          </div>

          <div >

            <%!-- Category & Subcategory --%>
            <%!-- <div class="rounded-lg p-6 bg-base-100">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Category</h2>
              <p class="text-lg text-base-content"><%= @product.category %> · <%= @product.subcategory %></p>
            </div> --%>




            <%!-- Product Description (placeholder) --%>
            <div class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">About this item</h2>
              <p class="text-base-content/80 leading-relaxed">
                <%= @product.descr %>
              </p>
            </div>

            <%!-- Dimensions --%>
            <div :if={@product.width || @product.length || @product.height} class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Dimensions</h2>
              <p class="text-base-content/80">
                <%= [
                  @product.width  && "W: #{Decimal.to_string(@product.width)} #{@product.units}",
                  @product.length && "L: #{Decimal.to_string(@product.length)} #{@product.units}",
                  @product.height && "H: #{Decimal.to_string(@product.height)} #{@product.units}"
                ] |> Enum.filter(& &1) |> Enum.join("; ") %>
              </p>
            </div>

            <%!-- Materials --%>
            <div :if={@product.materials} class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Materials</h2>
              <p class="text-base-content/80"><%= @product.materials %></p>
            </div>

            <%!-- Details (placeholder) --%>
            <div class="rounded-lg bg-base-100 space-y-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Details</h2>
              <p class="text-base-content/80 leading-relaxed">
                <%= @product.details %>
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
          <h2 class="text-2xl font-bold mb-6 text-base-content">More by <%= @product.artist.nickname %></h2>
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
