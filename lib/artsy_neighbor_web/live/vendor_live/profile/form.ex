defmodule ArtsyNeighborWeb.VendorLive.Profile.Form do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighborWeb.PhotoUploads

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  @impl true
  def mount(params, _session, socket) do
    if socket.assigns.current_scope.artist && socket.assigns.live_action == :new do
      {:ok, push_navigate(socket, to: ~p"/vendor/profile/edit")}
    else
      socket =
        socket
        |> assign(return_to: nil, return_label: nil)
        |> PhotoUploads.allow_photos(:profile_images)

      {:ok, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    step =
      case socket.assigns.current_scope.artist do
        nil -> -1
        %{onboarding_complete: true} -> -1
        %{onboarding_step: 1} -> 2
        %{onboarding_step: 2} -> 3
        _ -> -1
      end

    socket =
      socket
      |> assign(:return_to, Map.get(params, "return_to"))
      |> assign(:return_label, Map.get(params, "return_label"))
      |> assign(step: step)

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

        artist_with_string_medium =
          Map.update!(artist, :medium, fn medium_list ->
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
        |> put_flash(
          :error,
          "You must be logged in with a confirmed account to create an artist profile."
        )
        |> redirect(to: ~p"/users/log-in")

      user_id ->
        email = socket.assigns.current_scope.user.email

        changeset =
          Artists.registration_change_artist(%Artist{user_id: user_id}, %{"email" => email})

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
             "Your profile is public, so it must have at least one photo. " <>
               "Please upload another photo before removing this one. " <>
               "If you'd like to hide your profile from the public instead, " <>
               "use the \"De-activate profile\" button on your dashboard."
           )}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  # Ignore a second press while photos are still being saved.
  def handle_event("next_step", _params, %{assigns: %{saving_photos: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("next_step", _params, socket) do
    save_and_advance(socket)
  end

  @impl true
  # While step 2's photos are being saved, stay on step 2 (the Previous
  # button is disabled then too): when they're done, the form moves on
  # from step 2.
  def handle_event("prev_step", _params, %{assigns: %{saving_photos: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("prev_step", _params, socket) do
    new_step = if socket.assigns.step in [-1, 1], do: 1, else: socket.assigns.step - 1
    {:noreply, assign(socket, step: new_step)}
  end

  @impl true
  # Ignore saving while photos are being saved: leaving the page would
  # stop the photos half-way.
  def handle_event("save", _params, %{assigns: %{saving_photos: true}} = socket) do
    {:noreply, socket}
  end

  # Pressing Enter in a one-line field submits the form ("save") on any
  # step. Before the last step that means "Next", so step 2's photos are
  # saved the same way as with the Next button, not skipped.
  def handle_event("save", _params, %{assigns: %{step: step}} = socket) when step in [-1, 1, 2] do
    save_and_advance(socket)
  end

  def handle_event("save", params, socket) do
    artist_params = params |> Map.get("artist", %{}) |> parse_medium_field()

    # A profile photo isn't required to save: the profile just can't be
    # made public (activated) without one — see Artists.update_artist/2.
    save_artist(socket, socket.assigns.live_action, artist_params)
  end

  @impl true
  def handle_event("validate", %{"artist" => artist_params}, socket) do
    original_medium_string = artist_params["medium"]
    artist_params = parse_medium_field(artist_params)

    changeset =
      case socket.assigns.step do
        step when step in [-1, 1] ->
          Artists.registration_change_artist(socket.assigns.artist, artist_params)

        _ ->
          Artists.change_artist(socket.assigns.artist, artist_params)
      end

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

  defp save_and_advance(socket) do
    current_step = socket.assigns.step
    changeset = socket.assigns.form.source |> fix_medium_for_save()
    onboarding_complete = socket.assigns.artist.onboarding_complete

    result =
      if onboarding_complete do
        Artists.update_artist(changeset)
      else
        step_to_save = if current_step in [-1, 1], do: 1, else: current_step
        Artists.save_onboarding_progress(changeset, step_to_save)
      end

    case result do
      {:ok, artist} ->
        if !onboarding_complete && current_step in [-1, 1] do
          {:noreply, push_navigate(socket, to: ~p"/vendor/profile/edit")}
        else
          new_step = if current_step in [-1, 1], do: 2, else: current_step + 1

          socket =
            socket
            |> assign(:artist, artist)
            |> reinit_form_for_next_step(artist, current_step)

          if current_step == 2 do
            save_photos(socket, artist)
          else
            {:noreply, assign(socket, step: new_step)}
          end
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  defp fix_medium_for_save(changeset) do
    case Ecto.Changeset.get_change(changeset, :medium) do
      medium when is_binary(medium) ->
        parsed =
          medium
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Ecto.Changeset.put_change(changeset, :medium, parsed)

      _ ->
        changeset
    end
  end

  defp reinit_form_for_next_step(socket, artist, step) when step in [-1, 1] do
    artist_display =
      Map.update!(artist, :medium, fn m ->
        if is_list(m), do: Enum.join(m, ", "), else: m || ""
      end)

    assign(socket, :form, to_form(Artists.change_artist(artist_display)))
  end

  defp reinit_form_for_next_step(socket, _artist, _step), do: socket

  # Step 2's photos. They are processed in the background (see
  # ArtsyNeighborWeb.PhotoUploads); handle_async/3 then moves on to
  # step 3, or stays on step 2 if a photo was refused or the artist
  # should check the order of the photos.
  defp save_photos(socket, artist) do
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
      {:no_photos, socket} ->
        {:noreply, assign(socket, step: 3)}

      {:started, socket} ->
        {:noreply, socket}

      {:not_ready, socket} ->
        {:noreply,
         put_flash(socket, :error, PhotoUploads.problem_flash(socket, "Your profile is saved."))}
    end
  end

  @impl true
  def handle_async(:process_photos, result, socket) do
    {socket, outcome} = PhotoUploads.finish_processing(socket, :profile_images, result)

    socket = reload_existing_images(socket)
    total_photos = length(socket.assigns.existing_profile_images)

    cond do
      outcome.failed > 0 ->
        {:noreply,
         put_flash(socket, :error, PhotoUploads.problem_flash(socket, "Your profile is saved."))}

      reminder = PhotoUploads.order_reminder(outcome, total_photos) ->
        {:noreply, put_flash(socket, :info, reminder <> " Then press Next.")}

      true ->
        {:noreply, assign(socket, step: 3)}
    end
  end

  defp save_artist(socket, :edit, artist_params) do
    artist_params = Map.put(artist_params, "onboarding_complete", true)

    case Artists.update_artist(socket.assigns.artist, artist_params) do
      {:ok, _artist} ->
        # Photos were already saved on step 2 (save_photos/2).
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

    result =
      if socket.assigns.artist.id do
        Artists.update_artist(socket.assigns.artist, artist_params)
      else
        Artists.create_artist(artist_params)
      end

    case result do
      {:ok, _artist} ->
        # Photos were already saved on step 2 (save_photos/2).
        {:noreply,
         socket
         |> put_flash(:info, "Artist profile is created successfully.")
         |> push_navigate(to: ~p"/vendor")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
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
        <div>
          <.back :if={@return_to && @return_label} navigate={@return_to}>
            {@return_label}
          </.back>
        </div>

        <.header>
          {@page_title}
        </.header>

        <p>Step: {@step}</p>

        <.form for={@form} id="artist_form" phx-submit="save" phx-change="validate">
          <div>
            <p class="text-sm text-base-content/70">
              Please note: most of the information requested by the form is not visible to public.
              Only the fields marked "Visible to customers" are shown on your public profile. Your address (except the area code), phone and email are NOT visible to customers.
              <br />
              <br /> Fields marked with asterix <span class="text-error">*</span>
              are required to sell your art on our platform. <br />
              <br />
            </p>
          </div>

          <div>
            <ul class="steps w-full mb-8">
              <li class={["step", (@step >= 1 or @step == -1) && "step-error"]}>Shop Info</li>
              <li class={["step", @step >= 2 && "step-error"]}>Bio & Images</li>
              <li class={["step", @step >= 3 && "step-error"]}>Payment</li>
            </ul>

            <%!-- Step content --%>
            <%= case @step do %>
              <% step when step in [1, -1] -> %>
                <%!-- Step 1 form fields: name, address, etc. --%>

                <%!-- Nickname --%>
                <.input
                  field={@form[:nickname]}
                  label={
                    raw(
                      "Store name (visible to customers, 2–200 characters) <span class=\"text-error\">*</span>"
                    )
                  }
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
                  label={
                    raw(
                      "Area Code / Neighborhood (visible to customers) <span class=\"text-error\">*</span>"
                    )
                  }
                  placeholder="e.g., M5V 2T6"
                  required
                  phx-debounce="blur"
                />
              <% 2 -> %>
                <%!-- Step 2 form fields: images first (so they upload while
                     the artist fills in the rest), then bio --%>
                <%!-- ============================================================
             PROFILE IMAGE UPLOADS
             ============================================================ --%>
                <div class="divider">Profile Images</div>
                <p class="text-sm text-base-content/60 mb-4">
                  <PhotoUploads.accepted_help />. Visible to customers.
                  The first image is your main profile photo.
                  You need at least one photo before you can make your profile public.
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
                  photo_errors={@photo_errors}
                  saving_photos={@saving_photos}
                />
                <%!-- ============================================================ --%>

                <%!-- Bio --%>
                <.input
                  field={@form[:bio]}
                  type="textarea"
                  label={
                    raw(
                      "Bio (visible to customers, 75–4000 characters) <span class=\"text-error\">*</span>"
                    )
                  }
                  rows="4"
                  required
                  phx-debounce="blur"
                />

                <%!-- Medium (array of strings) --%>
                <.input
                  field={@form[:medium]}
                  label={
                    raw(
                      "Mediums, comma-separated. (visible to customers) <span class=\"text-error\">*</span>"
                    )
                  }
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
                  label="Announcement text — max 100 characters. Visible to customers if the announcement is active."
                  placeholder="e.g. I'll be at the Toronto Art Fair, booth 42 — come say hi!"
                  rows="2"
                  phx-debounce="blur"
                />
                <.input
                  field={@form[:announcement_active]}
                  type="checkbox"
                  label="Show this announcement on my public pages"
                />
              <% 3 -> %>
                <%!-- Step 3: payment placeholder --%>
                <div>
                  Payment info stub
                </div>
            <% end %>
          </div>

          <%!-- <.button_artsy variant="primary" disable_with="Submitting...">
          Save Artist
        </.button_artsy> --%>

          <%!-- Navigation buttons --%>
          <div class="flex justify-between mt-6">
            <button
              :if={@step > 1}
              type="button"
              phx-click="prev_step"
              class="btn btn-primary"
              disabled={@saving_photos}
            >
              Previous
            </button>
            <button
              :if={@step < 3}
              type="button"
              phx-click="next_step"
              class="btn btn-primary"
              disabled={@saving_photos}
            >
              Next
            </button>
            <%!-- <button :if={@step == 3} type="submit" class="btn btn-primary">
            Save Profile
          </button> --%>
            <.button_artsy :if={@step == 3} variant="primary" disable_with="Submitting...">
              Save Artist
            </.button_artsy>
          </div>
          <PhotoUploads.photo_status saving_photos={@saving_photos} photo_problem={@photo_problem} />
        </.form>

        <.back navigate={~p"/vendor"}>
          Back
        </.back>
      </div>
    </Layouts.artsy_main>
    """
  end
end
