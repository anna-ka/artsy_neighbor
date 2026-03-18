defmodule ArtsyNeighborWeb.VendorLive.CollectionForm do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.ProductCollection

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    artist = socket.assigns.current_scope.artist
    collection = %ProductCollection{artist_id: artist.id, position: next_collection_position(artist.id)}

    socket
    |> assign(:page_title, "Create Collection")
    |> assign(:collection, collection)
    |> assign(:form, to_form(Products.change_collection(collection)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    artist = socket.assigns.current_scope.artist
    collection = Products.get_collection!(id)

    if collection.artist_id != artist.id do
      socket
      |> put_flash(:error, "You are not authorized to edit this collection.")
      |> redirect(to: ~p"/vendor")
    else
      socket
      |> assign(:page_title, "Edit Collection")
      |> assign(:collection, collection)
      |> assign(:form, to_form(Products.change_collection(collection)))
    end
  end

  @impl true
  def handle_event("validate", %{"product_collection" => params}, socket) do
    changeset = Products.change_collection(socket.assigns.collection, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"product_collection" => params}, socket) do
    save_collection(socket, socket.assigns.live_action, params)
  end

  defp save_collection(socket, :new, params) do
    artist = socket.assigns.current_scope.artist

    params =
      params
      |> Map.put("artist_id", artist.id)
      |> Map.put("position", next_collection_position(artist.id))

    case Products.create_collection(params) do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Collection created successfully.")
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_collection(socket, :edit, params) do
    case Products.update_collection(socket.assigns.collection, params) do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Collection updated successfully.")
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Returns max(position) + 1 for this artist's collections,
  # or 1 if the artist has no collections yet.
  # Using max rather than count avoids collisions after deletions.
  defp next_collection_position(artist_id) do
    collections = Products.list_collections_for_artist(artist_id)
    max_pos = collections |> Enum.map(fn c -> c.position end) |> Enum.max(fn -> 0 end)
    max_pos + 1
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} variant="vendor">
      <div class="w-full px-8 py-8">

        <.back navigate={~p"/vendor"}>
          Artist Dashboard
        </.back>

        <.header>
          <%= @page_title %>
        </.header>

        <.form for={@form} id="collection-form" phx-change="validate" phx-submit="save">

          <.input
            field={@form[:name]}
            type="text"
            label="Collection name"
            placeholder="e.g. Watercolours, Large Format, Holiday Series"
            phx-debounce="blur"
          />

          <.button_artsy variant="primary" disable_with="Saving...">
            Save Collection
          </.button_artsy>

        </.form>

        <.back navigate={~p"/vendor"}>
          Artist Dashboard
        </.back>

      </div>
    </Layouts.artsy_main>
    """
  end
end
