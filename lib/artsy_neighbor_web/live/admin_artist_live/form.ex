defmodule ArtsyNeighborWeb.AdminArtistLive.Form do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Admin.AdminArtists
  alias ArtsyNeighbor.Artists.Artist
  # alias ArtsyNeighbor.Repo
  # alias ArtsyNeighbor.Artists

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do

    changeset = Artist.changeset(%Artist{}, %{})
    socket =
      socket
      |> assign(:page_title, "New Artist")
      |> assign(:form, to_form(changeset, as: "artist"))

    {:ok, socket}
  end

  def handle_event("save", %{"artist" => artist_params}, socket) do
    # Parse comma-separated medium string into array
    artist_params = parse_medium_field(artist_params)

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
          |> assign(:form, to_form(changeset, as: "artist"))
        {:noreply, socket}
    end

  end

  # Helper function to parse comma-separated medium string into array
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
      <div class="admin-index">
      <.header>
        <%= @page_title  %>
      </.header>

      <.form for={@form} id="artist_form" phx-submit="save">

        <%!-- Nickname --%>
        <.input
          field={@form[:nickname]}
          label="Nickname"
          placeholder="Artist's display name"
          required
        />

        <%!-- First Name --%>
        <.input
          field={@form[:first_name]}
          label="First Name"
          required
        />

        <%!-- Last Name --%>
        <.input
          field={@form[:last_name]}
          label="Last Name"
          required
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
          label="Email"
          required
        />

        <%!-- Phone --%>
        <.input
          field={@form[:phone]}
          type="tel"
          label="Phone"
          placeholder="e.g., 416-555-0101"
          required
        />

        <%!-- Street Address --%>
        <.input
          field={@form[:street_address]}
          label="Street Address"
          required
        />


        <%!-- Apartment Info --%>
        <.input
          field={@form[:apt_info]}
          label="Apartment/Unit"
          placeholder="e.g., Suite 3B, Unit 405"
        />

        <%!-- Area Code / Neighborhood --%>
        <.input
          field={@form[:area_code]}
          label="Area Code / Neighborhood"
          placeholder="e.g., M5V 2T6"
          required
        />

        <%!-- Bio --%>
        <.input
          field={@form[:bio]}
          type="textarea"
          label="Bio"
          rows="4"
          required
        />

        <%!-- Medium (array of strings) --%>
        <.input
          field={@form[:medium]}
          label="Mediums (comma-separated)"
          placeholder="e.g., Oil painting, Acrylic painting, Mixed media"
          phx-debounce="blur"
          required
        />

        <%!-- Main Image URL --%>
        <.input
          field={@form[:main_img]}
          label="Main Image URL"
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
    """
  end
end
