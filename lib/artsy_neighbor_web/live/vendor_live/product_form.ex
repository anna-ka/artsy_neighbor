defmodule ArtsyNeighborWeb.VendorLive.ProductForm do
  use ArtsyNeighborWeb, :live_view

  require Logger

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Categories

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    # allow_upload MUST be called in mount, before the page is rendered.
    # It registers the upload slot on the socket so LiveView knows to
    # accept file chunks over the websocket connection.
    # We name the slot :images — this name is used everywhere else:
    #   consume_uploaded_entries(socket, :images, ...)
    #   @uploads.images  in the template
    socket =
      socket
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 5,
        # 5 MB per file
        max_file_size: 5_000_000
      )
      |> apply_action(socket.assigns.live_action, params)

    {:ok, socket}
  end

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
    {:noreply, cancel_upload(socket, :images, ref)}
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
        # Photos are added AFTER the product is saved, because their rows
        # need product.id.
        socket = save_uploaded_images(socket, product, 1)
        after_save(socket, product, save_action)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_product(socket, :edit, product_params, save_action) do
    case Products.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        # New images are appended after the existing ones.
        existing_count = length(socket.assigns.existing_images)
        socket = save_uploaded_images(socket, product, existing_count + 1)
        after_save(socket, product, save_action)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Stores the files the artist picked and creates one ProductImage row
  # per file, with positions starting at `first_position`. Returns the
  # socket, with an error message if a photo couldn't be saved.
  #
  # (Still a plain copy into priv/static/uploads; image storage step 2b
  # switches this to Images.process_upload/3.)
  defp save_uploaded_images(socket, product, first_position) do
    # For each uploaded file, the callback receives:
    #   %{path: tmp_path} — the temp file path where LiveView buffered the upload
    #   entry             — metadata struct (client_name, size, content_type, etc.)
    # The callback must return {:ok, result}. The list of all results
    # becomes the return value of consume_uploaded_entries.
    image_paths =
      consume_uploaded_entries(socket, :images, fn %{path: tmp_path}, entry ->
        ext = Path.extname(entry.client_name)
        # System.unique_integer gives a collision-free number for the filename
        filename = "#{System.unique_integer([:positive])}#{ext}"

        dest =
          Path.join([
            # :code.priv_dir/1 returns the absolute path to priv/ at runtime
            :code.priv_dir(:artsy_neighbor),
            "static",
            "uploads",
            "products",
            filename
          ])

        File.cp!(tmp_path, dest)
        # The web-accessible URL path (relative to priv/static/)
        {:ok, "/uploads/products/#{filename}"}
      end)

    # Enum.with_index(first_position) pairs each path with a position.
    results =
      for {path, position} <- Enum.with_index(image_paths, first_position) do
        save_image_row(product, path, position)
      end

    if :error in results do
      put_flash(
        socket,
        :error,
        "One of your photos couldn't be saved. Please try adding it again."
      )
    else
      socket
    end
  end

  # Creates one photo's row. Returns :ok, or :error after removing the
  # copied file, which no row points to.
  defp save_image_row(product, path, position) do
    case Products.create_product_image(%{path: path, position: position, product_id: product.id}) do
      {:ok, _image} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Saving a photo of product #{product.id} failed: #{inspect(changeset.errors)}"
        )

        File.rm(Path.join([:code.priv_dir(:artsy_neighbor), "static", path]))
        :error
    end
  end

  # What happens after the product (and its photos) are saved depends on
  # the button pressed.
  defp after_save(socket, product, "draft") do
    {:noreply,
     socket
     |> put_flash(:info, "Saved as a draft. Buyers can't see it yet.")
     |> push_navigate(to: edit_path(product))}
  end

  defp after_save(socket, product, "preview") do
    preview_params = [
      preview: "1",
      return_to: edit_path(product),
      return_label: "Back to editing"
    ]

    {:noreply, push_navigate(socket, to: ~p"/products/#{product.id}?#{preview_params}")}
  end

  defp after_save(socket, product, "publish") do
    case Products.publish_product(product) do
      {:ok, _published} ->
        {:noreply,
         socket
         |> put_flash(:info, published_message(product))
         |> push_navigate(to: ~p"/vendor")}

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
  defp after_save(socket, _product, _save_action) do
    {:noreply,
     socket
     |> put_flash(:info, "Product saved.")
     |> push_navigate(to: ~p"/vendor")}
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

  # Translates LiveView upload error atoms into readable messages
  defp error_to_string(:too_large), do: "File too large (max 3 MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(:not_accepted), do: "File type not accepted (jpg, png, webp only)"

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

  defp save_buttons(assigns) do
    ~H"""
    <div :if={draft?(@product)} class="space-y-3">
      <div class="flex flex-wrap gap-3">
        <.button_artsy variant="outline" name="save_action" value="draft" disable_with="Saving...">
          Save draft
        </.button_artsy>
        <.button_artsy variant="outline" name="save_action" value="preview" disable_with="Saving...">
          Preview
        </.button_artsy>
        <.button_artsy
          variant="primary"
          name="save_action"
          value="publish"
          disable_with="Publishing..."
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
              <span class="label-text-alt text-base-content/60">
                Up to 5 files · jpg, png, webp · max 5 MB each
              </span>
            </div>

            <%!-- Existing images shown on the edit form, with up/down reorder buttons --%>
            <div :if={@existing_images != []}>
              <p class="text-sm text-base-content/60 mb-2">Already uploaded:</p>
              <div class="flex flex-col gap-3">
                <div
                  :for={{img, index} <- Enum.with_index(@existing_images)}
                  class="flex items-center gap-3"
                >
                  <img
                    src={img.path}
                    class="w-24 h-24 object-cover rounded-lg border border-base-300"
                  />
                  <div
                    class="flex flex-col gap-1 tooltip tooltip-right"
                    data-tip="Use arrows to change the ordering of images"
                  >
                    <%!-- ↑ hidden on the first image --%>
                    <button
                      :if={index > 0}
                      type="button"
                      phx-click="move_image_up"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >
                      ↑
                    </button>
                    <%!-- ↓ hidden on the last image --%>
                    <button
                      :if={index < length(@existing_images) - 1}
                      type="button"
                      phx-click="move_image_down"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >
                      ↓
                    </button>
                  </div>
                  <button
                    type="button"
                    phx-click="delete_image"
                    phx-value-imageid={img.id}
                    data-confirm="Remove this photo? This can't be undone."
                    class="btn btn-ghost btn-sm text-error"
                  >
                    Remove
                  </button>
                </div>
              </div>
            </div>

            <%!-- live_file_input is the LiveView-aware file picker.
                 Unlike a regular <input type="file">, it uploads the file
                 over the websocket in chunks as soon as it is selected —
                 before the form is even submitted. Without this component,
                 file uploads do not work in LiveView. --%>
            <.live_file_input
              upload={@uploads.images}
              class="file-input file-input-bordered w-full"
            />

            <%!-- Preview list: one row per selected file.
                 @uploads.images.entries is populated the moment the user
                 picks files, before they submit the form. --%>
            <div class="space-y-3">
              <div :for={entry <- @uploads.images.entries} class="flex items-center gap-3">
                <%!-- live_img_preview renders a thumbnail from the local file
                     immediately — no server round-trip needed. --%>
                <.live_img_preview
                  entry={entry}
                  class="w-16 h-16 object-cover rounded-lg border border-base-300"
                />

                <div class="flex-1 min-w-0">
                  <p class="text-sm truncate">{entry.client_name}</p>
                  <%!-- entry.progress goes 0→100 as the file uploads to the
                       server temp location over the websocket --%>
                  <progress
                    value={entry.progress}
                    max="100"
                    class="progress progress-primary w-full"
                  />
                </div>

                <%!-- Sends "cancel_upload" event with the entry's unique ref,
                     which removes it from the queue without submitting the form --%>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs text-error"
                >
                  ✕
                </button>

                <%!-- Per-file errors, e.g. this specific file is too large --%>
                <p :for={err <- upload_errors(@uploads.images, entry)} class="text-error text-xs">
                  {error_to_string(err)}
                </p>
              </div>
            </div>

            <%!-- Upload-level errors, e.g. too many files selected at once --%>
            <p :for={err <- upload_errors(@uploads.images)} class="text-error text-sm">
              {error_to_string(err)}
            </p>
          </div>
          <%!-- ============================================================ --%>

          <.save_buttons product={@product} />
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
