defmodule ArtsyNeighbor.ArtistsFixtures do
  @moduledoc """
  Test helpers for creating artist entities.
  """

  import ArtsyNeighbor.AccountsFixtures

  def unique_artist_nickname, do: "artist-#{System.unique_integer([:positive])}"
  def unique_artist_email, do: "artist#{System.unique_integer([:positive])}@example.com"

  @valid_bio "This is a valid bio for testing purposes. It is written to be at least 75 characters long."

  def artist_fixture(attrs \\ %{}) do
    user = user_fixture()

    {:ok, artist} =
      attrs
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
        status: :active,
        user_id: user.id
      })
      |> ArtsyNeighbor.Artists.create_artist()

    ArtsyNeighbor.Repo.preload(artist, [:artist_images])
  end
end
