defmodule ArtsyNeighbor.SampleDataTest do
  @moduledoc """
  `SampleData` (the preview's and seeds.exs's sample artists): adding
  and removing, tested with small made-up artists, and checks on the
  real data files in `priv/repo/sample_data/`, so a run on Fly doesn't
  stop halfway on a missing photo or category.

  Storage here is `Storage.Local` in a temporary folder (see
  `config/test.exs`).
  """
  use ArtsyNeighbor.DataCase, async: true

  import ExUnit.CaptureIO
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Accounts.Admin
  alias ArtsyNeighbor.Accounts.User
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists.ArtistImage
  alias ArtsyNeighbor.Categories.Category
  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Products.ProductImage
  alias ArtsyNeighbor.Release
  alias ArtsyNeighbor.SampleData
  alias ArtsyNeighbor.Storage
  alias ArtsyNeighbor.Storage.Local

  @sculptures %{
    name: "Sculptures",
    slug: "sculptures",
    description: "Sculptures",
    main_img: nil
  }

  # One small artist: a profile photo, one work with a photo and one
  # without. The photos are site images from priv/static/images/.
  defp entry(overrides \\ %{}) do
    Map.merge(
      %{
        user: %{email: "kit.sample@example.com", username: "kit_sample"},
        photo_dir: "images",
        photos: ["cat-sculpture.jpg"],
        artist: %{
          nickname: "Kit Sample",
          first_name: "Kit",
          last_name: "Sample",
          email: "kit.sample@example.com",
          phone: "250-555-0100",
          street_address: "1 Sample Street",
          area_code: "V8V 1A1",
          medium: ["Sculpture"],
          bio:
            "Makes small sample sculptures of cats and dogs in a garden studio, " <>
              "mostly from local clay.",
          delivery_options: ["pickup"],
          delivery_info: %{}
        },
        collections: [
          %{
            name: "Cats",
            works: [
              %{
                title: "Clay Cat",
                descr: "A small clay cat.",
                details: "Fired clay.",
                price: 120,
                category: "Sculptures",
                photos: ["pottery-cat.jpg"]
              },
              %{
                title: "Unphotographed Cat",
                descr: "Another small clay cat.",
                details: "Fired clay.",
                price: 90,
                category: "Sculptures",
                photos: []
              }
            ]
          }
        ]
      },
      overrides
    )
  end

  # A second, different artist (own nickname, login and contact email).
  defp other_entry do
    entry(%{
      user: %{email: "lou.sample@example.com", username: "lou_sample"},
      artist: Map.merge(entry().artist, %{nickname: "Lou Sample", email: "lou@example.com"}),
      photos: [],
      collections: []
    })
  end

  # Runs `fun` without printing its progress lines into the test output,
  # and returns what it printed.
  defp quietly(fun) do
    capture_io(fun)
  end

  # Adds the category and then `entries`; returns add_artists/1's result.
  defp add_sample_artists(entries) do
    quietly(fn -> SampleData.add_categories([@sculptures]) end)

    {result, _output} = with_io(fn -> SampleData.add_artists(entries) end)
    result
  end

  # Runs the test body, then deletes the photo files it stored (the
  # database rows go away with the test's transaction, the files don't),
  # also when an assertion in the body fails.
  defp with_photo_cleanup(fun) do
    fun.()
  after
    keys =
      Repo.all(from(i in ArtistImage, select: i.path)) ++
        Repo.all(from(i in ProductImage, select: i.path))

    for key <- keys, Storage.image_folder?(key) do
      Storage.delete_prefix(key)
    end
  end

  describe "add_categories/1" do
    test "adds the categories, and skips them the second time" do
      quietly(fn -> SampleData.add_categories([@sculptures]) end)
      output = quietly(fn -> SampleData.add_categories([@sculptures]) end)

      assert output =~ "Skipped category Sculptures"
      assert Repo.aggregate(from(c in Category, where: c.slug == "sculptures"), :count) == 1
    end

    test "skips a category whose name is there with another slug, and works use it" do
      # Like a category made by hand on the site, with its own slug.
      existing =
        %Category{}
        |> Category.changeset(%{
          name: "Sculptures",
          slug: "sculpture-by-hand",
          description: "Made by hand in the admin pages."
        })
        |> Repo.insert!()

      output = quietly(fn -> SampleData.add_categories([@sculptures]) end)

      assert output =~ "Skipped category Sculptures"
      assert Repo.aggregate(from(c in Category, where: c.name == "Sculptures"), :count) == 1

      with_photo_cleanup(fn ->
        assert add_sample_artists([entry()]) == :ok
        product = Repo.get_by!(Product, title: "Clay Cat")
        assert product.category_id == existing.id
      end)
    end
  end

  describe "add_artists/1" do
    test "adds a public artist who can log in, with stored photos" do
      with_photo_cleanup(fn ->
        assert add_sample_artists([entry()]) == :ok

        artist = Repo.get_by!(Artist, nickname: "Kit Sample")
        assert artist.status == :active
        assert artist.onboarding_complete

        user =
          Accounts.get_user_by_email_and_password("kit.sample@example.com", "DevPassword1!")

        assert user.id == artist.user_id
        assert user.confirmed_at

        [profile_photo] = Repo.all(from(i in ArtistImage, where: i.artist_id == ^artist.id))
        assert String.starts_with?(profile_photo.path, "artists/#{artist.id}/")
        assert File.exists?(Local.path_for(profile_photo.path <> "/thumb.webp", :public))
        assert File.exists?(Local.path_for(profile_photo.path <> "/source.webp", :private))
      end)
    end

    test "puts the works in an Uncategorized collection first, then theirs" do
      with_photo_cleanup(fn ->
        add_sample_artists([entry()])
        artist = Repo.get_by!(Artist, nickname: "Kit Sample")

        collections =
          Repo.all(
            from(c in ProductCollection,
              where: c.artist_id == ^artist.id,
              order_by: c.position,
              select: c.name
            )
          )

        assert collections == ["Uncategorized", "Cats"]
      end)
    end

    test "a work with a photo is for sale, one without stays a draft" do
      with_photo_cleanup(fn ->
        add_sample_artists([entry()])

        clay_cat = Repo.get_by!(Product, title: "Clay Cat")
        assert clay_cat.status == :available
        [photo] = Repo.all(from(i in ProductImage, where: i.product_id == ^clay_cat.id))
        assert String.starts_with?(photo.path, "products/#{clay_cat.id}/")

        assert Repo.get_by!(Product, title: "Unphotographed Cat").status == :draft
      end)
    end

    test "an artist without a profile photo stays a draft, as on the site" do
      with_photo_cleanup(fn ->
        assert add_sample_artists([entry(%{photos: []})]) == :ok

        assert Repo.get_by!(Artist, nickname: "Kit Sample").status == :inactive
      end)
    end

    test "skips an artist whose nickname is already there" do
      with_photo_cleanup(fn ->
        add_sample_artists([entry()])
        output = quietly(fn -> SampleData.add_artists([entry()]) end)

        assert output =~ "Skipped Kit Sample"
        assert Repo.aggregate(from(a in Artist, where: a.nickname == "Kit Sample"), :count) == 1
        assert Repo.aggregate(ArtistImage, :count) == 1
      end)
    end

    test "reuses an existing user with the same email, keeping their password" do
      user =
        user_fixture(%{email: "kit.sample@example.com", username: "kit_sample"})
        |> set_password()

      add_sample_artists([entry(%{photos: [], collections: []})])

      assert Repo.get_by!(Artist, nickname: "Kit Sample").user_id == user.id

      assert Accounts.get_user_by_email_and_password(
               "kit.sample@example.com",
               valid_user_password()
             )
    end

    test "never gives an account a second artist profile (e.g. after a rename)" do
      add_sample_artists([entry(%{photos: [], collections: []})])

      # The artist renames their profile, and the sample data is added again.
      Repo.get_by!(Artist, nickname: "Kit Sample")
      |> Ecto.Changeset.change(nickname: "Kit Sample Studio")
      |> Repo.update!()

      assert add_sample_artists([entry(%{photos: [], collections: []})]) ==
               {:error, ["Kit Sample"]}

      user = Repo.get_by!(User, email: "kit.sample@example.com")
      assert Repo.aggregate(from(a in Artist, where: a.user_id == ^user.id), :count) == 1
    end

    test "a username taken by someone else skips that artist, not the rest" do
      user_fixture(%{username: "kit_sample"})

      assert add_sample_artists([entry(%{photos: [], collections: []}), other_entry()]) ==
               {:error, ["Kit Sample"]}

      assert Repo.get_by(Artist, nickname: "Kit Sample") == nil
      assert Repo.get_by(Artist, nickname: "Lou Sample")
    end

    test "if a photo fails, the artist is removed again and the rest still go in" do
      broken = entry(%{photos: ["cat-sculpture.jpg", "no-such-photo.jpg"]})

      output =
        quietly(fn ->
          SampleData.add_categories([@sculptures])
          assert SampleData.add_artists([broken, other_entry()]) == {:error, ["Kit Sample"]}
        end)

      assert output =~ "the photo images/no-such-photo.jpg could not be added"
      assert output =~ "NOT ADDED"

      # Hard-deleted again, rows and photos (their files are deleted in
      # the background, which photo_file_deletion_test.exs checks).
      assert Repo.get_by(Artist, nickname: "Kit Sample") == nil
      assert Repo.aggregate(ArtistImage, :count) == 0
      assert Repo.get_by(Artist, nickname: "Lou Sample")
    end

    test "a missing category stops it with a clear message" do
      assert_raise RuntimeError, ~r/Category Sculptures is missing/, fn ->
        quietly(fn -> SampleData.add_artists([entry(%{photos: []})]) end)
      end
    end
  end

  describe "the developer's studio (user: :first_admin)" do
    defp studio_entry do
      entry(%{
        user: :first_admin,
        fallback_user: %{email: "studio.sample@example.com", username: "studio_sample"},
        photos: [],
        collections: []
      })
    end

    defp make_admin do
      user = set_password(user_fixture())
      Repo.insert!(%Admin{user_id: user.id})
      user
    end

    test "is linked to the admin account if it has no artist profile" do
      admin_user = make_admin()
      add_sample_artists([studio_entry()])

      assert Repo.get_by!(Artist, nickname: "Kit Sample").user_id == admin_user.id
    end

    test "gets its own login if the first admin already has an artist profile" do
      first_admin = make_admin()
      artist_fixture(%{user_id: first_admin.id})
      # A second admin without a profile must not get the studio.
      make_admin()

      add_sample_artists([studio_entry()])

      studio = Repo.get_by!(Artist, nickname: "Kit Sample")
      assert Repo.get!(User, studio.user_id).email == "studio.sample@example.com"
    end
  end

  describe "remove_all/0 and leftovers/0" do
    # Uses the real data files' emails and nicknames: a sample account
    # (maren.demo@example.com) with an artist, and the developer's
    # studio linked to an admin.
    setup do
      quietly(fn -> SampleData.add_categories([@sculptures]) end)

      maren_user =
        user_fixture(%{email: "maren.demo@example.com", username: "maren_demo"})
        |> set_password()

      # Renamed, to show it's found through the account, not the nickname.
      maren = artist_fixture(%{user_id: maren_user.id, nickname: "Maren Renamed"})
      maren_session = Accounts.generate_user_session_token(maren_user)

      admin_user = make_admin()

      studio =
        artist_fixture(%{user_id: admin_user.id, nickname: "Anna's Magnificent Art Studio"})

      someone_else = artist_fixture()

      %{
        maren_user: maren_user,
        maren: maren,
        maren_session: maren_session,
        admin_user: admin_user,
        studio: studio,
        someone_else: someone_else
      }
    end

    test "lists what is left before, and nothing after", context do
      assert SampleData.leftovers() == [
               "sample account not locked: maren.demo@example.com",
               "sample artist still there: Anna's Magnificent Art Studio"
             ]

      quietly(fn -> SampleData.remove_all() end)

      assert SampleData.leftovers() == []
      # Safe to run twice.
      quietly(fn -> assert SampleData.remove_all() == :ok end)
      assert Repo.get(Artist, context.someone_else.id)
    end

    test "deletes the sample artists, and locks the sample accounts", context do
      quietly(fn -> SampleData.remove_all() end)

      assert Repo.get(Artist, context.maren.id) == nil
      assert Repo.get(Artist, context.studio.id) == nil

      maren_user = Repo.get!(User, context.maren_user.id)
      assert maren_user.status == :removed

      assert Accounts.get_user_by_email_and_password(
               "maren.demo@example.com",
               valid_user_password()
             ) == nil

      assert Accounts.get_user_by_session_token(context.maren_session) == nil
    end

    test "leaves the admin account and other artists alone", context do
      quietly(fn -> SampleData.remove_all() end)

      admin_user = Repo.get!(User, context.admin_user.id)
      assert admin_user.status == :active
      assert Accounts.get_user_by_email_and_password(admin_user.email, valid_user_password())
      assert Repo.get(Artist, context.someone_else.id)
    end

    test "Release.check_before_launch/0 refuses until it's removed" do
      assert_raise RuntimeError, ~r/NOT READY/, fn ->
        quietly(fn -> Release.check_before_launch() end)
      end

      quietly(fn -> SampleData.remove_all() end)

      # While a trial page is served (photo speed step 3c), the check
      # still refuses, for that reason alone.
      output =
        quietly(fn ->
          if Release.trial_pages() == [] do
            assert Release.check_before_launch() == :ok
          else
            assert_raise RuntimeError, ~r/NOT READY/, fn -> Release.check_before_launch() end
          end
        end)

      assert output =~ "OK: no sample data left"
    end
  end

  describe "Release.trial_pages/1" do
    test "finds the trial-page folders among the served folders" do
      assert Release.trial_pages(~w(assets images trials robots.txt)) == ["trials"]
      assert Release.trial_pages(~w(assets images robots.txt)) == []
    end
  end

  describe "the data files in priv/repo/sample_data/" do
    test "every photo exists and would be accepted by the photo checks" do
      for entry <- SampleData.all_artist_entries(), photo <- SampleData.photos_of(entry) do
        file = Path.join(["priv/static", entry.photo_dir, photo])
        assert File.exists?(file), "missing photo #{file}"
        assert Images.check_file(file) == :ok, "#{file}: #{inspect(Images.check_file(file))}"
      end
    end

    test "every work's category is in categories.exs" do
      category_names =
        for category <- SampleData.load("categories"), do: category.name

      for entry <- SampleData.all_artist_entries(),
          collection <- entry.collections,
          work <- collection.works do
        assert work.category in category_names,
               "#{work.title}: unknown category #{work.category}"
      end
    end

    # The changeset's errors, leaving out the ids the adding fills in.
    defp errors_without_ids(changeset) do
      ids = [:user_id, :artist_id, :collection_id, :category_id]

      for {field, error} <- changeset.errors, field not in ids do
        {field, error}
      end
    end

    test "every artist and work passes its changeset" do
      for entry <- SampleData.all_artist_entries() do
        artist_changeset = Artist.activation_changeset(%Artist{}, entry.artist)

        assert errors_without_ids(artist_changeset) == [],
               "#{entry.artist.nickname}: #{inspect(artist_changeset.errors)}"

        for collection <- entry.collections, work <- collection.works do
          work_attrs = Map.drop(work, [:photos, :category])
          work_changeset = Product.changeset(%Product{}, Map.put(work_attrs, :position, 1))

          assert errors_without_ids(work_changeset) == [],
                 "#{work.title}: #{inspect(work_changeset.errors)}"
        end
      end
    end

    test "every artist has a profile photo, so all of them go public" do
      for entry <- SampleData.all_artist_entries() do
        assert entry.photos != [], "#{entry.artist.nickname} has no profile photo"
      end
    end

    test "nicknames, emails and usernames are unique" do
      entries = SampleData.all_artist_entries()
      nicknames = for entry <- entries, do: entry.artist.nickname
      emails = for entry <- entries, do: entry.artist.email
      usernames = for entry <- entries, is_map(entry.user), do: entry.user.username

      assert Enum.uniq(nicknames) == nicknames
      assert Enum.uniq(emails) == emails
      assert Enum.uniq(usernames) == usernames
    end

    test "there are 13 artists" do
      assert length(SampleData.all_artist_entries()) == 13
    end
  end

  test "Release.add_sample_data/0 refuses to run outside a preview app" do
    # FLY_APP_NAME is only set on Fly machines.
    assert System.get_env("FLY_APP_NAME") == nil

    assert_raise RuntimeError, ~r/not a preview app/, fn ->
      Release.add_sample_data()
    end
  end
end
