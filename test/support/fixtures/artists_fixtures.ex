defmodule ArtsyNeighbor.ArtistsFixtures do
  @moduledoc """
  Test helpers for creating artist entities.
  """

  import ArtsyNeighbor.AccountsFixtures

  def unique_artist_nickname, do: "artist-#{System.unique_integer([:positive])}"
  def unique_artist_email, do: "artist#{System.unique_integer([:positive])}@example.com"

  @valid_bio "This is a valid bio for testing purposes. It is written to be at least 75 characters long."

  @doc """
  An artist, `:active` unless `attrs` says otherwise.

  Created through `AdminArtists.create_artist/1`, which takes the owner
  from `attrs` (and makes the default collection too); that always makes an `:inactive` profile, so the
  status is then set directly, skipping the rules of
  `Artists.change_status/2` (e.g. an `:active` profile needs a photo).
  Most tests just need an existing artist; tests of the rules use
  `change_status/2`, `activate_artist/1` etc.

  `:onboarding_step` and `:onboarding_complete` in `attrs` are set
  directly afterwards too: no changeset takes them from a map, since
  only the server sets them (audit S-2).
  """
  def artist_fixture(attrs \\ %{}) do
    user = user_fixture()

    attrs = Map.new(attrs)
    status = Map.get(attrs, :status, :active)
    onboarding = Map.take(attrs, [:onboarding_step, :onboarding_complete])

    {:ok, artist} =
      attrs
      |> Map.drop([:status, :onboarding_step, :onboarding_complete])
      |> Enum.into(%{
        nickname: unique_artist_nickname(),
        first_name: "Test",
        last_name: "Artist",
        phone: "416-555-1234",
        bio: @valid_bio,
        email: unique_artist_email(),
        street_address: "123 Test Street",
        area_code: "M5H 2N2",
        medium: ["Oil painting"],
        user_id: user.id
      })
      |> ArtsyNeighbor.Admin.AdminArtists.create_artist()

    artist =
      artist
      |> ArtsyNeighbor.Artists.Artist.status_changeset(%{status: status})
      |> Ecto.Changeset.change(onboarding)
      |> ArtsyNeighbor.Repo.update!()

    ArtsyNeighbor.Repo.preload(artist, [:artist_images])
  end

  @doc """
  Adds a profile photo to `artist`. An artist needs one before
  `Artists.update_artist/2` will make them `:active`.
  """
  def artist_image_fixture(artist, attrs \\ %{}) do
    {:ok, image} =
      ArtsyNeighbor.Artists.create_artist_image(
        artist,
        Enum.into(attrs, %{path: "/profile-photo.jpg", position: 1})
      )

    image
  end
end
