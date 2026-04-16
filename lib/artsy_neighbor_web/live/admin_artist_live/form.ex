defmodule ArtsyNeighborWeb.AdminArtistLive.Form do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Accounts

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> allow_upload(:profile_images, accept: ~w(.jpg .jpeg .png .webp), max_entries: 5, max_file_size: 5_000_000)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    artist = Artists.get_artist!(id)

    # Convert medium array to comma-separated string for display in form
    artist_with_string_medium = Map.update!(artist, :medium, fn medium_list ->
      if is_list(medium_list) do
        Enum.join(medium_list, ", ")
      else
        medium_list
      end
    end)

    changeset = Artists.change_artist(artist_with_string_medium)

    socket
    |> assign(:page_title, "Edit Artist Profile")
    |> assign(:form, to_form(changeset))
    |> assign(:artist, artist)
    |> assign(:existing_profile_images, artist.artist_images)
    |> assign(:users, Accounts.list_users())
  end

  defp apply_action(socket, :new, _params) do
    changeset = Artists.change_artist(%Artist{}, %{})

    socket
    |> assign(:page_title, "New Artist")
    |> assign(:form, to_form(changeset))
    |> assign(:artist, %Artist{})
    |> assign(:existing_profile_images, [])
    |> assign(:users, Accounts.list_users())
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :profile_images, ref)}
  end

  @impl true
  def handle_event("move_image_up", %{"imageid" => id}, socket) do
    id = String.to_integer(id)
    images = socket.assigns.existing_profile_images
    index = Enum.find_index(images, fn img -> img.id == id end)

    if index && index > 0 do
      Artists.swap_image_positions(Enum.at(images, index), Enum.at(images, index - 1))
      {:noreply, reload_existing_images(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_image_down", %{"imageid" => id}, socket) do
    id = String.to_integer(id)
    images = socket.assigns.existing_profile_images
    index = Enum.find_index(images, fn img -> img.id == id end)

    if index && index < length(images) - 1 do
      Artists.swap_image_positions(Enum.at(images, index), Enum.at(images, index + 1))
      {:noreply, reload_existing_images(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_image", %{"imageid" => id}, socket) do
    id = String.to_integer(id)
    images = socket.assigns.existing_profile_images
    image = Enum.find(images, fn img -> img.id == id end)

    if image do
      Artists.delete_artist_image(image)
      {:noreply, reload_existing_images(socket)}
    else
      {:noreply, socket}
    end
  end

  defp reload_existing_images(socket) do
    artist = Artists.get_artist!(socket.assigns.artist.id)
    assign(socket, :existing_profile_images, artist.artist_images)
  end

  @impl true
  def handle_event("save", %{"artist" => artist_params}, socket) do
    artist_params = parse_medium_field(artist_params)
    save_artist(socket, socket.assigns.live_action, artist_params)
  end

  @impl true
  def handle_event("validate", %{"artist" => artist_params}, socket) do
    # Store the original medium string before parsing
    original_medium_string = artist_params["medium"]

    # Parse comma-separated medium string into array for validation
    artist_params = parse_medium_field(artist_params)
    changeset = Artists.change_artist(socket.assigns.artist, artist_params)

    # Convert medium back to string for form display
    changeset =
      if is_binary(original_medium_string) do
        Ecto.Changeset.put_change(changeset, :medium, original_medium_string)
      else
        changeset
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  defp save_artist(socket, :edit, artist_params) do
    case Artists.update_artist(socket.assigns.artist, artist_params) do
      {:ok, artist} ->
        existing_count = length(socket.assigns.existing_profile_images)

        upload_dir = Path.join([:code.priv_dir(:artsy_neighbor), "static", "uploads", "artist_profiles"])
        File.mkdir_p!(upload_dir)

        image_paths =
          consume_uploaded_entries(socket, :profile_images, fn %{path: tmp_path}, entry ->
            ext = Path.extname(entry.client_name)
            filename = "#{Ecto.UUID.generate()}#{ext}"
            File.cp!(tmp_path, Path.join(upload_dir, filename))
            {:ok, "/uploads/artist_profiles/#{filename}"}
          end)

        image_paths
        |> Enum.with_index(existing_count + 1)
        |> Enum.each(fn {path, position} ->
          Artists.create_artist_image(artist, %{path: path, position: position})
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Artist profile is updated successfully.")
         |> push_navigate(to: ~p"/admin/artists")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_artist(socket, :new, artist_params) do
    case Artists.create_artist(artist_params) do
      {:ok, artist} ->
        upload_dir = Path.join([:code.priv_dir(:artsy_neighbor), "static", "uploads", "artist_profiles"])
        File.mkdir_p!(upload_dir)

        image_paths =
          consume_uploaded_entries(socket, :profile_images, fn %{path: tmp_path}, entry ->
            ext = Path.extname(entry.client_name)
            filename = "#{Ecto.UUID.generate()}#{ext}"
            File.cp!(tmp_path, Path.join(upload_dir, filename))
            {:ok, "/uploads/artist_profiles/#{filename}"}
          end)

        image_paths
        |> Enum.with_index(1)
        |> Enum.each(fn {path, position} ->
          Artists.create_artist_image(artist, %{path: path, position: position})
        end)

        {:noreply,
         socket
         |> put_flash(:info, "Artist profile is created successfully.")
         |> push_navigate(to: ~p"/admin/artists")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp error_to_string(:too_large),     do: "File too large (max 5 MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(:not_accepted),  do: "File type not accepted (jpg, png, webp only)"

  defp parse_medium_field(params) do
    case params["medium"] do
      medium when is_binary(medium) ->
        medium_list =
          medium
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "medium", medium_list)

      _ ->
        params
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} variant="admin" nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread_messages}>
      <div class="w-full px-8 py-8">

        <.back navigate={~p"/admin/artists"}>
          Back
        </.back>

        <.header>
          <%= @page_title %>
        </.header>

        <.form for={@form} id="artist_form" phx-submit="save" phx-change="validate">

          <%!-- ===== IDENTITY ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Identity</h3>
            <.input
              field={@form[:user_id]}
              type="select"
              label={raw("Linked User Account <span class=\"text-error\">*</span>")}
              options={Enum.map(@users, fn u -> {"#{u.username} (#{u.email})", u.id} end)}
              prompt="— select a user —"
            />
            <.input
              field={@form[:nickname]}
              label={raw("Nickname <span class=\"text-error\">*</span>")}
              placeholder="Artist's display name"
              required
              phx-debounce="blur"
            />
            <div class="grid grid-cols-3 gap-4">
              <.input
                field={@form[:first_name]}
                label={raw("First Name <span class=\"text-error\">*</span>")}
                required
                phx-debounce="blur"
              />
              <.input
                field={@form[:middle_name]}
                label="Middle Name"
                phx-debounce="blur"
              />
              <.input
                field={@form[:last_name]}
                label={raw("Last Name <span class=\"text-error\">*</span>")}
                required
                phx-debounce="blur"
              />
            </div>
          </div>

          <%!-- ===== CONTACT ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Contact</h3>
            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:email]}
                type="email"
                label={raw("Email <span class=\"text-error\">*</span>")}
                required
                phx-debounce="blur"
              />
              <.input
                field={@form[:phone]}
                type="tel"
                label={raw("Phone <span class=\"text-error\">*</span>")}
                placeholder="e.g., 416-555-0101"
                required
                phx-debounce="blur"
              />
            </div>
          </div>

          <%!-- ===== LOCATION ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Location</h3>
            <div class="grid grid-cols-3 gap-4">
              <div class="col-span-2">
                <.input
                  field={@form[:street_address]}
                  label={raw("Street Address <span class=\"text-error\">*</span>")}
                  required
                  phx-debounce="blur"
                />
              </div>
              <.input
                field={@form[:apt_info]}
                label="Apartment/Unit"
                placeholder="e.g., Suite 3B"
                phx-debounce="blur"
              />
            </div>
            <.input
              field={@form[:area_code]}
              label={raw("Area Code / Neighborhood <span class=\"text-error\">*</span>")}
              placeholder="e.g., M5V 2T6"
              required
              phx-debounce="blur"
            />
          </div>

          <%!-- ===== ARTIST PROFILE ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Artist Profile</h3>
            <.input
              field={@form[:bio]}
              type="textarea"
              label={raw("Bio <span class=\"text-error\">*</span>")}
              rows="4"
              required
              phx-debounce="blur"
            />
            <.input
              field={@form[:medium]}
              label={raw("Mediums (comma-separated) <span class=\"text-error\">*</span>")}
              placeholder="e.g., Oil painting, Acrylic painting, Mixed media"
              required
              phx-debounce="blur"
            />
          </div>

          <%!-- ===== ANNOUNCEMENT ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Announcement Banner</h3>
            <.input
              field={@form[:announcement]}
              type="textarea"
              label="Announcement text"
              placeholder="e.g. New collection dropping this weekend!"
              rows="2"
              phx-debounce="blur"
            />
            <.input
              field={@form[:announcement_active]}
              type="checkbox"
              label="Show this announcement on public pages"
            />
          </div>

          <%!-- ===== IMAGES ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Images</h3>
            <p class="text-sm text-base-content/60 mb-4">
              Accepted formats: jpg, png, webp · max 5 MB each · up to 5 images total.
            </p>

            <%!-- Existing images with up/down reorder buttons --%>
            <div :if={@existing_profile_images != []} class="mb-4">
              <p class="text-sm text-base-content/60 mb-2">Current images:</p>
              <div class="flex flex-col gap-3">
                <div
                  :for={{img, index} <- Enum.with_index(@existing_profile_images)}
                  class="flex items-center gap-3"
                >
                  <img src={img.path} class="w-24 h-24 object-cover rounded-lg border border-base-300" />
                  <div class="flex flex-col gap-1 tooltip tooltip-right" data-tip="Use arrows to reorder images">
                    <button
                      :if={index > 0}
                      type="button"
                      phx-click="move_image_up"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >↑</button>
                    <button
                      :if={index < length(@existing_profile_images) - 1}
                      type="button"
                      phx-click="move_image_down"
                      phx-value-imageid={img.id}
                      class="btn btn-ghost btn-xs"
                    >↓</button>
                  </div>
                  <button
                    type="button"
                    phx-click="delete_image"
                    phx-value-imageid={img.id}
                    class="btn btn-ghost btn-xs text-error"
                  >✕</button>
                </div>
              </div>
            </div>

            <%!-- Upload new images --%>
            <.live_file_input
              upload={@uploads.profile_images}
              class="file-input file-input-bordered w-full"
            />
            <p class="text-xs text-base-content/50 mt-1">New images are appended after existing ones. Save first, then reorder.</p>

            <div class="space-y-3 mt-3">
              <div :for={entry <- @uploads.profile_images.entries} class="flex items-center gap-3">
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
                <p :for={err <- upload_errors(@uploads.profile_images, entry)} class="text-error text-xs">
                  {error_to_string(err)}
                </p>
              </div>
            </div>

            <p :for={err <- upload_errors(@uploads.profile_images)} class="text-error text-sm mt-2">
              {error_to_string(err)}
            </p>
          </div>

          <%!-- ===== ONLINE PRESENCE ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Online Presence</h3>
            <div class="grid grid-cols-3 gap-4">
              <.input field={@form[:homepage]}  label="Homepage"  placeholder="https://..." />
              <.input field={@form[:facebook]}  label="Facebook"  placeholder="https://facebook.com/..." />
              <.input field={@form[:instagram]} label="Instagram" placeholder="https://instagram.com/..." />
            </div>
          </div>

          <%!-- ===== STATUS ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">Profile Status</h3>
            <.input
              field={@form[:status]}
              type="select"
              label="Status"
              options={
                Ecto.Enum.values(ArtsyNeighbor.Artists.Artist, :status)
                |> Enum.map(fn x -> {String.capitalize(to_string(x)), x} end)
              }
            />
          </div>

          <div class="mt-6">
            <.button_artsy variant="primary" disable_with="Submitting...">
              Save Artist
            </.button_artsy>
          </div>

        </.form>

        <.back navigate={~p"/admin/artists"}>
          Back
        </.back>

      </div>
    </Layouts.artsy_main>
    """
  end
end
