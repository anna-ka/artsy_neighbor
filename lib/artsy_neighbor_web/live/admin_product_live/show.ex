defmodule ArtsyNeighborWeb.AdminProductLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Products.get_product_with_associations(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Product not found.")
         |> push_navigate(to: ~p"/admin/products")}

      product ->
        images = Products.list_images_for_product(product.id)

        socket =
          socket
          |> assign(:product, product)
          |> assign(:images, images)
          |> assign(:current_image_index, 0)
          |> assign(:page_title, product.title)

        {:noreply, socket}
    end
  end

  @impl true
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 py-8 bg-base-100">

        <%!-- Admin Actions Header --%>
        <.header>
          <%= @product.title %>
          <:actions>
            <.button_artsy navigate={~p"/admin/products"} variant="ghost">
              <.icon name="hero-arrow-left" /> Back
            </.button_artsy>
            <.button_artsy navigate={~p"/admin/products/#{@product}/edit?return_to=show"} variant="primary">
              <.icon name="hero-pencil-square" /> Edit
            </.button_artsy>
          </:actions>
        </.header>

        <%!-- Main Section: Two Columns --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-12 items-start mt-8">

          <%!-- Left Column: Image Gallery --%>
          <div>
            <%!-- Main Image --%>
            <div class="relative aspect-square w-full rounded-lg overflow-hidden bg-base-300 flex items-center justify-center mb-4 group">
              <img
                src={Enum.at(@images, @current_image_index, %{path: "/images/avatar-placeholder.png"}).path}
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

            <%!-- Title, Artist, Category --%>
            <div class="mb-5">
              <h1 class="text-4xl font-bold mb-2 text-base-content"><%= @product.title %></h1>
              <p class="text-xl text-base-content/70">
                by
                <.link navigate={~p"/admin/artists/#{@product.artist}/edit"} class="hover:underline">
                  <%= @product.artist.nickname %>
                </.link>
              </p>
              <p class="text-sm text-base-content/50 mt-1"><%= @product.category.name %></p>
            </div>

            <%!-- Price --%>
            <div class="mb-6">
              <p class="text-3xl font-bold text-base-content">
                CA$<%= Decimal.to_string(@product.price) %>
              </p>
            </div>

            <%!-- Description --%>
            <div class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Description</h2>
              <p class="text-base-content/80 leading-relaxed"><%= @product.descr %></p>
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

            <%!-- Details --%>
            <div class="rounded-lg bg-base-100 mt-6">
              <h2 class="text-sm font-semibold text-base-content/60 mb-2">Details</h2>
              <p class="text-base-content/80 leading-relaxed"><%= @product.details %></p>
            </div>

          </div>
        </div>

      </div>
    </Layouts.artsy_main>
    """
  end
end
