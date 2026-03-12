defmodule ArtsyNeighborWeb.VendorLive.Dashboard do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products

  def mount(_params, _session, socket) do
    case socket.assigns.current_scope.artist do
      nil ->
        {:ok,
         socket
         |> put_flash(:info, "Please create your artist profile to get started.")
         |> redirect(to: ~p"/vendor/profile/new")}

      artist ->
        products = Products.get_products_by_artist(artist.id)

        {:ok,
         assign(socket,
           artist: artist,
           products: products,
           page_title: "Artist Dashboard"
         )}
    end
  end

  defp create_return_to_params() do
    URI.encode_query(return_to: "/vendor", return_label: "Artist Dashboard")
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} variant="vendor">
      <div class="space-y-10">

        <%!-- Header --%>
        <div class="flex items-center justify-between">
          <h1 class="text-3xl font-bold">Artist Dashboard</h1>
          <.link navigate={~p"/vendor/profile/edit" <> "?" <> create_return_to_params()} class="btn btn-ghost btn-xs">
                Edit profile
             </.link>
        </div>

        <%!-- Profile Card --%>
        <div class="card card-side bg-base-200 shadow-sm">
          <figure class="w-32 shrink-0">
            <img
              src={@artist.main_img}
              alt={@artist.nickname}
              class="h-full w-full object-cover"
            />
          </figure>
          <div class="card-body">
            <h2 class="card-title">{@artist.nickname}</h2>
            <p class="text-sm text-base-content/70">{@artist.area_code}</p>
            <p class="text-sm text-base-content/70">{Enum.join(@artist.medium, " · ")}</p>
            <p class="line-clamp-3">{@artist.bio}</p>
            <div class="card-actions mt-2">
            <.link navigate={~p"/artists/#{@artist.id}" <> "?" <> URI.encode_query(return_to: "/vendor", return_label: "Artist Dashboard")} class="btn btn-ghost btn-xs">
                View public profile →
             </.link>
            </div>
          </div>
        </div>

        <%!-- Products --%>
        <div>
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-2xl font-semibold">Your Products</h2>
            <.link navigate={~p"/vendor/products/new"} class="btn btn-primary btn-sm">
              + Add Product
            </.link>
          </div>

          <%= if @products == [] do %>
            <div class="text-center py-16 border border-dashed border-base-300 rounded-box">
              <p class="text-base-content/60 mb-4">You haven't listed any products yet.</p>
              <.link navigate={~p"/vendor/products/new"} class="btn btn-primary">
                Add your first product
              </.link>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>Category</th>
                    <th>Price</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for product <- @products do %>
                    <tr>
                      <td>
                        <div class="flex items-center gap-3">
                          <%= if img = List.first(product.product_images) do %>
                            <img
                              src={img.path}
                              alt={product.title}
                              class="w-12 h-12 object-cover rounded"
                            />
                          <% else %>
                            <div class="w-12 h-12 bg-base-300 rounded flex items-center justify-center text-xs text-base-content/40">
                              No img
                            </div>
                          <% end %>
                          <span class="font-medium">{product.title}</span>
                        </div>
                      </td>
                      <td>{product.category && product.category.name}</td>
                      <td>${product.price}</td>
                      <td>
                        <div class="flex gap-2 justify-end">
                          <.link navigate={~p"/products/#{product.id}" <> "?" <> create_return_to_params()} class="btn btn-ghost btn-xs">
                            View
                          </.link>
                          <.link
                            navigate={~p"/vendor/products/#{product.id}/edit" <> "?" <> create_return_to_params()}
                            class="btn btn-ghost btn-xs"
                          >
                            Edit
                          </.link>
                          <.link
                            phx-click="delete_product"
                            phx-value-id={product.id}
                            data-confirm="Delete this product? This cannot be undone."
                            class="btn btn-ghost btn-xs text-error"
                          >
                            Delete
                          </.link>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

      </div>
    </Layouts.artsy_main>
    """
  end

  def handle_event("delete_product", %{"id" => id}, socket) do
    product = Products.get_product!(String.to_integer(id))

    if product.artist_id == socket.assigns.artist.id do
      {:ok, _} = Products.delete_product(product)
      products = Products.get_products_by_artist(socket.assigns.artist.id)
      {:noreply, assign(socket, :products, products)}
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to delete this product.")}
    end
  end
end
