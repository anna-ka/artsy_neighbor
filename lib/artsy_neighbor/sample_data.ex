defmodule ArtsyNeighbor.SampleData do
  @moduledoc """
  Made-up sample data: the categories, artists with their profile
  photos, collections and works, and a user account for each artist.
  For development, and for the private preview on Fly, so the people
  helping with the site's looks have something to look at. Never for a
  real site (see `ArtsyNeighbor.Release.add_sample_data/0`): the sample
  accounts share one password, which is in the repository.

  The data itself is in `priv/repo/sample_data/`, one `.exs` file per
  group, each holding a plain list of maps. This module adds it
  (`add_all/0`), takes it away again (`remove_all/0`), and says what is
  left of it (`leftovers/0`).

  ## Adding

    * **It only adds.** Nothing existing is changed or deleted. A
      category whose slug or name is already there, or an artist whose nickname
      is already there, is skipped, so running it twice is safe.
    * **Every artist can log in**, with the email of their `user` and
      the password `"DevPassword1!"`. An existing user with that email
      is reused (keeping their own password), unless they already have
      an artist profile: then that artist is not added.
    * **The site's own rules apply.** Each artist and their works go
      in as drafts; then their photos are added like an artist's
      uploads (`Images.process_upload/3`, so on Fly they end up in
      Tigris), and only then is the artist made public
      (`Artists.activate_artist/1`) and each work put up for sale
      (`Products.publish_product/2`). Those refuse an artist or a work
      without a photo, as on the site.
    * **One artist failing doesn't stop the rest.** If something goes
      wrong with an artist (a photo can't be processed, the site is too
      busy), whatever was added of them is hard-deleted again, photos
      included, and the next artist is tried. At the end it lists the
      artists that weren't added; running it again retries them.

  ## The shape of an artist entry

      %{
        user: %{email: "maren.demo@example.com", username: "maren_demo"},
        photo_dir: "images/seed/demo/maren",    # under priv/static/
        photos: ["artist-1.jpg"],               # profile photos, in order
        artist: %{nickname: "Maren Holt", ...}, # fields for Artist.activation_changeset/2
        collections: [
          %{name: "Shoreline", works: [
            %{title: "Green Water", price: 950, category: "Paintings",
              photos: ["shore-2.jpg"], ...}     # fields for Product.changeset/2
          ]}
        ]
      }

  `user` can also be `:first_admin`, with a `fallback_user` (see
  `annas_studio.exs`): the studio is linked to the first admin
  account, or, if that account already has an artist profile, gets the
  fallback login. Every artist gets an "Uncategorized" collection
  first, as in the app, unless their first collection already has that
  name.
  """

  import Ecto.Query, only: [from: 2]

  alias ArtsyNeighbor.Accounts.Admin
  alias ArtsyNeighbor.Accounts.Scope
  alias ArtsyNeighbor.Accounts.User
  alias ArtsyNeighbor.Accounts.UserToken
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists.ArtistImage
  alias ArtsyNeighbor.Categories.Category
  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Products.ProductImage
  alias ArtsyNeighbor.Repo

  @password "DevPassword1!"

  @artist_files ["seed_artists", "annas_studio", "demo_artists"]

  # ------------------------------------------------------------------
  # The data
  # ------------------------------------------------------------------

  @doc """
  Reads one data file from `priv/repo/sample_data/`, e.g.
  `load("categories")`, and returns its list.
  """
  def load(name) do
    path = Application.app_dir(:artsy_neighbor, "priv/repo/sample_data/#{name}.exs")
    {data, _bindings} = Code.eval_file(path)
    data
  end

  @doc "All sample artist entries, from every artist data file."
  def all_artist_entries do
    Enum.flat_map(@artist_files, fn name -> load(name) end)
  end

  @doc "An entry's profile photos followed by all its works' photos."
  def photos_of(entry) do
    work_photos =
      for collection <- entry.collections, work <- collection.works, photo <- work.photos do
        photo
      end

    entry.photos ++ work_photos
  end

  @doc """
  The file of one sample photo: `photo` (e.g. `"shore-2.jpg"`) in an
  entry's `photo_dir` (e.g. `"images/seed/demo/maren"`), which is under
  `priv/static/`.
  """
  def photo_file(photo_dir, photo) do
    relative_path = Path.join(photo_dir, photo)
    Application.app_dir(:artsy_neighbor, Path.join("priv/static", relative_path))
  end

  # Every email a sample account can have (the `fallback_user` too,
  # but never the admin's: the studio's `user: :first_admin`).
  defp sample_emails(entries) do
    for entry <- entries, user <- [entry.user, Map.get(entry, :fallback_user)], is_map(user) do
      user.email
    end
  end

  # Nicknames of the entries that may belong to the admin account.
  defp admin_nicknames(entries) do
    for entry <- entries, entry.user == :first_admin do
      entry.artist.nickname
    end
  end

  # ------------------------------------------------------------------
  # Adding
  # ------------------------------------------------------------------

  @doc """
  Adds everything: the categories, the six original seed artists, the
  developer's studio and the six demo artists. Returns `:ok`, or
  `{:error, nicknames}` listing the artists that weren't added.
  """
  def add_all do
    add_categories(load("categories"))
    result = add_artists(all_artist_entries())
    IO.puts("Sample artists log in with their email and the password #{@password}")
    result
  end

  @doc "Adds only the six demo artists. The categories must be there already."
  def add_demo_artists do
    result = add_artists(load("demo_artists"))
    IO.puts("Demo artists log in with their email and the password #{@password}")
    result
  end

  @doc """
  Adds each category whose slug and name aren't in the database yet.
  Both are checked because both must be unique: a category made by hand
  can have the same name with a different slug. (The works find their
  category by name, so they use the existing one.)
  """
  def add_categories(categories) do
    for category <- categories do
      already_there =
        from(c in Category, where: c.slug == ^category.slug or c.name == ^category.name)

      if Repo.exists?(already_there) do
        IO.puts("Skipped category #{category.name} (already there)")
      else
        %Category{}
        |> Category.changeset(category)
        |> Repo.insert!()

        IO.puts("Added category #{category.name}")
      end
    end

    :ok
  end

  @doc """
  Adds each artist entry whose nickname isn't in the database yet (see
  the moduledoc). Returns `:ok`, or `{:error, nicknames}` listing the
  artists that weren't added.
  """
  def add_artists(entries) do
    category_ids =
      Repo.all(Category)
      |> Map.new(fn category -> {category.name, category.id} end)

    not_added =
      for entry <- entries, add_artist(entry, category_ids) == :not_added do
        entry.artist.nickname
      end

    if not_added == [] do
      :ok
    else
      IO.puts(
        "\nNOT ADDED (see the reasons above; running it again retries them): " <>
          Enum.join(not_added, ", ")
      )

      {:error, not_added}
    end
  end

  # Returns :added, :skipped or :not_added.
  defp add_artist(entry, category_ids) do
    nickname = entry.artist.nickname

    if Repo.exists?(from(a in Artist, where: a.nickname == ^nickname)) do
      IO.puts("Skipped #{nickname} (already there)")
      :skipped
    else
      IO.puts("Adding #{nickname} (#{photo_count_text(entry)})...")

      case owner(entry) do
        {:ok, user} ->
          add_artist_for(user, entry, category_ids)

        {:error, reason} ->
          IO.puts("  Not added: #{reason}")
          :not_added
      end
    end
  end

  defp photo_count_text(entry) do
    case length(photos_of(entry)) do
      1 -> "1 photo"
      count -> "#{count} photos"
    end
  end

  defp add_artist_for(user, entry, category_ids) do
    {artist, works} = insert_drafts(user, entry, category_ids)
    # Works are published as the artist would publish them, through
    # their own scope (Products checks who is acting).
    scope = Scope.for_user(user)

    case add_photos_and_go_public(scope, artist, works, entry) do
      :ok ->
        IO.puts("  Added")
        :added

      {:error, reason} ->
        # Takes away whatever was added of them, photo files included.
        {:ok, _} = Artists.hard_delete_artist(artist)
        IO.puts("  Not added: #{reason}. What was added of them has been removed again.")
        :not_added
    end
  end

  # The artist, their collections and works, all as drafts (not public
  # yet), in one short transaction. Returns {artist, [{product, work}]}.
  defp insert_drafts(user, entry, category_ids) do
    {:ok, result} =
      Repo.transact(fn ->
        # The owner and onboarding state are set on the struct: the
        # changeset doesn't take them from a map (audit S-2).
        artist =
          %Artist{user_id: user.id, onboarding_complete: true}
          |> Artist.activation_changeset(entry.artist)
          |> Repo.insert!()

        collections = Enum.with_index(with_uncategorized(entry.collections), 1)

        works_per_collection =
          for {collection, position} <- collections do
            saved_collection = insert_collection(collection, position, artist)

            for {work, work_position} <- Enum.with_index(collection.works, 1) do
              product =
                insert_draft_work(work, work_position, artist, saved_collection, category_ids)

              {product, work}
            end
          end

        {:ok, {artist, List.flatten(works_per_collection)}}
      end)

    result
  end

  defp with_uncategorized([%{name: "Uncategorized"} | _] = collections), do: collections
  defp with_uncategorized(collections), do: [%{name: "Uncategorized", works: []} | collections]

  # The first collection is the artist's default one (with_uncategorized/1
  # puts "Uncategorized" first). The owner, position and is_default go on
  # the struct: the changeset takes only the name.
  defp insert_collection(collection, position, artist) do
    %ProductCollection{artist_id: artist.id, position: position, is_default: position == 1}
    |> ProductCollection.changeset(%{name: collection.name})
    |> Repo.insert!()
  end

  defp insert_draft_work(work, position, artist, collection, category_ids) do
    attrs =
      work
      |> Map.drop([:photos, :category])
      |> Map.merge(%{
        collection_id: collection.id,
        category_id: category_id!(category_ids, work.category)
      })

    # The owner and position go on the struct: Product.changeset/2
    # takes neither.
    %Product{artist_id: artist.id, position: position}
    |> Product.changeset(attrs)
    |> Repo.insert!()
  end

  defp category_id!(category_ids, name) do
    case Map.fetch(category_ids, name) do
      {:ok, id} -> id
      :error -> raise "Category #{name} is missing. Add the categories first."
    end
  end

  # Returns :ok or {:error, reason}. The `rescue` catches anything
  # unexpected, so the caller can still remove the half-added artist.
  defp add_photos_and_go_public(scope, artist, works, entry) do
    with :ok <- add_artist_photos(artist, entry),
         :ok <- add_work_photos(works, entry.photo_dir),
         :ok <- go_public(scope, artist, works, entry) do
      :ok
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp add_artist_photos(artist, entry) do
    each_photo(entry.photos, entry.photo_dir, "artists/#{artist.id}", fn key, position ->
      %ArtistImage{}
      |> ArtistImage.changeset(%{path: key, position: position, artist_id: artist.id})
      |> Repo.insert!()
    end)
  end

  defp add_work_photos(works, photo_dir) do
    each_until_error(works, fn {product, work} ->
      each_photo(work.photos, photo_dir, "products/#{product.id}", fn key, position ->
        # The work goes on the struct: the changeset doesn't take it.
        %ProductImage{product_id: product.id}
        |> ProductImage.changeset(%{path: key, position: position})
        |> Repo.insert!()
      end)
    end)
  end

  # Processes and stores each photo file from priv/static/<photo_dir>/
  # under `folder` (e.g. "products/12"), then calls `save_row` with its
  # key and position. Stops at the first photo that fails.
  defp each_photo(photos, photo_dir, folder, save_row) do
    each_until_error(Enum.with_index(photos, 1), fn {photo, position} ->
      relative_path = Path.join(photo_dir, photo)

      case Images.process_upload(photo_file(photo_dir, photo), photo, folder) do
        {:ok, key} ->
          save_row.(key, position)
          :ok

        {:error, message} ->
          {:error, "the photo #{relative_path} could not be added (#{message})"}
      end
    end)
  end

  # Calls `fun` on each item until one returns {:error, reason}.
  # Returns :ok or that error.
  defp each_until_error(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Makes the artist public and puts each work with a photo up for
  # sale, through the site's own functions and their rules.
  defp go_public(scope, artist, works, entry) do
    with :ok <- activate(artist, entry) do
      each_until_error(works, fn {product, work} -> publish(scope, product, work) end)
    end
  end

  # An artist without a profile photo stays a draft, as on the site.
  defp activate(_artist, %{photos: []}), do: :ok

  defp activate(artist, _entry) do
    case Artists.activate_artist(artist) do
      {:ok, _artist} -> :ok
      {:error, reason} -> {:error, "the profile could not be made public (#{inspect(reason)})"}
    end
  end

  # A work without a photo stays a draft, as on the site.
  defp publish(_scope, _product, %{photos: []}), do: :ok

  defp publish(scope, product, work) do
    case Products.publish_product(scope, product) do
      {:ok, _product} -> :ok
      {:error, reason} -> {:error, "#{work.title} could not be published (#{inspect(reason)})"}
    end
  end

  # The user account the artist will belong to: {:ok, user} or
  # {:error, reason}.
  defp owner(%{user: :first_admin} = entry) do
    case first_admin() do
      nil ->
        IO.puts("  There is no admin account, so it gets its own login")
        find_or_create_user(entry.fallback_user)

      admin_user ->
        if has_artist?(admin_user) do
          IO.puts(
            "  The admin account already has an artist profile, so it gets " <>
              "its own login: #{entry.fallback_user.email}"
          )

          find_or_create_user(entry.fallback_user)
        else
          IO.puts("  Linked to the admin account #{admin_user.username}")
          {:ok, admin_user}
        end
    end
  end

  defp owner(entry), do: find_or_create_user(entry.user)

  # The user of the first admin (the oldest Admin row), or nil.
  defp first_admin do
    Repo.one(
      from(u in User,
        join: admin in Admin,
        on: admin.user_id == u.id,
        order_by: admin.id,
        limit: 1
      )
    )
  end

  defp has_artist?(user) do
    Repo.exists?(from(a in Artist, where: a.user_id == ^user.id))
  end

  defp find_or_create_user(%{email: email, username: username}) do
    case Repo.get_by(User, email: email) do
      nil ->
        if Repo.exists?(from(u in User, where: u.username == ^username)) do
          {:error, "another account already has the username #{username}"}
        else
          {:ok, insert_user(email, username)}
        end

      existing_user ->
        if has_artist?(existing_user) do
          {:error, "the account #{email} already has an artist profile"}
        else
          {:ok, existing_user}
        end
    end
  end

  defp insert_user(email, username) do
    %User{}
    |> User.registration_changeset(%{email: email, username: username})
    |> User.password_changeset(%{password: @password})
    |> User.confirm_changeset()
    |> Repo.insert!()
  end

  # ------------------------------------------------------------------
  # Removing
  # ------------------------------------------------------------------

  @doc """
  Takes the sample data away again, before a site is shown to anyone
  else:

    * every artist profile of a sample account is hard-deleted, with
      their works, photos (also their files in storage), orders,
      conversations and reviews. The developer's studio too, if it is
      linked to an admin account (the admin account itself stays);
    * every sample account is locked: its password is replaced by a
      random one nobody knows, it is logged out everywhere, and its
      status is set to `:removed`. (Locked rather than deleted: an
      account with orders or reviews can't be deleted yet.)

  The categories stay. Running it twice is safe. Returns `:ok`.
  """
  def remove_all do
    entries = all_artist_entries()
    emails = sample_emails(entries)

    sample_users = Repo.all(from(u in User, where: u.email in ^emails))

    for user <- sample_users do
      case Repo.get_by(Artist, user_id: user.id) do
        nil -> :ok
        artist -> hard_delete(artist)
      end
    end

    for artist <- admin_owned_artists(admin_nicknames(entries)) do
      hard_delete(artist)
    end

    for user <- sample_users, user.status != :removed do
      lock_user(user)
    end

    IO.puts("Sample data removed. The categories stay.")
    :ok
  end

  defp admin_owned_artists(nicknames) do
    Repo.all(
      from(a in Artist,
        join: admin in Admin,
        on: admin.user_id == a.user_id,
        where: a.nickname in ^nicknames
      )
    )
  end

  defp hard_delete(artist) do
    {:ok, _} = Artists.hard_delete_artist(artist)
    IO.puts("Deleted #{artist.nickname}")
  end

  defp lock_user(user) do
    random_password = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    {:ok, _user} =
      Repo.transact(fn ->
        # Logs them out everywhere (and voids any emailed login link).
        Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id))

        user
        |> User.password_changeset(%{password: random_password})
        |> User.status_changeset(%{status: :removed})
        |> Repo.update()
      end)

    IO.puts("Locked the account #{user.email}")
  end

  @doc """
  What is left of the sample data: a list of plain sentences, empty
  when there is nothing. Counts sample accounts that aren't locked
  (status other than `:removed`) and the developer's studio if it is
  still there. Used by `ArtsyNeighbor.Release.check_before_launch/0`.
  """
  def leftovers do
    entries = all_artist_entries()
    emails = sample_emails(entries)
    nicknames = admin_nicknames(entries)

    unlocked_users =
      Repo.all(
        from(u in User,
          where: u.email in ^emails and u.status != :removed,
          order_by: u.email,
          select: u.email
        )
      )

    studios =
      Repo.all(from(a in Artist, where: a.nickname in ^nicknames, select: a.nickname))

    for(email <- unlocked_users, do: "sample account not locked: #{email}") ++
      for(nickname <- studios, do: "sample artist still there: #{nickname}")
  end
end
