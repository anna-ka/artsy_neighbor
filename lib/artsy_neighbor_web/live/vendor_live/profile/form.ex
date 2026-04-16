defmodule ArtsyNeighborWeb.VendorLive.Profile.Form do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(return_to: nil, return_label: nil)
      |> allow_upload(:profile_images, accept: ~w(.jpg .jpeg .png .webp), max_entries: 5, max_file_size: 5_000_000)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
          socket
          |> assign(:return_to, Map.get(params, "return_to"))
          |> assign(:return_label, Map.get(params, "return_label"))

    {:noreply, socket}
  end

  defp apply_action(socket, :edit, _params) do
    artist = socket.assigns.current_scope.artist
    case artist do
      nil ->
        socket
        |> put_flash(:error, "Artist profile not found for this user.")
        |> redirect(to: ~p"/vendor/profile/new")

      artist ->
        artist = Artists.get_artist!(artist.id)

        artist_with_string_medium = Map.update!(artist, :medium, fn medium_list ->
          if is_list(medium_list), do: Enum.join(medium_list, ", "), else: medium_list
        end)

        changeset = Artists.change_artist(artist_with_string_medium)

        socket
        |> assign(:page_title, "Edit My Artist Profile")
        |> assign(:form, to_form(changeset))
        |> assign(:artist, artist)
        |> assign(:existing_profile_images, Enum.sort_by(artist.artist_images, & &1.position))
    end
  end

  defp apply_action(socket, :new, _) do
    user_id = socket.assigns.current_scope.user.id
    case user_id do
      nil ->
        socket
        |> put_flash(:error, "You must be logged in with a confirmed account to create an artist profile.")
        |> redirect(to: ~p"/users/log-in")

      user_id ->
        email = socket.assigns.current_scope.user.email
        changeset = Artists.change_artist(%Artist{user_id: user_id}, %{"email" => email})

        socket
        |> assign(:page_title, "Create My Artist Profile")
        |> assign(:form, to_form(changeset))
        |> assign(:artist, %Artist{user_id: user_id})
        |> assign(:existing_profile_images, [])
    end
  end

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

   @impl true
  def handle_event("save", %{"artist" => artist_params}, socket) do
    artist_params = parse_medium_field(artist_params)

    if socket.assigns.live_action == :new &&
       Enum.empty?(socket.assigns.uploads.profile_images.entries) &&
       Enum.empty?(socket.assigns.existing_profile_images) do
      {:noreply, put_flash(socket, :error, "Please upload at least one profile image.")}
    else
      save_artist(socket, socket.assigns.live_action, artist_params)
    end
  end

  @impl true
  def handle_event("validate", %{"artist" => artist_params}, socket) do
    original_medium_string = artist_params["medium"]
    artist_params = parse_medium_field(artist_params)
    changeset = Artists.change_artist(socket.assigns.artist, artist_params)

    changeset =
      if is_binary(original_medium_string) do
        Ecto.Changeset.put_change(changeset, :medium, original_medium_string)
      else
        changeset
      end

    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end


  defp reload_existing_images(socket) do
    artist = Artists.get_artist!(socket.assigns.artist.id)
    assign(socket, :existing_profile_images, Enum.sort_by(artist.artist_images, & &1.position))
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
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_artist(socket, :new, artist_params) do
    artist_params = Map.put(artist_params, "user_id", socket.assigns.current_scope.user.id)

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
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp error_to_string(:too_large),      do: "File too large (max 5 MB)"
  defp error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp error_to_string(:not_accepted),   do: "File type not accepted (jpg, png, webp only)"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} variant="vendor" nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread_messages}>
      <div class="w-full px-8 py-8">

      <div>
      <.back :if={@return_to && @return_label} navigate={@return_to}>
        {@return_label}
      </.back>
      </div>

      <.header>
        <%= @page_title  %>
      </.header>

      <.form for={@form} id="artist_form" phx-submit="save" phx-change="validate">

      <div>
      <p class="text-sm text-base-content/70">Note: only the fields marked "Visible to customers" are shown on your public profile. Your address (except the area code), phone and email are not visible to customers.
      <br>
      Fields marked with asterix <span class="text-error">*</span> are required.
      <br>
      <br>
      </p>
      </div>

        <%!-- Nickname --%>
        <.input
          field={@form[:nickname]}
          label={raw("Nickname <span class=\"text-error\">*</span>")}
          placeholder="Name as shown to customers"
          required
          phx-debounce="blur"
        />

        <%!-- First Name --%>
        <.input
          field={@form[:first_name]}
          label={raw("First Name <span class=\"text-error\">*</span>")}
          required
          phx-debounce="blur"
        />

        <%!-- Last Name --%>
        <.input
          field={@form[:last_name]}
          label={raw("Last Name <span class=\"text-error\">*</span>")}
          required
          phx-debounce="blur"
        />

        <%!-- Middle Name --%>
        <.input
          field={@form[:middle_name]}
          label="Middle Name"
        />

        <%!-- Email --%>
        <.input
          field={@form[:email]}
          type="email"
          label={raw("Email <span class=\"text-error\">*</span>")}
          required
          phx-debounce="blur"
        />

        <%!-- Phone --%>
        <.input
          field={@form[:phone]}
          type="tel"
          label={raw("Phone <span class=\"text-error\">*</span>")}
          placeholder="e.g., 416-555-0101"
          required
          phx-debounce="blur"
        />

        <%!-- Street Address --%>
        <.input
          field={@form[:street_address]}
          label={raw("Street Address <span class=\"text-error\">*</span>")}
          required
          phx-debounce="blur"
        />

        <%!-- Apartment Info --%>
        <.input
          field={@form[:apt_info]}
          label="Apartment/Unit"
          placeholder="e.g., Suite 3B, Unit 405"
          phx-debounce="blur"
        />

        <%!-- Area Code / Neighborhood --%>
        <.input
          field={@form[:area_code]}
          label={raw("Area Code / Neighborhood <span class=\"text-error\">*</span>")}
          placeholder="e.g., M5V 2T6"
          required
          phx-debounce="blur"
        />

        <%!-- Bio --%>
        <.input
          field={@form[:bio]}
          type="textarea"
          label={raw("Bio <span class=\"text-error\">*</span>")}
          rows="4"
          required
          phx-debounce="blur"
        />

        <%!-- Medium (array of strings) --%>
        <.input
          field={@form[:medium]}
          label={raw("Mediums (comma-separated) <span class=\"text-error\">*</span>")}
          placeholder="e.g., Oil painting, Acrylic painting, Mixed media"
          required
          phx-debounce="blur"
        />

        <%!-- ============================================================
             ANNOUNCEMENT
             ============================================================ --%>
        <div class="divider mt-6">Announcement Banner</div>
        <p class="text-sm text-base-content/60 mb-4">
          Optional short message shown at the top of your public profile and store pages.
          Use it for news like new collections, upcoming events, or availability changes.
        </p>
        <.input
          field={@form[:announcement]}
          type="textarea"
          label="Announcement text"
          placeholder="e.g. I'll be at the Toronto Art Fair, booth 42 — come say hi!"
          rows="2"
          phx-debounce="blur"
        />
        <.input
          field={@form[:announcement_active]}
          type="checkbox"
          label="Show this announcement on my public pages"
        />

        <%!-- ============================================================
             PROFILE IMAGE UPLOADS
             ============================================================ --%>
        <div class="divider mt-6">Profile Images</div>
        <p class="text-sm text-base-content/60 mb-4">
          Accepted formats: jpg, png, webp · max 5 MB each · up to 5 images total.
          The first image is your main profile photo.
        </p>

        <%!-- Existing images with reorder/delete --%>
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
        <%!-- ============================================================ --%>

        <.button_artsy variant="primary" disable_with="Submitting...">
          Save Artist
        </.button_artsy>

      </.form>

      <.back navigate={~p"/vendor"}>
          Back
        </.back>
      </div>
      </Layouts.artsy_main>
    """
  end

end
