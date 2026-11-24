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
    collection = Products.get_own_collection(socket.assigns.current_scope, parse_id(id))

    # Deleted meanwhile (e.g. in another tab), someone else's, or a
    # made-up address.
    if is_nil(collection) do
      socket
      |> put_flash(:error, "That collection isn't one of yours, or doesn't exist any more.")
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
    # The owner is always the logged-in artist (the scope's), never from
    # the params.
    socket.assigns.current_scope
    |> Products.create_collection(params)
    |> after_save(socket, "Collection created successfully.")
  end

  # update_collection/3 takes only the name from the params (audit S-4).
  defp save_collection(socket, :edit, params) do
    socket.assigns.current_scope
    |> Products.update_collection(socket.assigns.collection, params)
    |> after_save(socket, "Collection updated successfully.")
  end

  defp after_save({:ok, _collection}, socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/vendor")}
  end

  defp after_save({:error, %Ecto.Changeset{} = changeset}, socket, _message) do
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  # :artist_removed or :unauthorized (see Products, "Who is acting")
  defp after_save({:error, reason}, socket, _message) do
    {:noreply, put_flash(socket, :error, Products.refused_message(reason))}
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
