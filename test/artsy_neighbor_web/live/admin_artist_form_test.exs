defmodule ArtsyNeighborWeb.AdminArtistFormTest do
  @moduledoc """
  The admin artist form's status dropdown goes through
  `Artists.change_status/2` after the profile and photos are saved, so
  its rules apply (a public profile needs a photo) and a photo uploaded
  in the same save counts.
  """
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Accounts.Admin
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Repo

  # A small real photo shipped with the site.
  @photo "priv/static/images/cat-sculpture.jpg"

  setup %{conn: conn} do
    admin = user_fixture()
    Repo.insert!(%Admin{user_id: admin.id})
    %{conn: log_in_user(conn, admin)}
  end

  test "activating and uploading the first photo in the same save works", %{conn: conn} do
    artist = artist_fixture(%{status: :inactive})
    {:ok, view, _html} = live(conn, ~p"/admin/artists/#{artist}/edit")

    photo =
      file_input(view, "#artist_form", :profile_images, [
        %{
          name: "cat.jpg",
          content: File.read!(@photo),
          type: "image/jpeg"
        }
      ])

    render_upload(photo, "cat.jpg")

    result =
      view
      |> form("#artist_form", artist: %{status: "active"})
      |> render_submit()

    # Until image storage step 2b the form copies the file into
    # priv/static/uploads; remove it again.
    for image <- Artists.get_images_for_artist(artist) do
      File.rm(Path.join(["priv/static", image.path]))
    end

    assert {:error, {:live_redirect, %{to: "/admin/artists"}}} = result
    assert Artists.get_artist!(artist.id).status == :active
  end

  test "activating without a photo saves the profile but not the status, and says why",
       %{conn: conn} do
    artist = artist_fixture(%{status: :inactive})
    {:ok, view, _html} = live(conn, ~p"/admin/artists/#{artist}/edit")

    {:ok, _view, html} =
      view
      |> form("#artist_form", artist: %{status: "active", nickname: "Renamed Artist"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/artists/#{artist}/edit")

    assert html =~ "its status wasn&#39;t changed"
    assert html =~ "Add a profile photo before making your profile public."

    updated = Artists.get_artist!(artist.id)
    assert updated.status == :inactive
    assert updated.nickname == "Renamed Artist"
  end

  test "a new artist set to Active without a photo is created inactive, saying why",
       %{conn: conn} do
    owner = user_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/artists/new")

    {:ok, _view, html} =
      view
      |> form("#artist_form",
        artist: %{
          user_id: owner.id,
          nickname: "New Admin Artist",
          first_name: "New",
          last_name: "Artist",
          email: "new.artist@example.com",
          phone: "250-555-1234",
          street_address: "1 Fort Street",
          area_code: "V8W 1A1",
          bio: String.duplicate("A painter of the coast. ", 5),
          medium: "Watercolour",
          status: "active"
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Add a profile photo before making your profile public."
    artist = Artists.get_artist_by_user_id(owner.id)
    assert artist.status == :inactive
  end
end
