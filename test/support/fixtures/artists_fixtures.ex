defmodule ArtsyNeighbor.ArtistsFixtures do
  @moduledoc """
  Test helpers for creating artist entities.
  """

  def unique_artist_nickname, do: "artist-#{System.unique_integer([:positive])}"
  def unique_artist_email, do: "artist#{System.unique_integer([:positive])}@example.com"

  @valid_bio "This is a valid bio for testing purposes. It is written to be at least 75 characters long."

  def artist_fixture(attrs \\ %{}) do
    {:ok, artist} =
      attrs
      |> Enum.into(%{
        nickname: unique_artist_nickname(),
        first_name: "Test",
        last_name: "Artist",
        phone: "416-555-1234",
        bio: @valid_bio,
        main_img: "/images/test-artist.jpg",
        email: unique_artist_email(),
        street_address: "123 Test Street",
        area_code: "M5H 2N2",
        medium: ["Oil painting"]
      })
      |> ArtsyNeighbor.Admin.AdminArtists.create_artist()

    artist
  end
end
