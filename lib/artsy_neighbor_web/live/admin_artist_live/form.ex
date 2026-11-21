defmodule ArtsyNeighborWeb.AdminArtistLive.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighborWeb.PhotoUploads

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> PhotoUploads.allow_photos(:profile_images)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  # Needed for the push_patch/2 to the edit page after a new artist's
  # photo was refused (see handle_async/3). Nothing to do here.
  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp apply_action(socket, :edit, %{"id" => id}) do
    artist = Artists.get_artist!(id)

    # Convert medium array to comma-separated string for display in form
    artist_with_string_medium =
      Map.update!(artist, :medium, fn medium_list ->
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
    {:noreply, PhotoUploads.cancel_photo(socket, :profile_images, ref)}
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
      case Artists.delete_artist_image(image) do
        {:ok, _} ->
          {:noreply, reload_existing_images(socket)}

        # e.g. already removed in another browser tab
        {:error, :not_found} ->
          {:noreply,
           socket
           |> reload_existing_images()
           |> put_flash(:info, "That photo had already been removed.")}

        {:error, :last_photo_of_active_profile} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "An active profile must have at least one photo. Upload another photo " <>
               "before removing this one, or set the profile to inactive first."
           )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  # Ignore a second press while photos are still being saved.
  def handle_event("save", _params, %{assigns: %{saving_photos: true}} = socket) do
    {:noreply, socket}
  end

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

  defp reload_existing_images(socket) do
    artist = Artists.get_artist!(socket.assigns.artist.id)
    assign(socket, :existing_profile_images, artist.artist_images)
  end

  # Saving happens in three steps, in this order:
  #   1. the profile fields (update_artist/2 or create_artist/1, which
  #      never change the status; a new profile starts :inactive);
  #   2. the uploaded photos, processed in the background (see
  #      ArtsyNeighborWeb.PhotoUploads; handle_async/3 carries on);
  #   3. the status, if the dropdown asks for a different one, through
  #      Artists.change_status/2, which applies the rules (e.g. a public
  #      profile needs a photo, so the photos must be saved first).
  defp save_artist(socket, :edit, artist_params) do
    case Artists.update_artist(socket.assigns.artist, artist_params) do
      {:ok, artist} ->
        save_photos(
          socket,
          artist,
          artist_params["status"],
          "Artist profile is updated successfully."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_artist(socket, :new, artist_params) do
    case Artists.create_artist(artist_params) do
      {:ok, artist} ->
        save_photos(
          socket,
          artist,
          artist_params["status"],
          "Artist profile is created successfully."
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # Step 2. What step 3 needs is kept in assigns until the photos are done.
  defp save_photos(socket, artist, requested_status, success_message) do
    socket =
      assign(socket,
        artist: artist,
        requested_status: requested_status,
        success_message: success_message
      )

    folder = "artists/#{artist.id}"
    # New photos go after the ones already there.
    first_position = length(socket.assigns.existing_profile_images) + 1

    create_row = fn key, position ->
      Artists.create_artist_image(artist, %{path: key, position: position})
    end

    case PhotoUploads.start_processing(
           socket,
           :profile_images,
           folder,
           first_position,
           create_row
         ) do
      {:no_photos, socket} -> finish_save(socket, artist, requested_status, success_message)
      {:started, socket} -> {:noreply, socket}
      {:not_ready, socket} -> stay_with_photo_problem(socket, artist)
    end
  end

  @impl true
  def handle_async(:process_photos, result, socket) do
    artist = socket.assigns.artist
    {socket, outcome} = PhotoUploads.finish_processing(socket, :profile_images, result)

    if outcome.failed > 0 do
      stay_with_photo_problem(socket, artist)
    else
      finish_save(
        socket,
        artist,
        socket.assigns.requested_status,
        socket.assigns.success_message
      )
    end
  end

  # A photo was refused: stay, so it stays visible with its message.
  # The status isn't changed: the admin should see the photo problem
  # first (a public profile needs a photo).
  defp stay_with_photo_problem(socket, artist) do
    artist = Artists.get_artist!(artist.id)

    socket =
      socket
      |> assign(:page_title, "Edit Artist Profile")
      |> assign(:artist, artist)
      |> reload_existing_images()

    message =
      PhotoUploads.problem_flash(socket, "The profile is saved, but its status wasn't changed.")

    socket = put_flash(socket, :error, message)

    # Switch a new artist's page to its edit address, so saving again
    # doesn't create a second artist.
    if socket.assigns.live_action == :new do
      {:noreply, push_patch(socket, to: ~p"/admin/artists/#{artist.id}/edit")}
    else
      {:noreply, socket}
    end
  end

  # Step 3 (see save_artist/3). The profile and photos are already saved,
  # so if the status change is refused, the admin is taken to the
  # artist's edit page with the reason.
  defp finish_save(socket, artist, requested_status, success_message) do
    case change_requested_status(artist, requested_status) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, success_message)
         |> push_navigate(to: ~p"/admin/artists")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "The profile is saved, but its status wasn't changed: " <> reason)
         |> push_navigate(to: ~p"/admin/artists/#{artist.id}/edit")}
    end
  end

  # Returns :ok, or {:error, reason} with the reason in words.
  defp change_requested_status(_artist, nil), do: :ok
  defp change_requested_status(_artist, ""), do: :ok

  defp change_requested_status(artist, requested_status) do
    case Artists.change_status(artist, requested_status) do
      {:ok, _artist} ->
        :ok

      {:error, %Ecto.Changeset{} = changeset} ->
        messages =
          for {_field, {message, _details}} <- changeset.errors do
            message
          end

        {:error, Enum.join(messages, " ")}

      {:error, :user_missing} ->
        {:error, "the artist's user account no longer exists."}

      {:error, :invalid_status} ->
        {:error, "unknown status #{inspect(requested_status)}."}

      {:error, other} ->
        {:error, inspect(other)}
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
        <.back navigate={~p"/admin/artists"}>
          Back
        </.back>

        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="artist_form" phx-submit="save" phx-change="validate">
          <%!-- ===== IDENTITY ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Identity
            </h3>
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

          <%!-- ===== IMAGES ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Images
            </h3>
            <p class="text-sm text-base-content/60 mb-4">
              <PhotoUploads.accepted_help />
            </p>

            <%!-- Photos already stored, with ↑ ↓ and Remove buttons --%>
            <PhotoUploads.stored_photos
              images={@existing_profile_images}
              saving_photos={@saving_photos}
            />

            <%!-- Upload new images --%>
            <p class="text-xs text-base-content/50 mb-2">
              New images are appended after existing ones. Save first, then reorder.
            </p>
            <PhotoUploads.photo_picker
              upload={@uploads.profile_images}
              photo_prep={@photo_prep}
              photo_errors={@photo_errors}
              saving_photos={@saving_photos}
            />
          </div>

          <%!-- ===== CONTACT ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Contact
            </h3>
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
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Location
            </h3>
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
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Artist Profile
            </h3>
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
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Announcement Banner
            </h3>
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

          <%!-- ===== ONLINE PRESENCE ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Online Presence
            </h3>
            <div class="grid grid-cols-3 gap-4">
              <.input field={@form[:homepage]} label="Homepage" placeholder="https://..." />
              <.input
                field={@form[:facebook]}
                label="Facebook"
                placeholder="https://facebook.com/..."
              />
              <.input
                field={@form[:instagram]}
                label="Instagram"
                placeholder="https://instagram.com/..."
              />
            </div>
          </div>

          <%!-- ===== STATUS ===== --%>
          <div class="bg-base-200 rounded-xl p-5 mb-4">
            <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide mb-3">
              Profile Status
            </h3>
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
            <.button_artsy variant="primary" disable_with="Submitting..." disabled={@saving_photos}>
              Save Artist
            </.button_artsy>
            <PhotoUploads.photo_status saving_photos={@saving_photos} photo_problem={@photo_problem} />
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
