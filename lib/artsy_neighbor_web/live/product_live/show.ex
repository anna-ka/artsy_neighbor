defmodule ArtsyNeighborWeb.ProductLive.Show do
  @moduledoc """
  A work's public page, `/products/:id`: the whole work (never cropped)
  with its other photos on the left, and its details, price and the
  "Request to buy" / "Send message" buttons on the right. Below them:
  more by the same artist and similar works by others.

  Only works that are for sale (see `Products.only_available/1`) have a
  page; any other address goes back to `/products` with "Product not
  found".
  """
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Orders

  import ArtsyNeighborWeb.CustomComponents,
    only: [
      product_card: 1,
      report_link: 1,
      area_label: 1,
      artwork_size: 1,
      exact_price: 1
    ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, return_to: nil, return_label: nil, photo_index: 0)}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
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
          |> assign(:own_work, own_work?(product, socket))
          |> assign(:images, images)
          |> assign(:photo_index, 0)
          |> assign(:page_title, product.title)
          |> assign(:products_by_artist, products_by_artist)
          |> assign(:similar_products, similar_products)

        {:noreply, socket}
    end
  end

  # True when the logged-in vendor is looking at one of their own works.
  # They can't buy from or message themselves, so both buttons are
  # shown to them but disabled.
  defp own_work?(product, socket) do
    scope = socket.assigns.current_scope
    viewer_artist = scope && scope.artist

    viewer_artist != nil && viewer_artist.id == product.artist_id
  end

  # An arrow on the photo or a thumbnail was pressed. The index wraps
  # around, so "next" on the last photo shows the first one.
  def handle_event("show_photo", %{"index" => index}, socket) do
    photo_count = length(socket.assigns.images)

    photo_index =
      case Integer.parse(index) do
        {number, ""} when photo_count > 0 -> Integer.mod(number, photo_count)
        _ -> 0
      end

    {:noreply, assign(socket, :photo_index, photo_index)}
  end

  # "Send message" and "Request to buy": the artist's own buttons are
  # disabled; these guard against a click that gets through anyway.
  def handle_event("message_artist", _params, %{assigns: %{own_work: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("request_to_buy", _params, %{assigns: %{own_work: true}} = socket) do
    {:noreply, socket}
  end

  # "Send message": finds or creates a conversation between the current
  # user (buyer) and the artist (seller), then opens it.
  def handle_event("message_artist", _params, socket) do
    artist_id = socket.assigns.product.artist_id
    buyer_id = socket.assigns.current_scope.user.id
    {:ok, conversation} = Conversations.find_or_create_conversation(buyer_id, artist_id)
    {:noreply, push_navigate(socket, to: ~p"/messages/#{conversation.id}")}
  end

  # "Request to buy": adds the work to the buyer's open order with this
  # artist (starting one if there is none), then opens the conversation,
  # where the two of them arrange the rest.
  def handle_event("request_to_buy", _params, socket) do
    product = socket.assigns.product
    buyer = socket.assigns.current_scope.user
    artist = product.artist
    {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

    result =
      case Orders.get_open_order_for_conversation(conversation.id) do
        nil ->
          Orders.create_order(conversation, buyer, artist, [%{product: product, quantity: 1}])

        order ->
          already_in_order? =
            Enum.any?(order.items, fn item -> item.product_id == product.id end)

          if product.unique_work && already_in_order? do
            {:error, :unique_work_already_in_order}
          else
            Orders.add_item_to_order(order, product, :buyer)
          end
      end

    case result do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: ~p"/messages/#{conversation.id}")}

      {:error, :unique_work_already_in_order} ->
        {:noreply,
         put_flash(socket, :error, "This is a unique work and it is already in your order.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
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
      <%!-- "Back to ...", as on the artist page: only when the page was
           opened with return_to and return_label. --%>
      <.link :if={@return_to && @return_label} navigate={@return_to} class="back-under-menu">
        ← {@return_label}
      </.link>

      <%!-- Top: the work left, its details right (one column on phones) --%>
      <div class="product-top">
        <.work_photos product={@product} images={@images} photo_index={@photo_index} />

        <div class="product-info">
          <h1>{@product.title}</h1>
          <div class="product-by">
            by <.link navigate={~p"/artists/#{@product.artist}"}>{@product.artist.nickname}</.link>
          </div>
          <div class="artist-area">{area_label(@product.artist.area_code)}</div>

          <ul class="product-facts">
            <li :if={present?(@product.materials)}>{@product.materials}</li>
            <li :if={artwork_size(@product)}>{artwork_size(@product)}</li>
            <li :if={@product.unique_work} class="product-unique">
              <%!-- A four-pointed star, from the mockup --%>
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.6"
                aria-hidden="true"
              >
                <path d="M12 3l2.2 6.3L21 12l-6.8 2.7L12 21l-2.2-6.3L3 12l6.8-2.7z" />
              </svg>
              Unique work — one of a kind
            </li>
          </ul>

          <div class="product-price">{exact_price(@product.price)}</div>

          <.buy_buttons current_scope={@current_scope} own_work={@own_work} />

          <%!-- The old sections, until step 2 of the product page
               (docs/plans/2026-10-15-theme-and-components.md) --%>
          <div>
            <div class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">About this item</h2>
              <p class="text-base-content/80 leading-relaxed">
                {@product.descr}
              </p>
            </div>

            <div class="rounded-lg bg-base-100 space-y-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Details</h2>
              <p class="text-base-content/80 leading-relaxed">
                {@product.details}
              </p>
            </div>

            <div class="bg-base-100 mt-6 pt-6 border-t border-base-content/20">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Delivery Information</h2>
              <p class="text-base-content/80 leading-relaxed">
                Pick up at the artist studio. Contact the seller to check about delivery/shipping options and cost.
              </p>
            </div>

            <div class="bg-base-100 mt-6 pt-6 border-t border-base-content/20">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Delivery Information</h2>
              <p class="text-base-content/80 leading-relaxed">
                Items in original packaging can be returned if in original condition.
              </p>
            </div>
          </div>
        </div>
      </div>

      <div class="py-8 bg-base-100">
        <%!-- More by This Artist Section --%>
        <div :if={length(@products_by_artist) > 0} class="mb-12">
          <h2 class="text-2xl font-bold mb-6 text-base-content">
            More by {@product.artist.nickname}
          </h2>
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

      <div class="product-report">
        <.report_link
          :if={@current_scope && @current_scope.user}
          subject="product"
          id={@product.id}
          return_to={~p"/products/#{@product.id}"}
          return_label="Product page"
        >
          Report a concern about this listing
        </.report_link>
      </div>
    </Layouts.artsy_main>
    """
  end

  # The work's photos, one at a time: the whole photo, never cropped,
  # inside an area of fixed height (so the text beside it never jumps
  # when switching photos). With more than one photo: small see-through
  # arrows on the photo's own edges and square thumbnails under it.
  # No photos: the placeholder picture.
  attr :product, :map, required: true
  attr :images, :list, required: true
  attr :photo_index, :integer, required: true

  defp work_photos(assigns) do
    assigns = assign(assigns, :photo_count, length(assigns.images))

    ~H"""
    <div class="work-photos">
      <div class="work-view">
        <%!-- The frame is exactly as big as the photo, so the arrows
             (placed inside it) sit on the photo's own edges. --%>
        <div
          class="work-frame"
          aria-roledescription="carousel"
          aria-label={"Photos of #{@product.title}"}
        >
          <img
            :if={@photo_count == 0}
            src="/images/placeholder-product.jpg"
            alt={"#{@product.title} (no photo yet)"}
          />
          <img
            :for={{image, index} <- Enum.with_index(@images)}
            src={image.path}
            alt={"#{@product.title}, photo #{index + 1} of #{@photo_count}"}
            hidden={index != @photo_index}
          />

          <%= if @photo_count > 1 do %>
            <button
              type="button"
              class="carousel-arrow prev"
              phx-click="show_photo"
              phx-value-index={@photo_index - 1}
              aria-label="Previous photo"
            >
              ‹
            </button>
            <button
              type="button"
              class="carousel-arrow next"
              phx-click="show_photo"
              phx-value-index={@photo_index + 1}
              aria-label="Next photo"
            >
              ›
            </button>
          <% end %>
        </div>
      </div>

      <div :if={@photo_count > 1} class="work-thumbs">
        <button
          :for={{image, index} <- Enum.with_index(@images)}
          type="button"
          class={index == @photo_index && "current"}
          phx-click="show_photo"
          phx-value-index={index}
          aria-label={"Show photo #{index + 1}"}
          aria-pressed={to_string(index == @photo_index)}
        >
          <img src={image.path} alt="" />
        </button>
      </div>
    </div>
    """
  end

  # The two main buttons, of equal width. Logged out: "Log in to buy",
  # with a line about creating an account under it. The artist sees
  # both buttons on their own works, disabled.
  attr :current_scope, :any, required: true
  attr :own_work, :boolean, required: true

  defp buy_buttons(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope.user do %>
      <div class="product-actions">
        <.button variant="main" phx-click="request_to_buy" disabled={@own_work}>
          Request to buy
        </.button>
        <.button phx-click="message_artist" disabled={@own_work}>
          Send message
        </.button>
      </div>
    <% else %>
      <div class="product-actions">
        <.button variant="main" navigate={~p"/users/log-in"}>Log in to buy</.button>
      </div>
      <p class="product-small-note">
        New here? <.link navigate={~p"/users/register"}>Create an account</.link>
        — it only takes a minute.
      </p>
    <% end %>
    """
  end

  defp present?(nil), do: false
  defp present?(text), do: String.trim(text) != ""
end
