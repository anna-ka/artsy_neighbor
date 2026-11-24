defmodule ArtsyNeighborWeb.VendorLive.CollectionForm do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.ProductCollection

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]
  import ArtsyNeighborWeb.Params, only: [parse_id: 1]

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    artist = socket.assigns.current_scope.artist

    collection = %ProductCollection{artist_id: artist.id}

    socket
    |> assign(:page_title, "Create Collection")
    |> assign(:collection, collection)
    |> assign(:form, to_form(Products.change_collection(collection)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    artist = socket.assigns.current_scope.artist

    collection =
      case parse_id(id) do
        nil -> nil
        parsed -> Products.get_collection(parsed)
      end

    cond do
      # Deleted meanwhile (e.g. in another tab), or a made-up address.
      is_nil(collection) ->
        socket
        |> put_flash(:error, "That collection doesn't exist any more.")
        |> redirect(to: ~p"/vendor")

      collection.artist_id != artist.id ->
        socket
        |> put_flash(:error, "You are not authorized to edit this collection.")
        |> redirect(to: ~p"/vendor")

      true ->
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
    # The owner is always the logged-in artist, never from the params.
    artist = socket.assigns.current_scope.artist

    case Products.create_collection(artist.id, params) do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Collection created successfully.")
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # update_collection/2 takes only the name from the params (audit S-4).
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main
      flash={@flash}
      variant="vendor"
      nav_categories={@nav_categories}
      current_scope={@current_scope}
      has_unread={@has_unread_messages}
      pending_reviews_as_buyer={@pending_reviews_as_buyer}
      pending_reviews_as_vendor={@pending_reviews_as_vendor}
    >
      <div class="w-full px-8 py-8">
        <.back navigate={~p"/vendor"}>
          Artist Dashboard
        </.back>

        <.header>
          {@page_title}
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
