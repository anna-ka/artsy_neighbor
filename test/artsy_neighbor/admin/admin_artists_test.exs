defmodule ArtsyNeighbor.Admin.AdminArtistsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Admin.AdminArtists
  alias ArtsyNeighbor.Artists.Artist

  import ArtsyNeighbor.ArtistsFixtures

  @valid_attrs %{
    nickname: "VanGogh",
    first_name: "Vincent",
    last_name: "Artist",
    phone: "416-555-1234",
    bio: "This is a valid bio for testing purposes. It is written to be at least 75 characters long.",
    main_img: "/images/test-artist.jpg",
    email: "vincent@example.com",
    street_address: "123 Test Street",
    area_code: "M5H 2N2",
    medium: ["Oil painting"]
  }

  @update_attrs %{
    nickname: "Updated VanGogh",
    bio: "This is an updated bio for testing purposes. It must also be at least 75 characters long."
  }

  @invalid_attrs %{nickname: nil, first_name: nil, last_name: nil}

  describe "list_artists/0" do
    test "returns all artists" do
      artist = artist_fixture()
      assert AdminArtists.list_artists() == [artist]
    end

    test "returns empty list when no artists exist" do
      assert AdminArtists.list_artists() == []
    end
  end

  describe "get_artist!/1" do
    test "returns the artist with given id" do
      artist = artist_fixture()
      assert AdminArtists.get_artist!(artist.id) == artist
    end

    test "raises when artist does not exist" do
      assert_raise Ecto.NoResultsError, fn -> AdminArtists.get_artist!(0) end
    end
  end

  describe "create_artist/1" do
    test "with valid data creates an artist" do
      assert {:ok, %Artist{} = artist} = AdminArtists.create_artist(@valid_attrs)
      assert artist.nickname == "VanGogh"
      assert artist.first_name == "Vincent"
      assert artist.email == "vincent@example.com"
      assert artist.medium == ["Oil painting"]
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = AdminArtists.create_artist(@invalid_attrs)
    end
  end

  describe "update_artist/2" do
    test "with valid data updates the artist" do
      artist = artist_fixture()
      assert {:ok, %Artist{} = updated} = AdminArtists.update_artist(artist, @update_attrs)
      assert updated.nickname == "Updated VanGogh"
    end

    test "with invalid data returns error changeset" do
      artist = artist_fixture()
      assert {:error, %Ecto.Changeset{}} = AdminArtists.update_artist(artist, @invalid_attrs)
      assert artist == AdminArtists.get_artist!(artist.id)
    end
  end

  describe "delete_artist/1" do
    test "deletes the artist" do
      artist = artist_fixture()
      assert {:ok, %Artist{}} = AdminArtists.delete_artist(artist)
      assert_raise Ecto.NoResultsError, fn -> AdminArtists.get_artist!(artist.id) end
    end
  end

  describe "change_artist/2" do
    test "returns a valid changeset for an existing artist" do
      artist = artist_fixture()
      assert %Ecto.Changeset{valid?: true} = AdminArtists.change_artist(artist)
    end

    test "returns a changeset with errors for invalid attrs" do
      artist = artist_fixture()
      changeset = AdminArtists.change_artist(artist, @invalid_attrs)
      refute changeset.valid?
    end
  end
end
