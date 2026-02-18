defmodule ArtsyNeighborWeb.AdminArtistLive.Form do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Admin.AdminArtists
  alias ArtsyNeighbor.Artists.Artist
  # alias ArtsyNeighbor.Repo
  # alias ArtsyNeighbor.Artists

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    artist = AdminArtists.get_artist(id)

    # Convert medium array to comma-separated string for display in form
    artist_with_string_medium = Map.update!(artist, :medium, fn medium_list ->
      if is_list(medium_list) do
        Enum.join(medium_list, ", ")
      else
        medium_list
      end

    end)

    changeset = AdminArtists.get_changeset_for_artist(artist_with_string_medium)

    socket
    |> assign(:page_title, "Edit Artist")
    |> assign(:form, to_form(changeset))
    |> assign(:artist, artist)
  end

  defp apply_action(socket, :new, _params) do
    changeset = AdminArtists.get_changeset_for_artist(%Artist{}, %{})

    socket
    |> assign(:page_title, "New Artist")
    |> assign(:form, to_form(changeset))
    |> assign(:artist, %Artist{})

  end

  def handle_event("save", %{"artist" => artist_params}, socket) do
    # Parse comma-separated medium string into array
    artist_params = parse_medium_field(artist_params)
    save_artist(socket, socket.assigns.live_action, artist_params)
  end

   def handle_event("validate", %{"artist" => artist_params}, socket) do
    # Store the original medium string before parsing
    original_medium_string = artist_params["medium"]

    # Parse comma-separated medium string into array for validation
    artist_params = parse_medium_field(artist_params)
    changeset = AdminArtists.get_changeset_for_artist(socket.assigns.artist, artist_params)

    # Convert medium back to string for form display
    changeset =
      if is_binary(original_medium_string) do
        Ecto.Changeset.put_change(changeset, :medium, original_medium_string)
      else
        changeset
      end

    socket =
      socket
      |> assign(:form, to_form(changeset, action: :validate))

    {:noreply, socket}
  end


  # Handles saving edits to an existing artist.
  # artist_params - parameters submitted from the form. This map
  # must include field "medium" as an array of strings
  # (as returned by parse_medium_field/1 ).
  defp save_artist(socket, :edit, artist_params) do
    case AdminArtists.update_artist(socket.assigns.artist, artist_params) do
      {:ok, _artist} ->
        socket =
          socket
          |> put_flash( :info, "Artist profile is updated successfully.")
          |> push_navigate(to: ~p"/admin/artists")
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset))
        {:noreply, socket}
    end
  end

  defp save_artist(socket, :new, artist_params) do
    case AdminArtists.create_artist(artist_params) do
      {:ok, _artist} ->
        socket =
          socket
          |> put_flash( :info, "Artist profile is  created successfully.")
          |> push_navigate(to: ~p"/admin/artists")
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset))
        {:noreply, socket}
    end
  end



  #Helper function to parse comma-separated medium string into array.
  defp parse_medium_field(params) do
    case params["medium"] do
      medium when is_binary(medium) ->
        # Split by comma, trim whitespace, and remove empty strings
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

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <div class="w-full px-8 py-8">

      <%!-- {inspect(@live_action)}

      <pre>{inspect(@artist, pretty: true, width: 80, label: "Artist")}</pre> --%>

      <.header>
        <%= @page_title  %>
      </.header>

      <.form for={@form} id="artist_form" phx-submit="save" phx-change="validate">

        <%!-- Nickname --%>
        <.input
          field={@form[:nickname]}
          label={raw("Nickname <span class=\"text-error\">*</span>")}
          placeholder="Artist's display name"
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

        <%!-- Main Image URL --%>
        <.input
          field={@form[:main_img]}
          label={raw("Main Image URL <span class=\"text-error\">*</span>")}
          placeholder="/uploads/artists/1/profile.jpg"
          required
        />

        <%!-- Additional Image URLs --%>
        <.input
          field={@form[:img2]}
          label="Image 2 URL"
        />

        <.input
          field={@form[:img3]}

          label="Image 3 URL"
        />

        <.input
          field={@form[:img4]}
          label="Image 4 URL"
        />

        <.input
          field={@form[:img5]}
          label="Image 5 URL"
        />

        <.button_artsy variant="primary" disable_with="Submitting...">
          Save Artist
        </.button_artsy>


      </.form>

      <.back navigate={~p"/admin/artists"}>
          Back
        </.back>
      </div>
      </Layouts.artsy_main>
    """
  end
end
