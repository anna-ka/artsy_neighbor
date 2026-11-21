defmodule ArtsyNeighborWeb.VendorLive.ProductForm do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Categories
  alias ArtsyNeighborWeb.PhotoUploads

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    # The upload slot must be set up in mount, before the page is
    # rendered. We name it :images; the template uses @uploads.images.
    # PhotoUploads.allow_photos/2 also sets the accepted formats and
    # size limits shared by all photo forms.
    socket =
      socket
      |> PhotoUploads.allow_photos(:images)
      |> apply_action(socket.assigns.live_action, params)

    {:ok, socket}
  end

  # Needed because, after the first save of a new product whose photo
  # was refused, the page switches its address to the product's edit
  # page with push_patch/2 (see handle_async/3), which calls this. Nothing
  # to do: the socket already holds the saved product.
  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp apply_action(socket, :new, _params) do
    artist = socket.assigns.current_scope.artist
    product = %Product{artist_id: artist.id}

    socket
    |> assign(:page_title, "Create New Product")
    |> assign(:product, product)
    # no existing images for a new product
    |> assign(:existing_images, [])
    |> assign(:form, to_form(Products.change_product(product)))
    |> assign(:new_collection_form_open, false)
    |> assign_categories()
    |> assign_collections()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    artist = socket.assigns.current_scope.artist
    # get_product_with_associations! preloads product_images so we can
    # display them in the form (the plain get_product! does not preload)
    product = Products.get_product_with_associations!(id)

    if product.artist_id != artist.id do
      socket
      |> put_flash(:error, "You are not authorized to edit this product.")
      |> redirect(to: ~p"/vendor")
    else
      socket
      |> assign(:page_title, "Edit Product")
      |> assign(:product, product)
      |> assign(:existing_images, product.product_images)
      |> assign(:form, to_form(Products.change_product(product)))
      |> assign(:new_collection_form_open, false)
      |> assign_categories()
      |> assign_collections()
    end
  end

  # list_categories_all_status/0, not list_categories/0 — the latter is
  # now scoped to :active, and a product being edited may already be
  # assigned to a category that's since been archived. Without this, the
  # select's current value would be missing from its own options list,
  # the browser would default to selecting whatever category is first,
  # and saving without touching the dropdown would silently reassign the
  # product's category. Same reasoning as AdminProductLive.Form's
  # identical fix.
  defp assign_categories(socket) do
    categories = Categories.list_categories_all_status() |> Enum.map(fn c -> {c.name, c.id} end)
    assign(socket, :categories, categories)
  end

  defp assign_collections(socket) do
    artist = socket.assigns.current_scope.artist

    collections =
      Products.list_collections_for_artist(artist.id)
      |> Enum.map(fn c -> {c.name, c.id} end)

    assign(socket, :collections, collections)
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset = Products.change_product(socket.assigns.product, product_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  # The form has several submit buttons (see save_buttons/1); the one
  # pressed arrives as "save_action": "draft", "preview", "publish", or
  # "save" (the single button of a product that isn't a draft).
  @impl true
  # Ignore a second press while photos are still being saved (the
  # buttons are disabled then, but a fast double click can still arrive).
  def handle_event("save", _params, %{assigns: %{saving_photos: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"product" => product_params} = params, socket) do
    save_action = Map.get(params, "save_action", "save")
    save_product(socket, socket.assigns.live_action, product_params, save_action)
  end

  # "Remove" next to a stored photo. Only photos of the product being
  # edited (already checked to be this artist's) can be removed.
  @impl true
  def handle_event("delete_image", %{"imageid" => image_id}, socket) do
    image_id = String.to_integer(image_id)
    image = Enum.find(socket.assigns.existing_images, fn img -> img.id == image_id end)

    if image do
      was_available = socket.assigns.product.status == :available
      result = Products.delete_product_image(image)

      # Either way, show the photos as they are now.
      product = Products.get_product_with_associations!(socket.assigns.product.id)

      socket =
        socket
        |> assign(:product, product)
        |> assign(:existing_images, product.product_images)

      case result do
        {:ok, _deleted} ->
          # Products.delete_product_image/1 makes a product without
          # photos a draft (it can't be for sale without one).
          if was_available and product.status == :draft do
            {:noreply,
             put_flash(
               socket,
               :info,
               "That was the last photo, so this work is now a draft and hidden from buyers. " <>
                 "Add a photo and publish it again."
             )}
          else
            {:noreply, socket}
          end

        # e.g. already removed in another browser tab
        {:error, :not_found} ->
          {:noreply, put_flash(socket, :info, "That photo had already been removed.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_new_collection_form", _params, socket) do
    {:noreply, assign(socket, new_collection_form_open: !socket.assigns.new_collection_form_open)}
  end

  @impl true
  def handle_event("save_new_collection", %{"name" => name}, socket) do
    artist = socket.assigns.current_scope.artist
    name = String.trim(name)

    if name == "" do
      {:noreply, socket}
    else
      all_collections = Products.list_collections_for_artist(artist.id)
      max_pos = all_collections |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)

      case Products.create_collection(%{name: name, position: max_pos + 1, artist_id: artist.id}) do
        {:ok, new_collection} ->
          updated_collections =
            Products.list_collections_for_artist(artist.id)
            |> Enum.map(fn c -> {c.name, c.id} end)

          # Auto-select the new collection in the product form
          updated_changeset =
            socket.assigns.form.source
            |> Ecto.Changeset.put_change(:collection_id, new_collection.id)

          {:noreply,
           socket
           |> assign(:collections, updated_collections)
           |> assign(:form, to_form(updated_changeset))
           |> assign(:new_collection_form_open, false)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not create collection.")}
      end
    end
  end

  # cancel_upload removes one pending file from the upload queue.
  # entry.ref is a unique id that LiveView assigns to each selected file.
  # The user can cancel a file before submitting the form.
  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, PhotoUploads.cancel_photo(socket, :images, ref)}
  end

  @impl true
  def handle_event("move_image_up", %{"imageid" => image_id}, socket) do
    image_id = String.to_integer(image_id)
    # already sorted by position
    images = socket.assigns.existing_images
    index = Enum.find_index(images, fn img -> img.id == image_id end)

    if index && index > 0 do
      Products.swap_image_positions(Enum.at(images, index), Enum.at(images, index - 1))
      {:noreply, reload_existing_images(socket)}
    else
      # already first, nothing to do
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_image_down", %{"imageid" => image_id}, socket) do
    image_id = String.to_integer(image_id)
    images = socket.assigns.existing_images
    index = Enum.find_index(images, fn img -> img.id == image_id end)

    if index && index < length(images) - 1 do
      Products.swap_image_positions(Enum.at(images, index), Enum.at(images, index + 1))
      {:noreply, reload_existing_images(socket)}
    else
      # already last, nothing to do
      {:noreply, socket}
    end
  end

  # Reloads product_images from DB and updates the existing_images assign.
  # Called after a position swap to reflect the new order immediately.
  defp reload_existing_images(socket) do
    product = Products.get_product_with_associations!(socket.assigns.product.id)
    assign(socket, :existing_images, product.product_images)
  end

  defp save_product(socket, :new, product_params, save_action) do
    # A new product starts as a draft (Products.create_product/1); it
    # becomes :available only through publish_product/1, below.
    artist_id = socket.assigns.current_scope.artist.id
    product_params = Map.put(product_params, "artist_id", artist_id)

    case Products.create_product(product_params) do
      {:ok, product} ->
        save_photos(socket, product, save_action)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_product(socket, :edit, product_params, save_action) do
    case Products.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        save_photos(socket, product, save_action)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # The text is saved; now the photos. They are processed in the
  # background (see ArtsyNeighborWeb.PhotoUploads), and handle_async/3
  # below carries on when that's done. Photos come after the product
  # because they are stored in the product's folder, products/<id>/.
  defp save_photos(socket, product, save_action) do
    socket = assign(socket, product: product, save_action: save_action)
    folder = "products/#{product.id}"
    # New photos go after the ones already there.
    first_position = length(socket.assigns.existing_images) + 1

    create_row = fn key, position ->
      Products.create_product_image(%{path: key, position: position, product_id: product.id})
    end

    case PhotoUploads.start_processing(socket, :images, folder, first_position, create_row) do
      {:no_photos, socket} ->
        after_save(socket, product, save_action, nil)

      {:started, socket} ->
        {:noreply, socket}

      {:not_ready, socket} ->
        stay_with_photo_problem(socket, Products.get_product_with_associations!(product.id))
    end
  end

  # The background photo processing is done.
  @impl true
  def handle_async(:process_photos, result, socket) do
    {socket, outcome} = PhotoUploads.finish_processing(socket, :images, result)
    product = Products.get_product_with_associations!(socket.assigns.product.id)

    if outcome.failed > 0 do
      stay_with_photo_problem(socket, product)
    else
      after_save(socket, product, socket.assigns.save_action, outcome)
    end
  end

  # A photo was refused. Stay on this page, so the refused photos stay
  # visible in the upload box with their messages. The text and the
  # good photos are saved; the button's own action (publish, preview,
  # ...) is not carried out, so nothing happens that the artist doesn't
  # see. `product` must have its photos loaded.
  defp stay_with_photo_problem(socket, product) do
    socket =
      socket
      |> assign(:page_title, "Edit Product")
      |> assign(:product, product)
      |> assign(:existing_images, product.product_images)
      |> assign(:form, to_form(Products.change_product(product)))
      |> put_flash(:error, PhotoUploads.problem_flash(socket, "Your work is saved."))

    # A new product now exists: switch to its edit page's address, so
    # saving again (or reloading) doesn't create a second product.
    if socket.assigns.live_action == :new do
      {:noreply, push_patch(socket, to: edit_path(product))}
    else
      {:noreply, socket}
    end
  end

  # What happens after the product (and its photos) are saved depends on
  # the button pressed. `photo_outcome` is nil if no photos were added,
  # otherwise PhotoUploads' %{stored: ..., failed: 0}. When photos were
  # added and there are now several, the artist is reminded to check
  # their order — on the edit page, where the arrow buttons are.
  defp after_save(socket, product, "draft", photo_outcome) do
    message = join_messages("Saved as a draft. Buyers can't see it yet.", photo_outcome, product)

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: edit_path(product))}
  end

  defp after_save(socket, product, "preview", _photo_outcome) do
    preview_params = [
      preview: "1",
      return_to: edit_path(product),
      return_label: "Back to editing"
    ]

    {:noreply, push_navigate(socket, to: ~p"/products/#{product.id}?#{preview_params}")}
  end

  defp after_save(socket, product, "publish", photo_outcome) do
    case Products.publish_product(product) do
      {:ok, _published} ->
        finish_on_dashboard_or_edit(socket, product, published_message(product), photo_outcome)

      {:error, :no_photos} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Saved as a draft. Add at least one photo to publish this work."
         )
         |> push_navigate(to: edit_path(product))}

      {:error, _other} ->
        {:noreply,
         socket
         |> put_flash(:error, "Saved, but this work couldn't be published.")
         |> push_navigate(to: edit_path(product))}
    end
  end

  # "save": the single button of a product that isn't a draft. Its
  # status stays as it was.
  defp after_save(socket, product, _save_action, photo_outcome) do
    finish_on_dashboard_or_edit(socket, product, "Product saved.", photo_outcome)
  end

  # Back to the dashboard, unless the artist should check the order of
  # newly added photos: then to the edit page, with the reminder.
  defp finish_on_dashboard_or_edit(socket, product, message, photo_outcome) do
    case order_reminder(photo_outcome, product) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/vendor")}

      reminder ->
        {:noreply,
         socket
         |> put_flash(:info, message <> " " <> reminder)
         |> push_navigate(to: edit_path(product))}
    end
  end

  defp join_messages(message, photo_outcome, product) do
    case order_reminder(photo_outcome, product) do
      nil -> message
      reminder -> message <> " " <> reminder
    end
  end

  defp order_reminder(nil, _product), do: nil

  defp order_reminder(photo_outcome, product) do
    PhotoUploads.order_reminder(photo_outcome, length(product.product_images))
  end

  defp edit_path(product), do: ~p"/vendor/products/#{product.id}/edit"

  # A published work is only shown to buyers while the artist's own
  # profile is public too (Products.only_available/1). The status is read
  # fresh: the one in current_scope was loaded when the page opened.
  defp published_message(product) do
    if Artists.get_artist!(product.artist_id).status == :active do
      "Published! Buyers can now see this work."
    else
      "Published but not visible to public yet. Buyers will see it once your " <>
        "Artist profile is public — you can make it public from your Vendor dashboard."
    end
  end

  # A new product (not saved yet) counts as a draft too.
  defp draft?(product), do: product.id == nil or product.status == :draft

  # The form's submit buttons. Each sends its own "save_action" (see the
  # "save" event). A draft gets Save draft / Preview / Publish, with a
  # short explanation under them; any other product keeps one Save
  # button, which leaves its status as it is.
  #
  # Temporary, until the vendor dashboard lets artists change each
  # work's status (NOTES #16).
  attr :product, :any, required: true
  attr :saving_photos, :boolean, required: true

  defp save_buttons(assigns) do
    ~H"""
    <div :if={draft?(@product)} class="space-y-3">
      <div class="flex flex-wrap gap-3">
        <.button_artsy
          variant="outline"
          name="save_action"
          value="draft"
          disable_with="Saving..."
          disabled={@saving_photos}
        >
          Save draft
        </.button_artsy>
        <.button_artsy
          variant="outline"
          name="save_action"
          value="preview"
          disable_with="Saving..."
          disabled={@saving_photos}
        >
          Preview
        </.button_artsy>
        <.button_artsy
          variant="primary"
          name="save_action"
          value="publish"
          disable_with="Publishing..."
          disabled={@saving_photos}
        >
          Publish
        </.button_artsy>
      </div>

      <%!-- A click-to-open box rather than hover tooltips: hovering
           doesn't work on phones and tablets. --%>
      <details class="text-sm max-w-prose">
        <summary class="cursor-pointer underline">What do these buttons do?</summary>
        <ul class="mt-2 space-y-1 list-disc pl-5">
          <li>
            <strong>Save draft</strong>
            keeps your work so you can finish it later, from any computer or phone. Buyers can't see it.
          </li>
          <li>
            <strong>Preview</strong> saves the draft and shows its page the way buyers will see it.
          </li>
          <li>
            <strong>Publish</strong>
            saves and puts the work in your shop, for buyers to see. It needs at least one photo.
          </li>
        </ul>
      </details>
    </div>

    <.button_artsy
      :if={not draft?(@product)}
      variant="primary"
      name="save_action"
      value="save"
      disable_with="Saving..."
      disabled={@saving_photos}
    >
      Save
    </.button_artsy>
    """
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

        <%!-- A draft isn't shown to buyers; say so plainly. --%>
        <div :if={draft?(@product)} class="alert alert-info mb-6">
          <span>
            <strong>Draft</strong>
            — buyers can't see this work yet. When it's ready and has at least one photo, press <strong>Publish</strong>.
          </span>
        </div>

        <.form for={@form} id="product-form" phx-change="validate" phx-submit="save">
          <%!-- Title --%>
          <.input
            field={@form[:title]}
            type="text"
            label={raw("Title <span class=\"text-error\">*</span>")}
            placeholder="Product title"
            phx-debounce="blur"
          />

          <%!-- ============================================================
               IMAGE UPLOAD SECTION
               ============================================================ --%>
          <div class="space-y-4 py-4">
            <div class="label">
              <span class="label-text font-semibold">
                Images
                <span class="font-normal text-base-content/60">
                  (at least one is needed to publish)
                </span>
              </span>
            </div>
            <p class="text-sm text-base-content/60 -mt-2">
              <PhotoUploads.accepted_help />
            </p>

            <%!-- Photos already stored, with ↑ ↓ and Remove buttons --%>
            <PhotoUploads.stored_photos images={@existing_images} saving_photos={@saving_photos} />

            <%!-- The file picker and the list of picked photos, shared by
                 all photo forms (ArtsyNeighborWeb.PhotoUploads). --%>
            <PhotoUploads.photo_picker
              upload={@uploads.images}
              photo_prep={@photo_prep}
              photo_errors={@photo_errors}
              saving_photos={@saving_photos}
            />
          </div>
          <%!-- ============================================================ --%>

          <%!-- Description --%>
          <.input
            field={@form[:descr]}
            type="textarea"
            label={raw("Description <span class=\"text-error\">*</span>")}
            rows="3"
            phx-debounce="blur"
          />

          <%!-- Details --%>
          <.input
            field={@form[:details]}
            type="textarea"
            label={raw("Details <span class=\"text-error\">*</span>")}
            rows="4"
            phx-debounce="blur"
          />

          <%!-- Price --%>
          <.input
            field={@form[:price]}
            type="number"
            label={raw("Price <span class=\"text-error\">*</span>")}
            step="any"
            phx-debounce="blur"
          />

          <%!-- Unique Work --%>
          <.input
            field={@form[:unique_work]}
            type="checkbox"
            label="This is a unique, one-of-a-kind work (e.g. original painting or sculpture)"
          />

          <%!-- Category --%>
          <.input
            field={@form[:category_id]}
            type="select"
            label={raw("Category <span class=\"text-error\">*</span>")}
            prompt="Select a category"
            options={@categories}
          />

          <%!-- Collection (vendor-defined shelf) --%>
          <.input
            field={@form[:collection_id]}
            type="select"
            label="Collection"
            prompt="Select a collection"
            options={@collections}
          />
          <button
            type="button"
            phx-click="toggle_new_collection_form"
            class="btn btn-ghost btn-xs -mt-2 mb-2"
          >
            + New collection
          </button>

          <%!-- Dimensions --%>
          <div class="grid grid-cols-3 gap-4">
            <.input field={@form[:width]} type="number" label="Width" step="any" phx-debounce="blur" />
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

          <%!-- Units --%>
          <.input
            field={@form[:units]}
            type="select"
            label="Units"
            options={[{"Centimetres (cm)", "cm"}, {"Inches (in)", "in"}]}
          />

          <%!-- Materials --%>
          <.input
            field={@form[:materials]}
            type="text"
            label="Materials"
            placeholder="e.g., Oil on canvas, stretched linen"
            phx-debounce="blur"
          />

          <.save_buttons product={@product} saving_photos={@saving_photos} />
          <PhotoUploads.photo_status saving_photos={@saving_photos} photo_problem={@photo_problem} />
        </.form>

        <.back navigate={~p"/vendor"}>
          Artist Dashboard
        </.back>
      </div>

      <%!-- New collection modal — lives outside the product <form> to avoid nested forms --%>
      <div :if={@new_collection_form_open} class="modal modal-open">
        <div class="modal-box max-w-sm">
          <h3 class="font-semibold text-lg mb-4">New Collection</h3>
          <form phx-submit="save_new_collection">
            <input
              type="text"
              name="name"
              placeholder="e.g. Watercolours, Large Format"
              class="input input-bordered w-full"
              autofocus
            />
            <div class="modal-action">
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button
                type="button"
                phx-click="toggle_new_collection_form"
                class="btn btn-ghost btn-sm"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="toggle_new_collection_form"></div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
