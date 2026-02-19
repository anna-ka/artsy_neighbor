defmodule ArtsyNeighbor.ArtistsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Artists
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

  describe "read operations" do
    test "list_artists/0 returns all artists" do
      artist = artist_fixture()
      assert Artists.list_artists() == [artist]
    end

    test "list_artists/0 returns empty list when no artists exist" do
      assert Artists.list_artists() == []
    end

    test "get_artist/1 returns the artist with given id" do
      artist = artist_fixture()
      assert Artists.get_artist(artist.id) == artist
    end

    test "get_artist/1 returns nil for non-existent id" do
      assert Artists.get_artist(0) == nil
    end
  end

  describe "filter_artists_by_area/1" do
    test "returns artists in the given area" do
      artist = artist_fixture(%{area_code: "M5H 2N2"})
      _other = artist_fixture(%{area_code: "V6B 2W9"})
      assert Artists.filter_artists_by_area("M5H 2N2") == [artist]
    end

    test "returns empty list when no artists match" do
      artist_fixture(%{area_code: "M5H 2N2"})
      assert Artists.filter_artists_by_area("X0X 0X0") == []
    end
  end

  describe "filter_artists_by_medium/1" do
    test "returns artists with the given medium" do
      oil_artist = artist_fixture(%{medium: ["Oil painting"]})
      _other = artist_fixture(%{medium: ["Sculpture"]})
      assert Artists.filter_artists_by_medium("Oil painting") == [oil_artist]
    end

    test "is case-insensitive" do
      artist = artist_fixture(%{medium: ["Oil painting"]})
      assert Artists.filter_artists_by_medium("oil painting") == [artist]
    end

    test "returns empty list when no artists match" do
      artist_fixture(%{medium: ["Oil painting"]})
      assert Artists.filter_artists_by_medium("Ceramics") == []
    end
  end

  describe "filter_artists/1" do
    test "filters by nickname (partial, case-insensitive)" do
      artist = artist_fixture(%{nickname: "Elena"})
      _other = artist_fixture(%{nickname: "Marco"})
      result = Artists.filter_artists(%{"q_name" => "Elena", "q_medium" => "", "sort_by" => ""})
      assert result == [artist]
    end

    test "returns all artists when q_name is blank" do
      artist_fixture()
      artist_fixture()
      result = Artists.filter_artists(%{"q_name" => "", "q_medium" => "", "sort_by" => ""})
      assert length(result) == 2
    end

    test "filters by medium" do
      artist = artist_fixture(%{medium: ["Watercolor"]})
      _other = artist_fixture(%{medium: ["Sculpture"]})
      result = Artists.filter_artists(%{"q_name" => "", "q_medium" => "Watercolor", "sort_by" => ""})
      assert result == [artist]
    end

    test "returns empty list when no artists match filters" do
      artist_fixture(%{nickname: "Elena"})
      result = Artists.filter_artists(%{"q_name" => "Zephyr", "q_medium" => "", "sort_by" => ""})
      assert result == []
    end
  end

  describe "Artist changeset - required fields" do
    test "valid changeset with all required fields" do
      changeset = Artist.changeset(%Artist{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires nickname" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :nickname, nil))
      assert "can't be blank" in errors_on(changeset).nickname
    end

    test "requires first_name" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :first_name, nil))
      assert "can't be blank" in errors_on(changeset).first_name
    end

    test "requires last_name" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :last_name, nil))
      assert "can't be blank" in errors_on(changeset).last_name
    end

    test "requires email" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :email, nil))
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires phone" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :phone, nil))
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "requires bio" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :bio, nil))
      assert "can't be blank" in errors_on(changeset).bio
    end

    test "requires street_address" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :street_address, nil))
      assert "can't be blank" in errors_on(changeset).street_address
    end

    test "requires area_code" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :area_code, nil))
      assert "can't be blank" in errors_on(changeset).area_code
    end

    test "requires medium" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :medium, nil))
      assert "can't be blank" in errors_on(changeset).medium
    end

    test "allows middle_name to be nil" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :middle_name, nil))
      assert changeset.valid?
    end

    test "allows apt_info to be nil" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :apt_info, nil))
      assert changeset.valid?
    end
  end

  describe "Artist changeset - length validations" do
    test "rejects bio shorter than 75 characters" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :bio, String.duplicate("a", 74)))
      assert errors_on(changeset).bio != []
    end

    test "accepts bio of exactly 75 characters" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :bio, String.duplicate("a", 75)))
      assert changeset.valid?
    end

    test "rejects first_name shorter than 2 characters" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :first_name, "A"))
      assert errors_on(changeset).first_name != []
    end

    test "accepts first_name of exactly 2 characters" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :first_name, "Al"))
      assert changeset.valid?
    end

    test "rejects last_name shorter than 2 characters" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :last_name, "B"))
      assert errors_on(changeset).last_name != []
    end

    test "accepts last_name of exactly 2 characters" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :last_name, "Li"))
      assert changeset.valid?
    end
  end

  describe "Artist changeset - email validation" do
    test "accepts valid email" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :email, "test@example.com"))
      assert changeset.valid?
    end

    test "rejects email without @ sign" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :email, "notanemail"))
      assert errors_on(changeset).email != []
    end

    test "rejects email without domain extension" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :email, "user@nodot"))
      assert errors_on(changeset).email != []
    end
  end

  describe "Artist changeset - phone validation" do
    test "accepts standard North American format with dashes" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :phone, "416-555-1234"))
      assert changeset.valid?
    end

    test "accepts format with parentheses" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :phone, "(416) 555-1234"))
      assert changeset.valid?
    end

    test "accepts format with country code" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :phone, "+1-416-555-1234"))
      assert changeset.valid?
    end

    test "rejects non-numeric phone" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :phone, "not-a-phone"))
      assert errors_on(changeset).phone != []
    end
  end

  describe "Artist changeset - area_code (Canadian postal code) validation" do
    test "accepts postal code with space" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "M5H 2N2"))
      assert changeset.valid?
    end

    test "accepts postal code without space" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "M5H2N2"))
      assert changeset.valid?
    end

    test "accepts lowercase postal code" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "m5h2n2"))
      assert changeset.valid?
    end

    test "rejects US ZIP code format" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "10001"))
      assert errors_on(changeset).area_code != []
    end

    test "rejects postal code with wrong letter/digit pattern" do
      changeset = Artist.changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "MM5 2N2"))
      assert errors_on(changeset).area_code != []
    end
  end
end
