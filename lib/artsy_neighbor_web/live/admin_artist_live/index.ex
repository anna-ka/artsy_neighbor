defmodule ArtsyNeighborWeb.AdminArtistLive.Index do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Admin.AdminArtists
  alias ArtsyNeighbor.HardDelete

  import ArtsyNeighborWeb.CustomComponents,
    only: [button_artsy: 1, form_table: 1, back: 1, status_actions: 1]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin - Artists")
      |> stream(:artists, AdminArtists.list_artists_all_status())

    {:ok, socket}
  end

  @impl true
  def handle_event("remove", %{"id" => id}, socket) do
    artist = AdminArtists.get_artist!(id)
    {:ok, updated_artist} = AdminArtists.soft_delete_artist(artist)

    message = "Artist #{artist.nickname} has been marked as removed."

    socket =
      socket
      |> stream_insert(:artists, updated_artist)
      |> put_flash(:info, message)

    {:noreply, socket}
  end

  # Reverses "remove" — see AdminArtists.restore_artist/1 /
  # Artists.restore_artist/1. Lands on :inactive, not :active (the vendor
  # still has to activate their own profile), and does not touch the
  # artist's products (still :archived from soft_delete_artist/1) — those
  # wait on Products.restore_product/1, itself gated on the artist being
  # :active, so there's no "restore artist -> products instantly visible"
  # shortcut here.
  #
  # restore_artist/1 can return {:error, :already_active} (stale
  # page/double-click on an artist someone else already restored or
  # activated) or {:error, :user_missing} (the artist's linked user
  # account is gone — currently unreachable in practice, see that
  # function's own doc comment) in addition to a changeset error —
  # handled below with a flash for each rather than a MatchError.
  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    artist = AdminArtists.get_artist!(id)

    socket =
      case AdminArtists.restore_artist(artist) do
        {:ok, updated_artist} ->
          message =
            "Artist #{artist.nickname} has been restored to inactive — they'll need to activate their own profile before it's visible to the public again."

          socket
          |> stream_insert(:artists, updated_artist)
          |> put_flash(:info, message)

        {:error, :already_active} ->
          put_flash(socket, :info, "#{artist.nickname} is already active — nothing to restore.")

        {:error, :user_missing} ->
          put_flash(
            socket,
            :error,
            "Could not restore #{artist.nickname} — their linked user account no longer exists."
          )

        {:error, _reason} ->
          put_flash(
            socket,
            :error,
            "Could not restore #{artist.nickname}. Please try again."
          )
      end

    {:noreply, socket}
  end

  # Permanently deletes an artist via AdminArtists.hard_delete_artist/1
  # (which delegates to Artists.hard_delete_artist/1) — a hard delete,
  # unlike the "remove" handler above. This also destroys every order,
  # order item, conversation, conversation event, and review tied to this
  # artist; there is no undo. It's meant for admin/testing cleanup, not the
  # normal "take this vendor down" action — that's "remove", which just
  # flips status and is fully reversible. The confirm dialog in the
  # template spells this out to the admin before the event ever fires.
  #
  # hard_delete_artist/1 can return {:error, reason} rather than crashing —
  # handled below with a flash showing the actual reason (admin-only page,
  # so the raw database reason is more useful than a guess at the cause).
  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    artist = AdminArtists.get_artist!(id)

    socket =
      case AdminArtists.hard_delete_artist(artist) do
        {:ok, _deleted} ->
          message =
            "Artist #{artist.nickname} and all their orders, reviews, and conversations have been permanently deleted."

          socket
          |> stream_delete(:artists, artist)
          |> put_flash(:info, message)

        {:error, reason} ->
          put_flash(
            socket,
            :error,
            "Could not delete #{artist.nickname}: #{HardDelete.error_message(reason)}"
          )
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.artsy_wide flash={@flash} variant="admin" nav_categories={@nav_categories}>
      <div class="admin-index">
        <div>
          <.back navigate={~p"/admin"}>
            Admin Dashboard
          </.back>
        </div>

        <.header>
          {@page_title}
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
                    src={
                      artist.artist_images
                      |> Enum.sort_by(& &1.position)
                      |> List.first()
                      |> then(fn img ->
                        if img, do: img.path, else: "/images/avatar-placeholder.png"
                      end)
                    }
                    alt={artist.nickname}
                  />
                </div>
              </div>
            </:col>

            <%!-- Nickname --%>
            <:col :let={{_dom_id, artist}} label="Nickname" col_class="w-32">
              {artist.nickname}
            </:col>

            <%!-- First Name --%>
            <:col :let={{_dom_id, artist}} label="First name" col_class="w-28">
              {artist.first_name}
            </:col>

            <%!-- Last Name --%>
            <:col :let={{_dom_id, artist}} label="Last name" col_class="w-28">
              {artist.last_name}
            </:col>

            <%!-- Middle Name --%>
            <:col :let={{_dom_id, artist}} label="Middle" col_class="w-24">
              {artist.middle_name}
            </:col>
            
    <!-- Profile status -->
            <:col :let={{_dom_id, artist}} label="Status" col_class="w-24">
              {artist.status}
            </:col>

            <%!-- Email --%>
            <:col :let={{_dom_id, artist}} label="Email" col_class="w-48">
              {artist.email}
            </:col>

            <%!-- Phone --%>
            <:col :let={{_dom_id, artist}} label="Phone" col_class="w-32">
              {artist.phone}
            </:col>

            <%!-- Street Address --%>
            <:col :let={{_dom_id, artist}} label="Street address" col_class="w-56">
              {artist.street_address}
              {if artist.apt_info, do: ", #{artist.apt_info}"}
            </:col>

            <%!-- Area Code --%>
            <:col :let={{_dom_id, artist}} label="Neighborhood" col_class="w-28">
              <div class="badge badge-secondary badge-outline">
                {artist.area_code}
              </div>
            </:col>

            <%!-- Medium --%>
            <:col :let={{_dom_id, artist}} label="Medium" col_class="w-40">
              <div class="flex flex-wrap gap-1">
                <%= for medium <- Enum.take(artist.medium, 2) do %>
                  <span class="badge badge-primary badge-sm">
                    {medium}
                  </span>
                <% end %>
                <%= if length(artist.medium) > 2 do %>
                  <span class="badge badge-ghost badge-sm">
                    +{length(artist.medium) - 2}
                  </span>
                <% end %>
              </div>
            </:col>

            <%!-- Bio (truncated) --%>
            <:col :let={{_dom_id, artist}} label="Bio" col_class="w-64">
              <% bio = artist.bio || "" %>
              {String.slice(bio, 0, 50)}{if String.length(bio) > 50, do: "..."}
            </:col>

            <%!-- Actions --%>
            <:col :let={{_dom_id, artist}} label="Actions" col_class="w-48">
              <.status_actions
                id={artist.id}
                view_path={~p"/artists/#{artist}"}
                edit_path={~p"/admin/artists/#{artist}/edit"}
                show_restore={artist.status != :active}
                restore_confirm={"Restore #{artist.nickname}? Their status will change to inactive — they'll need to activate their own profile from the vendor dashboard before it's visible to the public again. Their products stay archived until restored individually, which itself waits on the artist being active."}
                soft_delete_event="remove"
                soft_delete_label="mark removed"
                soft_delete_confirm={"Mark artist #{artist.nickname} as removed? Their profile and products will be hidden from the public site, but all data is kept and this can be reversed using the restore action."}
                hard_delete_confirm={"Permanently delete artist #{artist.nickname}? This will also delete ALL of their orders, order items, conversations, and reviews. This cannot be undone."}
              />
            </:col>
          </.form_table>
        </div>
      </div>
    </Layouts.artsy_wide>
    """
  end
end
