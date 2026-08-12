defmodule ArtsyNeighbor.ArtistsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Products

  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ProductsFixtures

  # ---------------------------------------------------------------------------
  # These attrs satisfy activation_changeset (the full-profile changeset).
  # user_id is intentionally omitted here because assoc_constraint only fires
  # at the database level — it does NOT make a changeset invalid on its own.
  # Tests that need a real persisted artist use artist_fixture() instead.
  # ---------------------------------------------------------------------------
  @valid_attrs %{
    nickname: "VanGogh",
    first_name: "Vincent",
    last_name: "Artist",
    phone: "416-555-1234",
    bio: "This is a valid bio for testing purposes. It is written to be at least 75 characters long.",
    email: "vincent@example.com",
    street_address: "123 Test Street",
    area_code: "M5H 2N2",
    medium: ["Oil painting"]
  }

  # ---------------------------------------------------------------------------
  # list_artists/0 — public-facing function, should only return active artists
  # ---------------------------------------------------------------------------
  describe "list_artists/0" do
    # The fixture defaults to status: :active so this basic case still holds.
    test "returns active artists" do
      artist = artist_fixture(%{status: :active})
      result = Artists.list_artists()
      assert length(result) == 1
      assert hd(result).id == artist.id
    end

    test "returns empty list when no artists exist" do
      assert Artists.list_artists() == []
    end

    # Inactive artists are real vendors who have temporarily turned off their
    # profile. They should not appear on public pages.
    test "excludes inactive artists" do
      artist_fixture(%{status: :inactive})
      assert Artists.list_artists() == []
    end

    # Removed artists are soft-deleted. Their record stays in the DB but they
    # must never surface to the public under any circumstances.
    test "excludes removed artists" do
      artist_fixture(%{status: :removed})
      assert Artists.list_artists() == []
    end
  end

  # ---------------------------------------------------------------------------
  # list_artists_all_status/0 — admin-only function, returns every artist
  # regardless of status, sorted active → inactive → removed, then by nickname
  # ---------------------------------------------------------------------------
  describe "list_artists_all_status/0" do
    test "returns artists of all statuses" do
      _active   = artist_fixture(%{status: :active})
      _inactive = artist_fixture(%{status: :inactive})
      _removed  = artist_fixture(%{status: :removed})
      result = Artists.list_artists_all_status()
      assert length(result) == 3
    end

    test "sorts active first, then inactive, then removed" do
      # Create out of alphabetical/insertion order to be sure sort is by status, not insertion
      removed  = artist_fixture(%{status: :removed,  nickname: "Zara"})
      inactive = artist_fixture(%{status: :inactive, nickname: "Marco"})
      active   = artist_fixture(%{status: :active,   nickname: "Elena"})

      ids = Artists.list_artists_all_status() |> Enum.map(& &1.id)
      assert ids == [active.id, inactive.id, removed.id]
    end

    test "within the same status, sorts alphabetically by nickname" do
      b_artist = artist_fixture(%{status: :active, nickname: "Berta"})
      a_artist = artist_fixture(%{status: :active, nickname: "Anna"})

      [first, second] = Artists.list_artists_all_status()
      assert first.id  == a_artist.id
      assert second.id == b_artist.id
    end

    test "preloads artist_images for each artist" do
      artist = artist_fixture()
      {:ok, _} = Artists.create_artist_image(artist, %{path: "/uploads/test.jpg", position: 1})

      [result] = Artists.list_artists_all_status()
      # If images were not preloaded, this would be an Ecto.Association.NotLoaded struct
      assert is_list(result.artist_images)
      assert length(result.artist_images) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # remove_artist/1 — soft-delete an artist and set their products :unavailable
  # ---------------------------------------------------------------------------
  describe "remove_artist/1" do
    test "sets the artist's status to :removed" do
      artist = artist_fixture()
      assert {:ok, updated} = Artists.remove_artist(artist)
      assert updated.status == :removed
    end

    # When an artist is removed, their products should stop being visible on
    # public pages. We set status to :unavailable rather than deleting them,
    # because products may be referenced by existing orders.
    test "sets all of the artist's products to :unavailable" do
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})

      # Confirm the product starts :available
      assert Products.get_product!(product.id).status == :available

      {:ok, _} = Artists.remove_artist(artist)
      assert Products.get_product!(product.id).status == :unavailable
    end

    test "returns the updated artist with artist_images preloaded" do
      artist = artist_fixture()
      {:ok, updated} = Artists.remove_artist(artist)

      # Must have artist_images loaded so the admin index can stream_insert without crashing
      assert is_list(updated.artist_images)
      assert updated.status == :removed
    end

    test "does not affect products belonging to other artists" do
      artist_a = artist_fixture()
      artist_b = artist_fixture()
      product_b = product_fixture(%{artist_id: artist_b.id})

      {:ok, _} = Artists.remove_artist(artist_a)

      # artist_b's product should be untouched
      assert Products.get_product!(product_b.id).status == :available
    end
  end

  # ---------------------------------------------------------------------------
  # save_onboarding_progress/2
  #
  # This is the onboarding-specific save path. The changeset it receives comes
  # from registration_changeset (step 1 validation only — no bio or medium
  # required). Two branches:
  #   - artist has no id → inserts into DB + creates default collection (Multi)
  #   - artist already has an id → plain update
  # ---------------------------------------------------------------------------
  describe "save_onboarding_progress/2" do
    # The new-artist path goes through create_artist/1 which runs a Multi
    # transaction: insert artist + insert "Uncategorized" collection.
    test "inserts a new artist and creates the default collection when artist has no id" do
      user = user_fixture()

      changeset = Artists.registration_change_artist(%Artist{}, %{
        nickname: "Newbie",
        first_name: "Test",
        last_name: "Artist",
        phone: "416-555-1234",
        email: "newbie@example.com",
        street_address: "100 Test St",
        area_code: "M5H 2N2",
        user_id: user.id
      })

      assert {:ok, artist} = Artists.save_onboarding_progress(changeset, 1)

      collections = Products.list_collections_for_artist(artist.id)
      assert length(collections) == 1
      assert hd(collections).name == "Uncategorized"
    end

    test "stamps the given step value onto the artist" do
      user = user_fixture()

      changeset = Artists.registration_change_artist(%Artist{}, %{
        nickname: "Steppy",
        first_name: "Test",
        last_name: "Artist",
        phone: "416-555-1234",
        email: "steppy@example.com",
        street_address: "100 Test St",
        area_code: "M5H 2N2",
        user_id: user.id
      })

      assert {:ok, artist} = Artists.save_onboarding_progress(changeset, 1)
      assert artist.onboarding_step == 1
    end

    # The update path (artist already exists) just does a Repo.update.
    # It does not recreate the collection.
    test "updates an existing artist's onboarding_step without re-creating the collection" do
      artist = artist_fixture()
      changeset = Artists.registration_change_artist(artist, %{nickname: artist.nickname})

      assert {:ok, updated} = Artists.save_onboarding_progress(changeset, 2)
      assert updated.onboarding_step == 2

      # Collection count should remain exactly 1 (created when artist was first inserted)
      assert length(Products.list_collections_for_artist(artist.id)) == 1
    end

    test "returns an error changeset when the changeset is invalid" do
      # Pass an invalid changeset (nickname required but blank)
      changeset = Artists.registration_change_artist(%Artist{}, %{nickname: ""})

      assert {:error, %Ecto.Changeset{}} = Artists.save_onboarding_progress(changeset, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Onboarding flow — registration_changeset (step 1)
  #
  # This is the lightweight first-step changeset. It only validates the basics
  # needed to create an account: name, email, phone, address. Bio and medium
  # are intentionally NOT required here — the vendor fills those in later.
  # ---------------------------------------------------------------------------
  describe "onboarding flow — registration_changeset (step 1)" do
    test "succeeds with only step-1 fields — bio and medium are not required" do
      user = user_fixture()
      changeset = Artists.registration_change_artist(%Artist{}, %{
        nickname: "EarlyBird",
        first_name: "Test",
        last_name: "Artist",
        phone: "416-555-1234",
        email: "early@example.com",
        street_address: "100 Test St",
        area_code: "M5H 2N2",
        user_id: user.id
      })
      assert changeset.valid?
    end

    # Each field below IS required at step 1
    test "requires nickname" do
      changeset = Artists.registration_change_artist(%Artist{}, %{nickname: nil})
      assert "can't be blank" in errors_on(changeset).nickname
    end

    test "requires email" do
      changeset = Artists.registration_change_artist(%Artist{}, %{email: nil})
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires phone" do
      changeset = Artists.registration_change_artist(%Artist{}, %{phone: nil})
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "requires street_address" do
      changeset = Artists.registration_change_artist(%Artist{}, %{street_address: nil})
      assert "can't be blank" in errors_on(changeset).street_address
    end

    # These fields are NOT required at registration — no error expected
    test "allows bio to be nil (not collected until step 2)" do
      changeset = Artists.registration_change_artist(%Artist{}, %{bio: nil})
      assert Map.get(errors_on(changeset), :bio, []) == []
    end

    test "allows medium to be nil (not collected until step 2)" do
      changeset = Artists.registration_change_artist(%Artist{}, %{medium: nil})
      assert Map.get(errors_on(changeset), :medium, []) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Onboarding flow — activation_changeset (full profile)
  #
  # This is the strict changeset used for the final profile save. All required
  # fields must be present. If a vendor tries to bypass step 2 (bio, medium)
  # and jump straight to the final save, activation_changeset will reject it.
  # ---------------------------------------------------------------------------
  describe "onboarding flow — activation_changeset (full profile)" do
    test "succeeds when all required fields are present" do
      changeset = Artist.activation_changeset(%Artist{}, @valid_attrs)
      # Note: valid? is true even without user_id because assoc_constraint only
      # fires at the DB level (FK violation), not at changeset-build time.
      assert changeset.valid?
    end

    # If an artist somehow calls the final save without having filled in step 2,
    # activation_changeset must reject it — bio is required for the full profile.
    test "fails when bio is missing — cannot activate without completing step 2" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :bio, nil))
      assert "can't be blank" in errors_on(changeset).bio
    end

    # Same for medium — without a medium the public profile would be empty.
    test "fails when medium is missing — cannot activate without completing step 2" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :medium, nil))
      assert "can't be blank" in errors_on(changeset).medium
    end

    # A bio that is too short fails even if it is present — we require substance.
    test "fails when bio is too short (under 75 characters)" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :bio, "Too short."))
      assert errors_on(changeset).bio != []
    end

    # If an artist who completed step 1 (has nickname, email, etc. but no bio)
    # attempts activation, they should get a clear error, not a crash.
    test "fails when called on a step-1-only artist — bio and medium still required" do
      step1_attrs = %{
        nickname: "Incomplete",
        first_name: "Test",
        last_name: "Artist",
        phone: "416-555-1234",
        email: "incomplete@example.com",
        street_address: "100 Test St",
        area_code: "M5H 2N2"
        # bio and medium intentionally omitted — simulates step 1 → step 3 jump
      }
      changeset = Artist.activation_changeset(%Artist{}, step1_attrs)
      refute changeset.valid?
      assert errors_on(changeset).bio != []
      assert errors_on(changeset).medium != []
    end
  end

  # ---------------------------------------------------------------------------
  # Onboarding flow — onboarding_complete field
  #
  # This boolean is what distinguishes "profile being set up" from "profile
  # is live and can be edited freely." It defaults to false and is only set
  # to true explicitly by save_artist(:edit) at the end of onboarding.
  # ---------------------------------------------------------------------------
  describe "onboarding flow — onboarding_complete field" do
    test "defaults to false on a new artist" do
      changeset = Artist.activation_changeset(%Artist{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :onboarding_complete) == false
    end

    test "activation_changeset accepts onboarding_complete: true" do
      attrs = Map.put(@valid_attrs, :onboarding_complete, true)
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :onboarding_complete) == true
    end

    test "registration_changeset also accepts onboarding_complete" do
      changeset = Artists.registration_change_artist(%Artist{}, %{onboarding_complete: true})
      assert Ecto.Changeset.get_field(changeset, :onboarding_complete) == true
    end
  end

  # ---------------------------------------------------------------------------
  # Basic read operations
  # ---------------------------------------------------------------------------
  describe "read operations" do
    test "list_artists/0 returns all active artists" do
      artist = artist_fixture()
      result = Artists.list_artists()
      assert length(result) == 1
      assert hd(result).id == artist.id
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

  # ---------------------------------------------------------------------------
  # filter_artists_by_area/1
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # filter_artists_by_medium/1
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # filter_artists/1 — combined name + medium + sort filter used by the public
  # artist index page
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # filter_artists/1 — status scoping
  # These mirror the list_artists/0 tests but for the filter path specifically,
  # since filter_artists has its own with_status(:active) call.
  # ---------------------------------------------------------------------------
  describe "filter_artists/1 - status scoping" do
    test "excludes inactive artists" do
      artist_fixture(%{status: :inactive})
      result = Artists.filter_artists(%{"q_name" => "", "q_medium" => "", "sort_by" => ""})
      assert result == []
    end

    test "excludes removed artists" do
      artist_fixture(%{status: :removed})
      result = Artists.filter_artists(%{"q_name" => "", "q_medium" => "", "sort_by" => ""})
      assert result == []
    end

    test "includes active artists" do
      artist = artist_fixture(%{status: :active})
      result = Artists.filter_artists(%{"q_name" => "", "q_medium" => "", "sort_by" => ""})
      assert length(result) == 1
      assert hd(result).id == artist.id
    end
  end

  # ---------------------------------------------------------------------------
  # Artists.create_artist/1
  # ---------------------------------------------------------------------------
  describe "Artists.create_artist/1" do
    test "creates artist and default Uncategorized collection atomically" do
      assert {:ok, artist} = Artists.create_artist(@valid_attrs)
      collections = Products.list_collections_for_artist(artist.id)
      assert length(collections) == 1
      assert hd(collections).name == "Uncategorized"
    end

    test "returns error changeset when artist attrs are invalid" do
      assert {:error, %Ecto.Changeset{}} = Artists.create_artist(%{nickname: nil})
    end

    # New artists start inactive so they can finish onboarding before going live.
    # An admin or the onboarding completion step sets them to active.
    test "new artist defaults to inactive status" do
      {:ok, artist} = Artists.create_artist(@valid_attrs)
      assert artist.status == :inactive
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — required fields (activation_changeset)
  #
  # activation_changeset is the full-profile changeset used for the final
  # onboarding save and for all subsequent profile edits.
  # ---------------------------------------------------------------------------
  describe "Artist changeset - required fields" do
    test "valid changeset with all required fields" do
      changeset = Artist.activation_changeset(%Artist{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires nickname" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :nickname, nil))
      assert "can't be blank" in errors_on(changeset).nickname
    end

    test "requires first_name" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :first_name, nil))
      assert "can't be blank" in errors_on(changeset).first_name
    end

    test "requires last_name" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :last_name, nil))
      assert "can't be blank" in errors_on(changeset).last_name
    end

    test "requires email" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :email, nil))
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires phone" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :phone, nil))
      assert "can't be blank" in errors_on(changeset).phone
    end

    test "requires bio" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :bio, nil))
      assert "can't be blank" in errors_on(changeset).bio
    end

    test "requires street_address" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :street_address, nil))
      assert "can't be blank" in errors_on(changeset).street_address
    end

    test "requires area_code" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :area_code, nil))
      assert "can't be blank" in errors_on(changeset).area_code
    end

    test "requires medium" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :medium, nil))
      assert "can't be blank" in errors_on(changeset).medium
    end

    test "allows middle_name to be nil" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :middle_name, nil))
      assert changeset.valid?
    end

    test "allows apt_info to be nil" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :apt_info, nil))
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — length validations
  # ---------------------------------------------------------------------------
  describe "Artist changeset - length validations" do
    test "rejects bio shorter than 75 characters" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :bio, String.duplicate("a", 74)))
      assert errors_on(changeset).bio != []
    end

    test "accepts bio of exactly 75 characters" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :bio, String.duplicate("a", 75)))
      assert changeset.valid?
    end

    test "rejects first_name shorter than 2 characters" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :first_name, "A"))
      assert errors_on(changeset).first_name != []
    end

    test "accepts first_name of exactly 2 characters" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :first_name, "Al"))
      assert changeset.valid?
    end

    test "rejects last_name shorter than 2 characters" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :last_name, "B"))
      assert errors_on(changeset).last_name != []
    end

    test "accepts last_name of exactly 2 characters" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :last_name, "Li"))
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — email validation
  # ---------------------------------------------------------------------------
  describe "Artist changeset - email validation" do
    test "accepts valid email" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :email, "test@example.com"))
      assert changeset.valid?
    end

    test "rejects email without @ sign" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :email, "notanemail"))
      assert errors_on(changeset).email != []
    end

    test "rejects email without domain extension" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :email, "user@nodot"))
      assert errors_on(changeset).email != []
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — phone validation
  # ---------------------------------------------------------------------------
  describe "Artist changeset - phone validation" do
    test "accepts standard North American format with dashes" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :phone, "416-555-1234"))
      assert changeset.valid?
    end

    test "accepts format with parentheses" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :phone, "(416) 555-1234"))
      assert changeset.valid?
    end

    test "accepts format with country code" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :phone, "+1-416-555-1234"))
      assert changeset.valid?
    end

    test "rejects non-numeric phone" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :phone, "not-a-phone"))
      assert errors_on(changeset).phone != []
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — announcement
  #
  # The announcement is an optional short text shown on the artist's public
  # profile. It is capped at 100 characters because it appears in a banner.
  # ---------------------------------------------------------------------------
  describe "Artist changeset - announcement" do
    test "accepts announcement text and active flag" do
      attrs = Map.merge(@valid_attrs, %{announcement: "Studio open this weekend!", announcement_active: true})
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert changeset.valid?
    end

    test "announcement_active defaults to false" do
      changeset = Artist.activation_changeset(%Artist{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :announcement_active) == false
    end

    test "allows announcement to be nil (vendor hasn't set one)" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :announcement, nil))
      assert changeset.valid?
    end

    # 100 characters is the hard limit — anything longer would break the banner layout
    test "rejects announcement over 100 characters" do
      long_text = String.duplicate("x", 101)
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :announcement, long_text))
      assert errors_on(changeset).announcement != []
    end

    test "accepts announcement of exactly 100 characters" do
      text = String.duplicate("x", 100)
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :announcement, text))
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — status
  # ---------------------------------------------------------------------------
  describe "Artist changeset - status" do
    test "defaults to inactive" do
      changeset = Artist.activation_changeset(%Artist{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == :inactive
    end

    test "accepts valid status values" do
      for status <- [:active, :inactive, :removed] do
        changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :status, status))
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end

    test "sets status_changed_at when status changes" do
      artist = artist_fixture(%{status: :inactive})
      changeset = Artist.activation_changeset(artist, %{status: :active})
      assert Ecto.Changeset.get_change(changeset, :status_changed_at) != nil
    end

    test "does not update status_changed_at when status is unchanged" do
      artist = artist_fixture(%{status: :active})
      changeset = Artist.activation_changeset(artist, %{nickname: "New Name"})
      assert Ecto.Changeset.get_change(changeset, :status_changed_at) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — status_changeset/2
  #
  # A lightweight changeset used by remove_artist/1 and status toggles.
  # It only touches the status field — other fields are ignored, so there is
  # no risk of accidentally overwriting profile data.
  # ---------------------------------------------------------------------------
  describe "Artist changeset - status_changeset/2" do
    test "changes the status field" do
      artist = artist_fixture(%{status: :inactive})
      changeset = Artist.status_changeset(artist, %{status: :active})
      assert Ecto.Changeset.get_change(changeset, :status) == :active
    end

    test "sets status_changed_at when status changes" do
      artist = artist_fixture(%{status: :inactive})
      changeset = Artist.status_changeset(artist, %{status: :removed})
      assert Ecto.Changeset.get_change(changeset, :status_changed_at) != nil
    end

    # status_changeset should not accept other fields — if it did, it could
    # be misused to overwrite bio, nickname, etc. without full validation.
    test "ignores non-status fields" do
      artist = artist_fixture()
      changeset = Artist.status_changeset(artist, %{status: :removed, nickname: "Hacker"})
      assert Ecto.Changeset.get_change(changeset, :nickname) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — delivery options
  # ---------------------------------------------------------------------------
  describe "Artist changeset - delivery options" do
    test "accepts valid delivery options" do
      attrs = Map.put(@valid_attrs, :delivery_options, ["pickup", "shipping"])
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert changeset.valid?
    end

    test "rejects unknown delivery option values" do
      attrs = Map.put(@valid_attrs, :delivery_options, ["teleportation"])
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert errors_on(changeset).delivery_options != []
    end

    test "accepts delivery_info with matching keys" do
      attrs = Map.merge(@valid_attrs, %{
        delivery_options: ["pickup", "shipping"],
        delivery_info: %{"pickup" => "By appointment", "shipping" => "Canada Post only"}
      })
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert changeset.valid?
    end

    test "rejects delivery_info with keys not in delivery_options" do
      attrs = Map.merge(@valid_attrs, %{
        delivery_options: ["pickup"],
        delivery_info: %{"shipping" => "some note"}
      })
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert errors_on(changeset).delivery_info != []
    end

    test "rejects delivery note longer than 500 characters" do
      long_note = String.duplicate("x", 501)
      attrs = Map.merge(@valid_attrs, %{
        delivery_options: ["pickup"],
        delivery_info: %{"pickup" => long_note}
      })
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert errors_on(changeset).delivery_info != []
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — social links
  # ---------------------------------------------------------------------------
  describe "Artist changeset - social links" do
    test "accepts valid homepage URL" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :homepage, "https://www.example.com"))
      assert changeset.valid?
    end

    test "rejects malformed homepage URL" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :homepage, "not a url"))
      assert errors_on(changeset).homepage != []
    end

    test "accepts valid instagram URL" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :instagram, "https://instagram.com/myprofile"))
      assert changeset.valid?
    end

    test "accepts valid facebook URL" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :facebook, "https://facebook.com/mypage"))
      assert changeset.valid?
    end

    test "allows all social links to be nil" do
      attrs = Map.merge(@valid_attrs, %{homepage: nil, instagram: nil, facebook: nil})
      changeset = Artist.activation_changeset(%Artist{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Artist changeset — area_code (Canadian postal code) validation
  # ---------------------------------------------------------------------------
  describe "Artist changeset - area_code (Canadian postal code) validation" do
    test "accepts postal code with space" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "M5H 2N2"))
      assert changeset.valid?
    end

    test "accepts postal code without space" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "M5H2N2"))
      assert changeset.valid?
    end

    test "accepts lowercase postal code" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "m5h2n2"))
      assert changeset.valid?
    end

    test "rejects US ZIP code format" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "10001"))
      assert errors_on(changeset).area_code != []
    end

    test "rejects postal code with wrong letter/digit pattern" do
      changeset = Artist.activation_changeset(%Artist{}, Map.put(@valid_attrs, :area_code, "MM5 2N2"))
      assert errors_on(changeset).area_code != []
    end
  end

  # ---------------------------------------------------------------------------
  # ArtistImage context
  # ---------------------------------------------------------------------------
  describe "ArtistImage context" do
    test "create_artist_image/2 creates an image for an artist" do
      artist = artist_fixture()
      assert {:ok, image} = Artists.create_artist_image(artist, %{path: "/uploads/test.jpg", position: 1})
      assert image.path == "/uploads/test.jpg"
      assert image.position == 1
      assert image.artist_id == artist.id
    end

    test "get_images_for_artist/1 returns images ordered by position" do
      artist = artist_fixture()
      {:ok, _} = Artists.create_artist_image(artist, %{path: "/uploads/b.jpg", position: 2})
      {:ok, _} = Artists.create_artist_image(artist, %{path: "/uploads/a.jpg", position: 1})
      images = Artists.get_images_for_artist(artist)
      assert length(images) == 2
      assert hd(images).position == 1
    end

    test "get_images_for_artist/1 returns only images for the given artist" do
      artist = artist_fixture()
      other  = artist_fixture()
      {:ok, _} = Artists.create_artist_image(artist, %{path: "/uploads/mine.jpg",   position: 1})
      {:ok, _} = Artists.create_artist_image(other,  %{path: "/uploads/theirs.jpg", position: 1})
      images = Artists.get_images_for_artist(artist)
      assert length(images) == 1
      assert hd(images).path == "/uploads/mine.jpg"
    end

    test "swap_image_positions/2 swaps positions of two images" do
      artist = artist_fixture()
      {:ok, img1} = Artists.create_artist_image(artist, %{path: "/uploads/first.jpg",  position: 1})
      {:ok, img2} = Artists.create_artist_image(artist, %{path: "/uploads/second.jpg", position: 2})
      assert {:ok, _} = Artists.swap_image_positions(img1, img2)
      [reloaded_first, reloaded_second] = Artists.get_images_for_artist(artist)
      assert reloaded_first.path  == "/uploads/second.jpg"
      assert reloaded_second.path == "/uploads/first.jpg"
    end

    test "delete_artist_image/1 removes the image" do
      artist = artist_fixture()
      {:ok, image} = Artists.create_artist_image(artist, %{path: "/uploads/gone.jpg", position: 1})
      assert {:ok, _} = Artists.delete_artist_image(image)
      assert Artists.get_images_for_artist(artist) == []
    end
  end
end
