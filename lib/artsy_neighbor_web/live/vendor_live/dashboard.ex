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
        collections = Products.list_collections_for_artist(artist.id)

        {:ok,
         assign(socket,
           artist: artist,
           products: products,
           collections: collections,
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
            <div class="flex gap-2">
              <div class="tooltip tooltip-left" data-tip="Create a collection of products — useful for when you have many diverse works">
                <.link navigate={~p"/vendor/collections/new"} class="btn btn-secondary btn-sm">
                  + Add Collection
                </.link>
              </div>
              <.link navigate={~p"/vendor/products/new"} class="btn btn-primary btn-sm">
                + Add Product
              </.link>
            </div>
          </div>

          <%= if @products == [] do %>
            <div class="text-center py-16 border border-dashed border-base-300 rounded-box">
              <p class="text-base-content/60 mb-4">You haven't listed any products yet.</p>
              <.link navigate={~p"/vendor/products/new"} class="btn btn-primary">
                Add your first product
              </.link>
            </div>
          <% else %>
            <%!-- One section per collection --%>
            <div class="space-y-8">
              <div :for={{collection, index} <- Enum.with_index(@collections)}>

                <%!-- Collection heading with product count + collection actions --%>
                <div class="flex items-center gap-4 border-b border-base-300 pb-2">
                  <%!-- Up/down arrows to reorder collections --%>
                  <div class="flex flex-col tooltip tooltip-right" data-tip="Reorder collections">
                    <button
                      :if={index > 0}
                      type="button"
                      phx-click="move_collection_up"
                      phx-value-collectionid={collection.id}
                      class="btn btn-ghost btn-xs"
                    >↑</button>
                    <button
                      :if={index < length(@collections) - 1}
                      type="button"
                      phx-click="move_collection_down"
                      phx-value-collectionid={collection.id}
                      class="btn btn-ghost btn-xs"
                    >↓</button>
                  </div>

                  <h3 class="text-lg font-semibold">
                    {collection.name}
                    <span class="text-sm font-normal text-base-content/60 ml-2">
                      ({length(collection.products)})
                    </span>
                  </h3>
                  <%!-- Collection actions — styled as plain text links to distinguish
                       them from the product row buttons (btn btn-ghost btn-xs) below --%>
                  <div class="flex gap-3">
                    <.link
                      navigate={~p"/vendor/collections/#{collection.id}/edit"}
                      class="text-xs text-secondary hover:underline"
                    >
                      Edit collection
                    </.link>
                    <%!-- "All Works" is the protected default — disallow deletion --%>
                    <.link
                      :if={collection.name != "All Works"}
                      phx-click="delete_collection"
                      phx-value-id={collection.id}
                      data-confirm={"Delete \"#{collection.name}\"? Its products will be moved to your All Works collection."}
                      class="text-xs text-warning hover:underline"
                    >
                      Delete collection
                    </.link>
                  </div>
                </div>

                <%!-- Products table for this collection --%>
                <div class="overflow-x-auto">
                  <table class="table table-zebra">
                    <thead>
                      <tr>
                        <th></th>
                        <th>Product</th>
                        <th>Category</th>
                        <th>Price</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={{product, product_index} <- Enum.with_index(collection.products)}>
                        <%!-- Arrow column — reorder products within this collection --%>
                        <td class="w-8">
                          <div class="flex flex-col tooltip tooltip-right" data-tip="Reorder products">
                            <button
                              :if={product_index > 0}
                              type="button"
                              phx-click="move_product_up"
                              phx-value-productid={product.id}
                              phx-value-collectionid={collection.id}
                              class="btn btn-ghost btn-xs"
                            >↑</button>
                            <button
                              :if={product_index < length(collection.products) - 1}
                              type="button"
                              phx-click="move_product_down"
                              phx-value-productid={product.id}
                              phx-value-collectionid={collection.id}
                              class="btn btn-ghost btn-xs"
                            >↓</button>
                          </div>
                        </td>
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
                    </tbody>
                  </table>
                </div>

              </div>
            </div>
          <% end %>
        </div>

      </div>
    </Layouts.artsy_main>
    """
  end

  def handle_event("move_product_up", %{"productid" => pid, "collectionid" => cid}, socket) do
    product_id = String.to_integer(pid)
    coll_id = String.to_integer(cid)
    collection = Enum.find(socket.assigns.collections, fn c -> c.id == coll_id end)
    products = collection.products
    index = Enum.find_index(products, fn p -> p.id == product_id end)

    if index && index > 0 do
      Products.swap_product_positions(Enum.at(products, index), Enum.at(products, index - 1))
      {:noreply, assign(socket, collections: Products.list_collections_for_artist(socket.assigns.artist.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_product_down", %{"productid" => pid, "collectionid" => cid}, socket) do
    product_id = String.to_integer(pid)
    coll_id = String.to_integer(cid)
    collection = Enum.find(socket.assigns.collections, fn c -> c.id == coll_id end)
    products = collection.products
    index = Enum.find_index(products, fn p -> p.id == product_id end)

    if index && index < length(products) - 1 do
      Products.swap_product_positions(Enum.at(products, index), Enum.at(products, index + 1))
      {:noreply, assign(socket, collections: Products.list_collections_for_artist(socket.assigns.artist.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_collection_up", %{"collectionid" => id}, socket) do
    id = String.to_integer(id)
    collections = socket.assigns.collections
    index = Enum.find_index(collections, fn c -> c.id == id end)

    if index && index > 0 do
      Products.swap_collection_positions(Enum.at(collections, index), Enum.at(collections, index - 1))
      {:noreply, assign(socket, collections: Products.list_collections_for_artist(socket.assigns.artist.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("move_collection_down", %{"collectionid" => id}, socket) do
    id = String.to_integer(id)
    collections = socket.assigns.collections
    index = Enum.find_index(collections, fn c -> c.id == id end)

    if index && index < length(collections) - 1 do
      Products.swap_collection_positions(Enum.at(collections, index), Enum.at(collections, index + 1))
      {:noreply, assign(socket, collections: Products.list_collections_for_artist(socket.assigns.artist.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_collection", %{"id" => id}, socket) do
    collection = Products.get_collection!(String.to_integer(id))

    if collection.artist_id == socket.assigns.artist.id do
      {:ok, _} = Products.delete_collection(collection)
      collections = Products.list_collections_for_artist(socket.assigns.artist.id)
      {:noreply,
       socket
       |> put_flash(:info, "Collection deleted. Its products have been moved to All Works.")
       |> assign(collections: collections)}
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to delete this collection.")}
    end
  end

  def handle_event("delete_product", %{"id" => id}, socket) do
    product = Products.get_product!(String.to_integer(id))

    if product.artist_id == socket.assigns.artist.id do
      {:ok, _} = Products.delete_product(product)
      products = Products.get_products_by_artist(socket.assigns.artist.id)
      collections = Products.list_collections_for_artist(socket.assigns.artist.id)
      {:noreply, assign(socket, products: products, collections: collections)}
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to delete this product.")}
    end
  end
end
