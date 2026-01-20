defmodule ArtsyNeighborWeb.ArtistLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do

    socket =
      socket
      |> stream(:artists, Artists.filter_artists(params), reset: true)
      |> assign(:form, to_form(params))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 py-8 bg-base-100">

        <%!-- Page Header --%>
        <div class="mb-8">
          <h1 class="text-4xl font-bold text-base-content mb-2">Our Artists</h1>
          <p class="text-lg text-base-content/70">Discover talented local artists and their unique creations</p>

          <%!-- Search form --%>

          <.filter_artists_form form={@form} />

        </div>

        <%!-- Artists Grid --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6" id="artists-list" phx-update="stream">
          <.artist_card :for={{dom_id, artist} <- @streams.artists}  artist={artist} dom_id={dom_id}/>
        </div>

      </div>
    </Layouts.artsy_main>
    """
  end


  @doc """
  Handles filtering of artists based on form input.
  """
  def handle_event("filter_artists", params, socket) do
    params =
      params
      |> Map.take(~w(q_medium q_name sort_by))
      |> Map.reject(fn {_k, v} -> v == "" end)

    socket = push_patch(socket, to: ~p"/artists?#{params}")

    {:noreply, socket}
  end


  @doc """
  Renders filter form for artists.
  """
  attr :form, :map, required: true, doc: "Form struct to bind to the form"
  def filter_artists_form(assigns) do
    ~H"""
      <.form for={@form} id="filter-artists-form" phx-change="filter_artists" class="mt-4">
            <div class="flex flex-col lg:flex-row lg:items-end lg:justify-between mt-4">
              <.input field={@form[:q_medium]} placeholder="Search by medium..." autocomplete="off"
                class="w-full input" phx-debounce="500" />

                <.input field={@form[:q_name]} placeholder="Search by name ..." autocomplete="off"
                class="w-full input" phx-debounce="500" />

              <.input
                  type="select"
                  field={@form[:sort_by]}
                  prompt="Sort By"
                  options={[
                    "Neighborhood": "area_code",
                    "Artist name": "nickname",
                    "Main medium": "main_medium"
                  ]}
              />

              <.link patch={~p"/artists"}>
                Reset filters
            </.link>

            </div>
          </.form>

    """
  end

  @doc """
  Renders an artist card displaying artist details.
  """

  attr :artist, :map, required: true, doc: "An ArtsyNeighbor.Artists.Artist struct"
  attr :dom_id, :string, required: true, doc: "Required DOM id for the artist card"

  def artist_card(assigns) do
    ~H"""
      <.link navigate={~p"/artists/#{@artist}"} id={@dom_id}>
        <%!-- DaisyUI Card Component --%>
        <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">

          <%!-- DaisyUI figure for image --%>
          <figure class="aspect-square">
            <img
              src={@artist.main_img}
              alt={@artist.nickname}
              class="w-full h-full object-cover hover:scale-105 transition-transform duration-300"
            />
          </figure>

          <%!-- DaisyUI card-body --%>
          <div class="card-body">
            <%!-- DaisyUI card-title --%>
            <h3 class="card-title">
              <%= @artist.nickname %>
            </h3>

            <%!-- DaisyUI badge for neighborhood --%>
            <div class="badge badge-secondary badge-outline">
              <%= @artist.area_code %>
            </div>

            <%!-- DaisyUI badges for medium tags --%>
            <div class="card-actions justify-start flex-wrap mt-2">
              <%= for medium <- Enum.take(@artist.medium, 3) do %>
                <div class="badge badge-primary badge-sm">
                  <%= medium %>
                </div>
              <% end %>
              <%= if length(@artist.medium) > 3 do %>
                <div class="badge badge-ghost badge-sm">
                  +<%= length(@artist.medium) - 3 %> more
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </.link>
    """
 end



end
