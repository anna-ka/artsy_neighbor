defmodule ArtsyNeighborWeb.AdminProductLive.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Admin.AdminProducts
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Categories
  alias ArtsyNeighborWeb.PhotoUploads

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]
  import ArtsyNeighborWeb.Params, only: [parse_id: 1]

  # A refusal from Products or AdminProducts: on this page it can only
  # mean someone who isn't an admin got in.
  @msg_admins_only "Only admins can change products here."

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> PhotoUploads.allow_photos(:images)
      |> apply_action(socket.assigns.live_action, params)

    {:ok, socket}
  end

  # Needed for the push_patch/2 to the edit page after a new product's
  # photo was refused (see handle_async/3). Nothing to do here.
  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp apply_action(socket, :edit, %{"id" => id}) do
    product = Products.get_product_with_associations!(id)

    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, product)
    |> assign(:existing_images, product.product_images)
    |> assign(:form, to_form(AdminProducts.change_product(product)))
    |> assign_selects(product.artist_id)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, %Product{})
    |> assign(:existing_images, [])
    |> assign(:form, to_form(AdminProducts.change_product(%Product{})))
    |> assign_selects(nil)
  end

  defp assign_selects(socket, artist_id) do
    # All statuses, so a work whose artist isn't :active can still be
    # edited (its owner must be in the list, or the form sends no
    # artist). Like the categories below.
    artists =
      Artists.list_artists_all_status()
      |> Enum.map(fn artist -> artist_option(artist) end)

    categories = Categories.list_categories_all_status() |> Enum.map(fn c -> {c.name, c.id} end)
    collections = collections_for(artist_id)

    socket
    |> assign(:artists, artists)
    |> assign(:categories, categories)
    |> assign(:collections, collections)
  end

  # "Nickname", or "Nickname (inactive)" for an artist who isn't :active.
  defp artist_option(artist) do
    if artist.status == :active do
      {artist.nickname, artist.id}
    else
      {"#{artist.nickname} (#{artist.status})", artist.id}
    end
  end

  defp collections_for(nil), do: []

  defp collections_for(artist_id) do
    Products.list_collections_for_artist(artist_id)
    |> Enum.map(fn c -> {c.name, c.id} end)
  end

  @impl true
  def handle_event("artist_changed", %{"product" => %{"artist_id" => artist_id}}, socket) do
    # nil for "no artist chosen" ("") and for anything that isn't an id.
    artist_id = parse_id(artist_id)
    collections = collections_for(artist_id)
    changeset = AdminProducts.change_product(socket.assigns.product, %{"artist_id" => artist_id})

    {:noreply,
     socket
     |> assign(:collections, collections)
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset = AdminProducts.change_product(socket.assigns.product, product_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  # Ignore a second press while photos are still being saved.
  def handle_event("save", _params, %{assigns: %{saving_photos: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"product" => product_params}, socket) do
    save_product(socket, socket.assigns.live_action, product_params)
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, PhotoUploads.cancel_photo(socket, :images, ref)}
  end

  # "Remove" next to a stored photo (PhotoUploads.stored_photos/1).
  # Products.delete_product_image/2 makes a product without photos a
  # draft.
  @impl true
  def handle_event("delete_image", %{"imageid" => image_id}, socket) do
    image_id = parse_id(image_id)
    image = Enum.find(socket.assigns.existing_images, fn img -> img.id == image_id end)

    if image do
      result = Products.delete_product_image(socket.assigns.current_scope, image)

      # Either way, show the photos as they are now; or, if the whole
      # product was deleted meanwhile (another tab), go back to the list.
      case Products.get_product_with_associations_all_status(socket.assigns.product.id) do
        nil ->
          {:noreply,
           socket
           |> put_flash(:error, "This product was deleted, so its photos are gone too.")
           |> push_navigate(to: ~p"/admin/products")}

        product ->
          socket =
            socket
            |> assign(:product, product)
            |> assign(:existing_images, product.product_images)

          case result do
            {:ok, _deleted} ->
              {:noreply, socket}

            {:error, :not_found} ->
              {:noreply, put_flash(socket, :info, "That photo had already been removed.")}

            {:error, :unauthorized} ->
              {:noreply, put_flash(socket, :error, @msg_admins_only)}
          end
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_image_up", %{"imageid" => image_id}, socket) do
    image_id = parse_id(image_id)
    images = socket.assigns.existing_images
    index = Enum.find_index(images, fn img -> img.id == image_id end)

    if index && index > 0 do
      Products.swap_image_positions(
        socket.assigns.current_scope,
        Enum.at(images, index),
        Enum.at(images, index - 1)
      )

      {:noreply, reload_existing_images(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_image_down", %{"imageid" => image_id}, socket) do
    image_id = parse_id(image_id)
    images = socket.assigns.existing_images
    index = Enum.find_index(images, fn img -> img.id == image_id end)

    if index && index < length(images) - 1 do
      Products.swap_image_positions(
        socket.assigns.current_scope,
        Enum.at(images, index),
        Enum.at(images, index + 1)
      )

      {:noreply, reload_existing_images(socket)}
    else
      {:noreply, socket}
    end
  end

  defp reload_existing_images(socket) do
    product = Products.get_product_with_associations!(socket.assigns.product.id)
    assign(socket, :existing_images, product.product_images)
  end

  defp save_product(socket, :new, product_params) do
    case AdminProducts.create_product(socket.assigns.current_scope, product_params) do
      {:ok, product} ->
        # Remembered so that the product is still published when the
        # admin saves again after a photo was refused (the page has
        # switched to the edit address by then; see finish_save/2).
        socket = assign(socket, :created_here, true)
        save_photos(socket, product)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      # Only if this page were opened by someone who isn't an admin.
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, @msg_admins_only)}
    end
  end

  defp save_product(socket, :edit, product_params) do
    scope = socket.assigns.current_scope

    case AdminProducts.update_product(scope, socket.assigns.product, product_params) do
      {:ok, product} ->
        save_photos(socket, product)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      # Only if this page were opened by someone who isn't an admin.
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, @msg_admins_only)}
    end
  end

  # The text is saved; the photos are processed in the background (see
  # ArtsyNeighborWeb.PhotoUploads), and handle_async/3 carries on.
  defp save_photos(socket, product) do
    socket = assign(socket, :product, product)
    folder = "products/#{product.id}"
    # New photos go after the ones already there.
    first_position = length(socket.assigns.existing_images) + 1

    scope = socket.assigns.current_scope

    create_row = fn key, position ->
      Products.create_product_image(scope, product, %{path: key, position: position})
    end

    case PhotoUploads.start_processing(socket, :images, folder, first_position, create_row) do
      {:no_photos, socket} ->
        finish_save(socket, product)

      {:started, socket} ->
        {:noreply, socket}

      {:not_ready, socket} ->
        stay_with_photo_problem(socket, Products.get_product_with_associations!(product.id))
    end
  end

  @impl true
  def handle_async(:process_photos, result, socket) do
    {socket, outcome} = PhotoUploads.finish_processing(socket, :images, result)
    product = Products.get_product_with_associations!(socket.assigns.product.id)

    if outcome.failed > 0 do
      stay_with_photo_problem(socket, product)
    else
      finish_save(socket, product)
    end
  end

  # A photo was refused: stay, so it stays visible with its message.
  # A new product isn't published yet in that case. `product` must have
  # its photos loaded.
  defp stay_with_photo_problem(socket, product) do
    socket =
      socket
      |> assign(:page_title, "Edit Product")
      |> assign(:product, product)
      |> assign(:existing_images, product.product_images)
      |> assign(:form, to_form(AdminProducts.change_product(product)))
      |> put_flash(:error, PhotoUploads.problem_flash(socket, "The product is saved."))

    # Switch a new product's page to its edit address, so saving again
    # doesn't create a second product.
    if socket.assigns.live_action == :new do
      {:noreply, push_patch(socket, to: ~p"/admin/products/#{product.id}/edit")}
    else
      {:noreply, socket}
    end
  end

  # New products start as :draft (AdminProducts.create_product/2). An
  # admin-created product is published straight away, as before —
  # unless it has no photo, which publishing requires. "Created here"
  # rather than live_action == :new: after a refused photo the page has
  # switched to the edit address, but the product is still the new one.
  defp finish_save(socket, product) do
    message =
      if socket.assigns[:created_here] do
        case Products.publish_product(socket.assigns.current_scope, product) do
          {:ok, _published} ->
            "Product created successfully."

          {:error, :no_photos} ->
            "Product created as a draft: it needs at least one photo to be published."

          # e.g. archived or deleted in another tab meanwhile.
          {:error, _reason} ->
            "Product saved, but it couldn't be published. Check its status in the list."
        end
      else
        "Product updated successfully."
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/admin/products")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main
      flash={@flash}
      variant="admin"
      nav_categories={@nav_categories}
      current_scope={@current_scope}
      has_unread={@has_unread_messages}
      pending_reviews_as_buyer={@pending_reviews_as_buyer}
      pending_reviews_as_vendor={@pending_reviews_as_vendor}
    >
      <div class="w-full px-8 py-8">
        <.back navigate={~p"/admin/products"}>
          Admin Products
        </.back>

        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="product-form" phx-change="validate" phx-submit="save">
          <%!-- ===== PRODUCT DETAILS ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Product Details
            </h3>
            <.input
              field={@form[:title]}
              type="text"
              label={raw("Title <span class=\"text-error\">*</span>")}
              placeholder="Product title"
              phx-debounce="blur"
            />
            <.input
              field={@form[:descr]}
              type="textarea"
              label={raw("Description <span class=\"text-error\">*</span>")}
              rows="3"
              phx-debounce="blur"
            />
            <.input
              field={@form[:details]}
              type="textarea"
              label={raw("Details <span class=\"text-error\">*</span>")}
              rows="4"
              phx-debounce="blur"
            />
            <.input
              field={@form[:price]}
              type="number"
              label={raw("Price <span class=\"text-error\">*</span>")}
              step="any"
              phx-debounce="blur"
            />
            <.input
              field={@form[:unique_work]}
              type="checkbox"
              label="This is a unique, one-of-a-kind work (e.g. original painting or sculpture)"
            />
          </div>

          <%!-- ===== IMAGES ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Images
            </h3>
            <p class="text-sm text-base-content/60 mb-4">
              <PhotoUploads.accepted_help />
            </p>

            <%!-- Photos already stored, with ↑ ↓ and Remove buttons --%>
            <PhotoUploads.stored_photos images={@existing_images} saving_photos={@saving_photos} />

            <p class="text-xs text-base-content/50 mb-2">
              New images are appended after existing ones.
            </p>
            <PhotoUploads.photo_picker
              upload={@uploads.images}
              photo_prep={@photo_prep}
              photo_errors={@photo_errors}
              saving_photos={@saving_photos}
            />
          </div>

          <%!-- ===== CLASSIFICATION ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Classification
            </h3>
            <.input
              field={@form[:artist_id]}
              type="select"
              label={raw("Artist <span class=\"text-error\">*</span>")}
              prompt="Select an artist"
              options={@artists}
              phx-change="artist_changed"
            />
            <.input
              field={@form[:category_id]}
              type="select"
              label={raw("Category <span class=\"text-error\">*</span>")}
              prompt="Select a category"
              options={@categories}
            />
            <.input
              field={@form[:collection_id]}
              type="select"
              label="Collection"
              prompt={
                if @collections == [], do: "Select an artist first", else: "Select a collection"
              }
              options={@collections}
              disabled={@collections == []}
            />
          </div>

          <%!-- ===== DIMENSIONS & MATERIALS ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Dimensions & Materials
            </h3>
            <div class="grid grid-cols-3 gap-4">
              <.input
                field={@form[:width]}
                type="number"
                label="Width"
                step="any"
                phx-debounce="blur"
              />
              <.input
                field={@form[:length]}
                type="number"
                label="Length"
                step="any"
                phx-debounce="blur"
              />
              <.input
                field={@form[:height]}
                type="number"
                label="Height"
                step="any"
                phx-debounce="blur"
              />
            </div>
            <.input
              field={@form[:units]}
              type="select"
              label="Units"
              options={[{"Centimetres (cm)", "cm"}, {"Inches (in)", "in"}]}
            />
            <.input
              field={@form[:materials]}
              type="text"
              label="Materials"
              placeholder="e.g., Oil on canvas, stretched linen"
              phx-debounce="blur"
            />
          </div>

          <div class="mt-6">
            <.button_artsy variant="primary" disable_with="Saving..." disabled={@saving_photos}>
              Save Product
            </.button_artsy>
            <PhotoUploads.photo_status saving_photos={@saving_photos} photo_problem={@photo_problem} />
          </div>
        </.form>

        <.back navigate={~p"/admin/products"}>
          Admin Products
        </.back>
      </div>
    </Layouts.artsy_main>
    """
  end
end
