defmodule ArtsyNeighborWeb.VendorLive.ProductForm do
  use ArtsyNeighborWeb, :live_view

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
        max_file_size: 5_000_000  # 5 MB per file
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
    |> assign(:existing_images, [])  # no existing images for a new product
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

  defp assign_categories(socket) do
    categories = Categories.list_categories() |> Enum.map(fn c -> {c.name, c.id} end)
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

  @impl true
  def handle_event("save", %{"product" => product_params}, socket) do
    save_product(socket, socket.assigns.live_action, product_params)
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

          {:noreply, socket
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
    images = socket.assigns.existing_images  # already sorted by position
    index = Enum.find_index(images, fn img -> img.id == image_id end)

    if index && index > 0 do
      Products.swap_image_positions(Enum.at(images, index), Enum.at(images, index - 1))
      {:noreply, reload_existing_images(socket)}
    else
      {:noreply, socket}  # already first, nothing to do
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
      {:noreply, socket}  # already last, nothing to do
    end
  end

  # Reloads product_images from DB and updates the existing_images assign.
  # Called after a position swap to reflect the new order immediately.
  defp reload_existing_images(socket) do
    product = Products.get_product_with_associations!(socket.assigns.product.id)
    assign(socket, :existing_images, product.product_images)
  end

  defp save_product(socket, :new, product_params) do
    # Require at least one image on create
    if Enum.empty?(socket.assigns.uploads.images.entries) do
      {:noreply, put_flash(socket, :error, "Please upload at least one image of your work.")}
    else
      artist_id = socket.assigns.current_scope.artist.id
      product_params = Map.put(product_params, "artist_id", artist_id)

      case Products.create_product(product_params) do
        {:ok, product} ->
          # consume_uploaded_entries is called AFTER the product is saved
          # because we need product.id to create the ProductImage records.
          #
          # For each uploaded file, the callback receives:
          #   %{path: tmp_path} — the temp file path where LiveView buffered the upload
          #   entry             — metadata struct (client_name, size, content_type, etc.)
          #
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
                  "static", "uploads", "products", filename
                ])
              # Move the temp file to permanent storage
              File.cp!(tmp_path, dest)
              # Return the web-accessible URL path (relative to priv/static/)
              {:ok, "/uploads/products/#{filename}"}
            end)

          # Create one ProductImage row per uploaded file.
          # Enum.with_index(1) pairs each path with a position: 1, 2, 3...
          image_paths
          |> Enum.with_index(1)
          |> Enum.each(fn {path, position} ->
            Products.create_product_image(%{
              path: path,
              position: position,
              product_id: product.id
            })
          end)

          {:noreply,
           socket
           |> put_flash(:info, "Product created successfully.")
           |> push_navigate(to: ~p"/vendor")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  defp save_product(socket, :edit, product_params) do
    case Products.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        # New images are appended after the existing ones.
        # We start their position numbers after the last existing image.
        existing_count = length(socket.assigns.existing_images)

        image_paths =
          consume_uploaded_entries(socket, :images, fn %{path: tmp_path}, entry ->
            ext = Path.extname(entry.client_name)
            filename = "#{System.unique_integer([:positive])}#{ext}"
            dest =
              Path.join([
                :code.priv_dir(:artsy_neighbor),
                "static", "uploads", "products", filename
              ])
            File.cp!(tmp_path, dest)
            {:ok, "/uploads/products/#{filename}"}
          end)

        image_paths
        |> Enum.with_index(existing_count + 1)
        |> Enum.each(fn {path, position} ->
          Products.create_product_image(%{
            path: path,
            position: position,
            product_id: product.id
          })
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully.")
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # Translates LiveView upload error atoms into readable messages
  defp error_to_string(:too_large), do: "File too large (max 3 MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(:not_accepted), do: "File type not accepted (jpg, png, webp only)"

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
          <button type="button" phx-click="toggle_new_collection_form" class="btn btn-ghost btn-xs -mt-2 mb-2">
            + New collection
          </button>

          <%!-- Dimensions --%>
          <div class="grid grid-cols-3 gap-4">
            <.input field={@form[:width]}  type="number" label="Width"  step="any" phx-debounce="blur" />
            <.input field={@form[:length]} type="number" label="Length" step="any" phx-debounce="blur" />
            <.input field={@form[:height]} type="number" label="Height" step="any" phx-debounce="blur" />
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
                <%!-- Only show the required asterisk when there are no existing images --%>
                <span :if={@existing_images == []} class="text-error">*</span>
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
                  <div class="flex flex-col gap-1 tooltip tooltip-right" data-tip="Use arrows to change the ordering of images">
                    <%!-- ↑ hidden on the first image --%>
                    <button
                      :if={index > 0}
                      type="button"
                      phx-click="move_image_up"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >↑</button>
                    <%!-- ↓ hidden on the last image --%>
                    <button
                      :if={index < length(@existing_images) - 1}
                      type="button"
                      phx-click="move_image_down"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >↓</button>
                  </div>
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

          <.button_artsy variant="primary" disable_with="Saving...">
            Save Product
          </.button_artsy>

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
              <button type="button" phx-click="toggle_new_collection_form" class="btn btn-ghost btn-sm">Cancel</button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="toggle_new_collection_form"></div>
      </div>

    </Layouts.artsy_main>
    """
  end
end
