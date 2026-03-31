defmodule ArtsyNeighborWeb.AdminProductLive.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Categories

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 5,
        max_file_size: 5_000_000
      )
      |> apply_action(socket.assigns.live_action, params)

    {:ok, socket}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    product = Products.get_product_with_associations!(id)

    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, product)
    |> assign(:existing_images, product.product_images)
    |> assign(:form, to_form(Products.change_product(product)))
    |> assign_selects(product.artist_id)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, %Product{})
    |> assign(:existing_images, [])
    |> assign(:form, to_form(Products.change_product(%Product{})))
    |> assign_selects(nil)
  end

  defp assign_selects(socket, artist_id) do
    artists = Artists.list_artists() |> Enum.map(fn a -> {a.nickname, a.id} end)
    categories = Categories.list_categories() |> Enum.map(fn c -> {c.name, c.id} end)
    collections = collections_for(artist_id)

    socket
    |> assign(:artists, artists)
    |> assign(:categories, categories)
    |> assign(:collections, collections)
  end

  defp collections_for(nil), do: []
  defp collections_for(artist_id) do
    Products.list_collections_for_artist(artist_id)
    |> Enum.map(fn c -> {c.name, c.id} end)
  end

  @impl true
  def handle_event("artist_changed", %{"product" => %{"artist_id" => artist_id}}, socket) do
    artist_id = if artist_id == "", do: nil, else: String.to_integer(artist_id)
    collections = collections_for(artist_id)
    changeset = Products.change_product(socket.assigns.product, %{"artist_id" => artist_id})

    {:noreply,
     socket
     |> assign(:collections, collections)
     |> assign(:form, to_form(changeset, action: :validate))}
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
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :images, ref)}
  end

  @impl true
  def handle_event("move_image_up", %{"imageid" => image_id}, socket) do
    image_id = String.to_integer(image_id)
    images = socket.assigns.existing_images
    index = Enum.find_index(images, fn img -> img.id == image_id end)

    if index && index > 0 do
      Products.swap_image_positions(Enum.at(images, index), Enum.at(images, index - 1))
      {:noreply, reload_existing_images(socket)}
    else
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
      {:noreply, socket}
    end
  end

  defp reload_existing_images(socket) do
    product = Products.get_product_with_associations!(socket.assigns.product.id)
    assign(socket, :existing_images, product.product_images)
  end

  defp save_product(socket, :new, product_params) do
    case Products.create_product(product_params) do
      {:ok, product} ->
        upload_images(socket, product, 1)

        {:noreply,
         socket
         |> put_flash(:info, "Product created successfully.")
         |> push_navigate(to: ~p"/admin/products")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_product(socket, :edit, product_params) do
    case Products.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        existing_count = length(socket.assigns.existing_images)
        upload_images(socket, product, existing_count + 1)

        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully.")
         |> push_navigate(to: ~p"/admin/products")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp upload_images(socket, product, start_position) do
    upload_dir = Path.join([:code.priv_dir(:artsy_neighbor), "static", "uploads", "products"])
    File.mkdir_p!(upload_dir)

    consume_uploaded_entries(socket, :images, fn %{path: tmp_path}, entry ->
      ext = Path.extname(entry.client_name)
      filename = "#{Ecto.UUID.generate()}#{ext}"
      File.cp!(tmp_path, Path.join(upload_dir, filename))
      {:ok, "/uploads/products/#{filename}"}
    end)
    |> Enum.with_index(start_position)
    |> Enum.each(fn {path, position} ->
      Products.create_product_image(%{path: path, position: position, product_id: product.id})
    end)
  end

  defp error_to_string(:too_large),      do: "File too large (max 5 MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(:not_accepted),   do: "File type not accepted (jpg, png, webp only)"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} variant="admin" nav_categories={@nav_categories}>
      <div class="w-full px-8 py-8">

        <.back navigate={~p"/admin/products"}>
          Admin Products
        </.back>

        <.header>
          <%= @page_title %>
        </.header>

        <.form for={@form} id="product-form" phx-change="validate" phx-submit="save">

          <%!-- ===== PRODUCT DETAILS ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Product Details</h3>
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

          <%!-- ===== CLASSIFICATION ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Classification</h3>
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
              prompt={if @collections == [], do: "Select an artist first", else: "Select a collection"}
              options={@collections}
              disabled={@collections == []}
            />
          </div>

          <%!-- ===== DIMENSIONS & MATERIALS ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Dimensions & Materials</h3>
            <div class="grid grid-cols-3 gap-4">
              <.input field={@form[:width]}  type="number" label="Width"  step="any" phx-debounce="blur" />
              <.input field={@form[:length]} type="number" label="Length" step="any" phx-debounce="blur" />
              <.input field={@form[:height]} type="number" label="Height" step="any" phx-debounce="blur" />
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

          <%!-- ===== IMAGES ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Images</h3>
            <p class="text-sm text-base-content/60 mb-4">
              Up to 5 files · jpg, png, webp · max 5 MB each
            </p>

            <div :if={@existing_images != []} class="mb-4">
              <p class="text-sm text-base-content/60 mb-2">Already uploaded:</p>
              <div class="flex flex-col gap-3">
                <div
                  :for={{img, index} <- Enum.with_index(@existing_images)}
                  class="flex items-center gap-3"
                >
                  <img src={img.path} class="w-24 h-24 object-cover rounded-lg border border-base-300" />
                  <div class="flex flex-col gap-1 tooltip tooltip-right" data-tip="Reorder images">
                    <button
                      :if={index > 0}
                      type="button"
                      phx-click="move_image_up"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >↑</button>
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

            <.live_file_input upload={@uploads.images} class="file-input file-input-bordered w-full" />
            <p class="text-xs text-base-content/50 mt-1">New images are appended after existing ones.</p>

            <div class="space-y-3 mt-3">
              <div :for={entry <- @uploads.images.entries} class="flex items-center gap-3">
                <.live_img_preview entry={entry} class="w-16 h-16 object-cover rounded-lg border border-base-300" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm truncate">{entry.client_name}</p>
                  <progress value={entry.progress} max="100" class="progress progress-primary w-full" />
                </div>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs text-error"
                >✕</button>
                <p :for={err <- upload_errors(@uploads.images, entry)} class="text-error text-xs">
                  {error_to_string(err)}
                </p>
              </div>
            </div>

            <p :for={err <- upload_errors(@uploads.images)} class="text-error text-sm mt-2">
              {error_to_string(err)}
            </p>
          </div>

          <div class="mt-6">
            <.button_artsy variant="primary" disable_with="Saving...">
              Save Product
            </.button_artsy>
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
