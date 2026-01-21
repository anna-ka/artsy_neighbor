defmodule ArtsyNeighborWeb.AdminArtistLive.Index do


  use ArtsyNeighborWeb, :live_view

  # alias ArtsyNeighbor.Admin.AdminArtists
  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, form_table: 1]

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign( :page_title, "Admin - Artists")
      |> stream(:artists, ArtsyNeighbor.Admin.AdminArtists.list_artists())
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>
    <div class="admin-index">

    <.header>
          <%= @page_title  %>
          <:actions>
             <.button_artsy navigate={~p"/admin/artists/new"} variant="secondary">
               New Artist
             </.button_artsy>
          </:actions>
    </.header>

    <div class="overflow-x-auto">
        <.form_table id="admin-artists-table" rows={@streams.artists}>
        <%!-- Image --%>
        <:col :let={{_dom_id, artist}} label="Image" col_class="w-20">
          <div class="avatar">
            <div class="mask mask-squircle h-12 w-12">
              <img
                src={artist.main_img}
                alt={artist.nickname} />
            </div>
          </div>
        </:col>

        <%!-- Nickname --%>
        <:col :let={{_dom_id, artist}} label="Nickname" col_class="w-32">
          <%= artist.nickname %>
        </:col>

        <%!-- First Name --%>
        <:col :let={{_dom_id, artist}} label="First name" col_class="w-28">
          <%= artist.first_name %>
        </:col>

        <%!-- Last Name --%>
        <:col :let={{_dom_id, artist}} label="Last name" col_class="w-28">
          <%= artist.last_name %>
        </:col>

        <%!-- Middle Name --%>
        <:col :let={{_dom_id, artist}} label="Middle" col_class="w-24">
          <%= artist.middle_name %>
        </:col>

        <%!-- Email --%>
        <:col :let={{_dom_id, artist}} label="Email" col_class="w-48">
          <%= artist.email %>
        </:col>

        <%!-- Phone --%>
        <:col :let={{_dom_id, artist}} label="Phone" col_class="w-32">
          <%= artist.phone %>
        </:col>

        <%!-- Street Address --%>
        <:col :let={{_dom_id, artist}} label="Street address" col_class="w-56">
          <%= artist.street_address %>
          <%= if artist.apt_info, do: ", #{artist.apt_info}" %>
        </:col>

        <%!-- Area Code --%>
        <:col :let={{_dom_id, artist}} label="Neighborhood" col_class="w-28">
          <div class="badge badge-secondary badge-outline">
            <%= artist.area_code %>
          </div>
        </:col>

        <%!-- Medium --%>
        <:col :let={{_dom_id, artist}} label="Medium" col_class="w-40">
          <div class="flex flex-wrap gap-1">
            <%= for medium <- Enum.take(artist.medium, 2) do %>
              <span class="badge badge-primary badge-sm">
                <%= medium %>
              </span>
            <% end %>
            <%= if length(artist.medium) > 2 do %>
              <span class="badge badge-ghost badge-sm">
                +<%= length(artist.medium) - 2 %>
              </span>
            <% end %>
          </div>
        </:col>

        <%!-- Bio (truncated) --%>
        <:col :let={{_dom_id, artist}} label="Bio" col_class="w-64">
          <%= String.slice(artist.bio, 0, 50) %><%= if String.length(artist.bio) > 50, do: "..." %>
        </:col>

        <%!-- Actions --%>
        <:col :let={{_dom_id, _artist}} label="Actions" col_class="w-36">
          <div class="flex gap-2">
            <button class="btn btn-ghost btn-xs">view</button>
            <button class="btn btn-ghost btn-xs">edit</button>
            <button class="btn btn-ghost btn-xs text-error">delete</button>
          </div>
        </:col>

        </.form_table>



    </div>
    </div>
    </Layouts.artsy_main>
    """
  end


end
