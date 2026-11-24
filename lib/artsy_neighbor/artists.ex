defmodule ArtsyNeighbor.Artists do
  @moduledoc """
  The Artists context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo
  alias Ecto.Multi

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.HardDelete
  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists.ArtistImage
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Products.ProductImage
  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Reviews.VendorReview
  alias ArtsyNeighbor.Reviews.BuyerReview
  alias ArtsyNeighbor.Reviews.ProductReview

  @doc """
  The name a new artist's default collection starts with. The artist may
  rename it: code recognises the default collection by its `is_default`
  field, never by this name.
  """
  def default_collection_name, do: "Uncategorized"

  @doc """
  Returns the list of all artists. Associations not preloaded by default.
   Artists are ordered by their main medium (first element in the medium array) and then by

  ## Examples

      iex> list_artists()
      [%Artist{}, ...]

  """
  def list_artists do
    Artist
    |> with_status(:active)
    |> order_by([a], fragment("?[1]", a.medium))
    |> order_by(asc: :area_code)
    |> Repo.all()
  end

  @doc """
  Returns active artists with their associated images preloaded,
  ordered by main medium then area code.
  """
  def list_artists_with_images do
    Artist
    |> with_status(:active)
    |> order_by([a], fragment("?[1]", a.medium))
    |> order_by(asc: :area_code)
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  # How many reviews an artist needs before their average counts for
  # "Popular artists" on the home page: one 5-star review shouldn't put
  # an artist ahead of one with twenty 4.8s.
  @popular_min_reviews 3

  @doc """
  Returns up to `count` artists for the home page's "Popular artists",
  each as `%{artist: artist, rating: rating, works: works}`:

    * `artist` — with their photos loaded, first photo first
    * `rating` — `%{count: 6, average: 4.2}`, from
      `Reviews.vendor_review_summary/1` (average nil with no reviews)
    * `works` — their featured works (up to 4), in order, with photos:
      the same works as "Featured works" on their page

  First the best-rated artists with at least #{@popular_min_reviews}
  reviews (best average first; more reviews first when two are equal).
  Any places left go to the artists who added a work most recently.
  Only active artists with at least one work for sale, since the card
  is made of their works' pictures.
  """
  def list_popular_artists(count) do
    best_rated = best_rated_artists(count)
    best_rated_ids = Enum.map(best_rated, fn artist -> artist.id end)
    newest = artists_with_newest_works(count - length(best_rated), best_rated_ids)

    for artist <- best_rated ++ newest do
      %{
        artist: Repo.preload(artist, artist_images: artist_images_by_position()),
        rating: ArtsyNeighbor.Reviews.vendor_review_summary(artist.id),
        # The same function as the Works tab's "Featured works", so the
        # card follows the artist's choice once they can make one
        # (NOTES.md #23).
        works: ArtsyNeighbor.Products.list_newest_artist_products(artist.id, 4)
      }
    end
  end

  defp best_rated_artists(count) do
    from(a in Artist,
      join: selling in subquery(ArtsyNeighbor.Products.artists_with_works_for_sale_query()),
      on: selling.artist_id == a.id,
      join: rating in subquery(ArtsyNeighbor.Reviews.vendor_review_summaries_query()),
      on: rating.artist_id == a.id,
      where: a.status == :active,
      where: rating.count >= @popular_min_reviews,
      order_by: [desc: rating.average, desc: rating.count, asc: a.id],
      limit: ^count
    )
    |> Repo.all()
  end

  # The artists who added a work for sale most recently, leaving out
  # `left_out_ids` (the ones already chosen).
  defp artists_with_newest_works(count, _left_out_ids) when count <= 0, do: []

  defp artists_with_newest_works(count, left_out_ids) do
    from(a in Artist,
      join: selling in subquery(ArtsyNeighbor.Products.artists_with_works_for_sale_query()),
      on: selling.artist_id == a.id,
      where: a.status == :active,
      where: a.id not in ^left_out_ids,
      order_by: [desc: selling.newest_work_at, asc: a.id],
      limit: ^count
    )
    |> Repo.all()
  end

  defp artist_images_by_position, do: from(i in ArtistImage, order_by: [asc: i.position])

  @doc """
  Returns all artists regardless of status, for admin use.
  Sorted active → inactive → removed, then by nickname within each group.
  """
  def list_artists_all_status do
    Artist
    |> order_by(
      [a],
      fragment(
        "CASE WHEN ? = 'active' THEN 0 WHEN ? = 'inactive' THEN 1 ELSE 2 END",
        a.status,
        a.status
      )
    )
    |> order_by([a], asc: a.nickname)
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  @doc """
  Returns the list of artists filtered by the given status.
  If status is nil, returns all artists.
  """
  def with_status(query, nil), do: query
  def with_status(query, status), do: where(query, [a], a.status == ^status)

  @doc """
  Filters artists by the given area code.
  """
  def filter_artists_by_area(area_code) do
    Artist
    |> where([a], a.area_code == ^area_code)
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  @doc """
  Filters artists by the given medium.
  """
  def filter_artists_by_medium(medium) do
    search_term = "%#{medium}%"

    Artist
    |> where(
      [a],
      fragment("EXISTS (SELECT 1 FROM unnest(?) AS m WHERE m ILIKE ?)", a.medium, ^search_term)
    )
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  @doc """
  Filters artists based on provided parameters.
  It shows only active artists by default, but can be extended to include other statuses if needed.

  Suported parameters:
    - "q_name": filters by artist nickname
    - "q_medium": filters by medium
  ## Examples

      iex> filter_artists(%{"q_name" => "Elena", "q_medium" => "Oil"})
      [%Artist{}, ...]
  """
  def filter_artists(filter_params) do
    q_name = String.trim(filter_params["q_name"] || "")
    q_medium = String.trim(filter_params["q_medium"] || "")
    sort_term = String.trim(filter_params["sort_by"] || "")

    Artist
    |> with_status(:active)
    |> with_nickname(q_name)
    |> with_medium(q_medium)
    |> sort_by(sort_term)
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  @doc """
  Filters artists by medium if provided.
  """
  def with_medium(query, q_medium)
      when is_binary(q_medium) and q_medium != "" do
    search_term = "%#{q_medium}%"

    query
    |> where(
      [a],
      fragment("EXISTS (SELECT 1 FROM unnest(?) AS m WHERE m ILIKE ?)", a.medium, ^search_term)
    )
  end

  def with_medium(query, _), do: query

  @doc """
  Filters artists by nickname if provided.
  """
  def with_nickname(query, nickname)
      when is_binary(nickname) and nickname != "" do
    search_term = "%#{nickname}%"

    query
    |> where([a], ilike(a.nickname, ^search_term))
  end

  def with_nickname(query, _), do: query

  def sort_by(query, "area_code") do
    query
    |> order_by(asc: :area_code)
  end

  def sort_by(query, "nickname") do
    query
    |> order_by(asc: :nickname)
  end

  def sort_by(query, "main_medium") do
    query
    |> order_by([a], fragment("?[1]", a.medium))
  end

  def sort_by(query, _), do: query

  @doc """
  Gets a single artist by ID.

  ## Examples

      iex> get_artist(123)
      %Artist{}

      iex> get_artist(456)
      nil

  """
  def get_artist(id) do
    Repo.get(Artist, id)
    |> Repo.preload([:artist_images])
  end

  @doc """
  Gets a single artist by artist ID, bang version.
  Throws `Ecto.NoResultsError` if the Artist does not exist.
  """
  def get_artist!(id) do
    Repo.get!(Artist, id)
    |> Repo.preload([:artist_images])
  end

  @doc """
  Gets a single artist by user ID.
  Returns nil if the Artist does not exist.
  Needed for associating artists with user accounts.
  """
  def get_artist_by_user_id(user_id) do
    Repo.get_by(Artist, user_id: user_id)
  end

  @doc """
  Creates a new artist and atomically inserts their default collection
  (`is_default`, named "Uncategorized" to start with).
  Returns {:ok, artist} or {:error, changeset}. The new artist is always
  :inactive (the changesets don't take a status); see change_status/2.

  Takes a changeset, never a map of params: the owner (`user_id`) is
  whatever the changeset says, so the caller must have chosen it. The
  vendor's onboarding (save_onboarding_progress/2) builds it with
  registration_changeset on `%Artist{user_id: ...}`, the owner set by
  the server. To create a profile with an owner picked from a form
  (the admin form, test fixtures), use `AdminArtists.create_artist/1`,
  whose name says it's for admins (audit S-2).

  A user who already has a profile gets `{:error, changeset}` with an
  error on `:user_id` (one profile per user).
  """
  def create_artist(%Ecto.Changeset{} = changeset) do
    Multi.new()
    |> Multi.insert(:artist, changeset)
    |> Multi.insert(:collection, fn %{artist: artist} ->
      %ProductCollection{artist_id: artist.id, position: 1, is_default: true}
      |> ProductCollection.changeset(%{name: default_collection_name()})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{artist: artist}} -> {:ok, artist}
      {:error, :artist, changeset, _} -> {:error, changeset}
      {:error, :collection, _changeset, _} -> {:error, :collection_creation_failed}
    end
  end

  @doc """
  A helper function to get a changeset for an artist.
  Does not make any changes to DB.
  """
  def change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.activation_changeset(artist, attrs)
  end

  @doc """
  Returns a registration changeset for an artist — validates only step 1 fields.
  Used during onboarding before the full profile is complete.
  """
  def registration_change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.registration_changeset(artist, attrs)
  end

  @doc """
  Saves partial artist profile progress during onboarding.
  Stamps onboarding_step onto the changeset, then:
  - If the artist is new (no id): inserts artist + default collection atomically.
  - If the artist already exists: updates in place.
  Returns {:ok, artist} or {:error, changeset}.
  """
  def save_onboarding_progress(%Ecto.Changeset{} = changeset, step) do
    changeset = Ecto.Changeset.put_change(changeset, :onboarding_step, step)

    case changeset.data.id do
      nil -> create_artist(changeset)
      _id -> Repo.update(changeset)
    end
  end

  @doc """
  Updates an artist's profile fields.

  Never changes the status: the profile changeset
  (`Artist.activation_changeset/2`) doesn't take one, so a status sent
  along with a form is ignored. Status changes go through
  `change_status/2` and the functions it uses.
  """
  def update_artist(%Ecto.Changeset{} = changeset) do
    Repo.update(changeset)
  end

  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    artist
    |> change_artist(attrs)
    |> Repo.update()
  end

  # --- Status changes -------------------------------------------------
  #
  # Every status change goes through one of the functions below, each
  # applying its own rules:
  #   * activate_artist/1    — :inactive -> :active; needs a profile photo
  #                            (and refuses :removed -> :active);
  #   * deactivate_artist/1  — :active -> :inactive; hides their
  #                            :available products (-> :unavailable);
  #   * soft_delete_artist/1 — -> :removed; archives all their products;
  #   * restore_artist/1     — :removed -> :inactive.
  # change_status/2 picks the right one, for a form that offers a status
  # choice (the admin artist form).

  @doc """
  Moves an artist to `new_status` (an atom, or its string form from a
  form, e.g. `"active"`) through the function for that change — see
  "Status changes" above. Returns `{:ok, artist}` (also when the status
  is already `new_status`), or the error of the function used:
  `{:error, changeset}` (e.g. no profile photo), `{:error, :not_active}`,
  `{:error, :already_active}`, `{:error, :user_missing}`, or
  `{:error, :invalid_status}` for a status that doesn't exist.
  """
  def change_status(%Artist{} = artist, new_status) when is_binary(new_status) do
    # Ecto.Enum.mappings/2 lists the schema's own statuses, e.g.
    # [active: "active", ...], so only a real status is turned into an atom.
    mappings = Ecto.Enum.mappings(Artist, :status)

    case Enum.find(mappings, fn {_atom, string} -> string == new_status end) do
      {status_atom, _string} -> change_status(artist, status_atom)
      nil -> {:error, :invalid_status}
    end
  end

  def change_status(%Artist{status: status} = artist, status), do: {:ok, artist}

  def change_status(%Artist{} = artist, :active), do: activate_artist(artist)

  def change_status(%Artist{status: :active} = artist, :inactive),
    do: deactivate_artist(artist)

  def change_status(%Artist{status: :removed} = artist, :inactive),
    do: restore_artist(artist)

  def change_status(%Artist{} = artist, :removed), do: soft_delete_artist(artist)

  def change_status(%Artist{}, _other), do: {:error, :invalid_status}

  @doc """
  Makes an artist's profile public (:active).

  Refuses, with a changeset whose `:status` error says why, when the
  profile has no photo (`needs_profile_photo_message/0`) or is :removed
  (restore_artist/1 first). Doesn't bring back products hidden when
  the profile was deactivated: each is published again on its own
  (Products.publish_product/1).
  """
  def activate_artist(%Artist{} = artist) do
    Repo.transact(fn ->
      # Re-read under the lock: the struct we were given may be stale,
      # and a photo can't be removed while we check (see
      # delete_artist_image/1, which takes the same lock).
      locked = lock_artist(artist.id)

      result =
        locked
        |> Artist.status_changeset(%{status: :active})
        |> refuse_active_without_photos(count_profile_photos(locked.id))
        |> Repo.update()

      # With its photos loaded, as soft_delete_artist/1 and
      # restore_artist/1 return it: the pages showing it need them.
      case result do
        {:ok, updated} -> {:ok, Repo.preload(updated, [:artist_images])}
        error -> error
      end
    end)
  end

  # --- Activation and profile photos ----------------------------------
  #
  # The rule: an artist profile can only be :active (public) while it has
  # at least one profile photo. activate_artist/1 checks it, and
  # delete_artist_image/1 refuses to remove the last photo of an :active
  # profile. New profiles always start as :inactive (the profile
  # changeset doesn't take a status).

  @msg_needs_profile_photo "Add a profile photo before making your profile public."

  @doc "The message shown when a profile can't go public without a photo."
  def needs_profile_photo_message, do: @msg_needs_profile_photo

  defp refuse_active_without_photos(changeset, photo_count) do
    if photo_count == 0 do
      Ecto.Changeset.add_error(changeset, :status, @msg_needs_profile_photo)
    else
      changeset
    end
  end

  defp count_profile_photos(artist_id) do
    ArtistImage
    |> where([i], i.artist_id == ^artist_id)
    |> Repo.aggregate(:count)
  end

  # Locks the artist's row until the surrounding transaction ends.
  defp lock_artist(artist_id) do
    Artist
    |> where([a], a.id == ^artist_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  # Used by deactivate_artist/1: "an artist leaving :active hides their
  # available products". A thin, readably-named wrapper around
  # cascade_products_status/3 below, which also backs soft_delete_artist/1
  # — one implementation of "bulk-update an artist's products' status",
  # not two independently-maintained copies of the same Repo.update_all.
  defp cascade_available_products_to_unavailable(artist_id) do
    cascade_products_status(artist_id, :available, :unavailable)
  end

  # Bulk-updates an artist's products to `to_status`. `from_status` is nil
  # to touch every one of the artist's products unconditionally (used by
  # soft_delete_artist/1 — a full removal, where even an already-:archived
  # product should end up in the same bucket), or a specific atom to scope
  # it to only products currently at that status (used by the lighter
  # :active -> :inactive pause cascade above, which must leave
  # already-:archived products alone).
  defp cascade_products_status(artist_id, from_status, to_status) do
    query =
      case from_status do
        nil -> from(p in Product, where: p.artist_id == ^artist_id)
        status -> from(p in Product, where: p.artist_id == ^artist_id and p.status == ^status)
      end

    Repo.update_all(
      query,
      set: [
        status: to_string(to_status),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  @doc """
  Updates the vendor's default pickup address/instructions (used to prefill
  the Schedule Pick-up form). See Artist.pickup_defaults_changeset/2.
  """
  def update_pickup_defaults(%Artist{} = artist, attrs) do
    artist
    |> Artist.pickup_defaults_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks an artist as :removed and sets ALL of their products to :archived
  (unconditionally — even ones the vendor had already archived themselves
  individually; a soft-deleted artist's whole catalog goes into the same
  bucket, regardless of prior per-product status). Under normal
  circumstances Artists are never hard-deleted — they are permanent
  records. For exceptions (admin/testing cleanup) see hard_delete_artist/1
  below, which is irreversible and cascades to all dependent records.

  Compare deactivate_artist/1: a lighter, self-service, reversible-in-spirit
  pause (:active -> :inactive) that only touches currently-:available
  products and leaves already-:archived ones alone — this function is the
  heavier, admin-initiated removal.
  """
  def soft_delete_artist(%Artist{} = artist) do
    Repo.transaction(fn ->
      cascade_products_status(artist.id, nil, :archived)

      case artist |> Artist.status_changeset(%{status: :removed}) |> Repo.update() do
        {:ok, updated} -> Repo.preload(updated, [:artist_images])
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deactivates an artist's profile (:active -> :inactive) and cascades
  their currently-:available products to :unavailable. Used by the
  vendor dashboard's "De-activate profile" and, through change_status/2,
  by the admin form's status dropdown, so the cascade holds whichever
  way the profile is hidden. Also independently backed by
  only_available/1's own artist-status check at the query layer —
  cascade and query-layer check are defense in depth for the same
  problem, not a substitute for one another.

  Only touches :available products, not :archived ones — a product the
  vendor already archived themselves stays archived; this is a pause, not
  a removal, so it shouldn't disturb a deliberate per-product choice.
  Compare soft_delete_artist/1, which unconditionally forces every product
  to :archived regardless of prior status, because it's a full removal.

  Refuses (returns {:error, :not_active}) unless the artist is currently
  :active — deactivating only means something as a transition away from
  active; calling this on an already-:inactive or :removed artist would be
  meaningless at best, or (for :removed) actively wrong, since it would
  silently move a removed artist to :inactive as a side effect.

  Does not cascade back on reactivation (activate_artist/1): a vendor's
  products stay :unavailable until each is published again
  (Products.publish_product/1; no button for it yet, NOTES #16).
  """
  def deactivate_artist(%Artist{status: :active} = artist) do
    Repo.transact(fn ->
      cascade_available_products_to_unavailable(artist.id)

      artist
      |> Artist.status_changeset(%{status: :inactive})
      |> Repo.update()
    end)
  end

  def deactivate_artist(%Artist{}), do: {:error, :not_active}

  @doc """
  Reverses soft_delete_artist/1, setting status back to :inactive — not
  :active, since restoring a removed profile shouldn't silently re-publish
  it. The vendor still has to actively re-activate from their dashboard.
  Does not touch the artist's products, which stay :archived (set by
  soft_delete_artist/1) until brought back individually via
  Products.restore_product/1 — itself gated on the artist being :active,
  so this alone isn't enough to make any of them visible again either.

  Refuses (returns {:error, :already_active}) if the artist is currently
  :active — restoring is meant to bring a removed/inactive profile back
  into view, not silently demote a live one. Without this guard, a stale
  page or double-click on an already-active artist would flip them to
  :inactive and hide them.

  Also refuses (returns {:error, :user_missing}) if the artist's linked
  User account no longer exists. Nothing in the app can currently delete a
  User, so this is a defensive guard, not a live check. It checks only
  that the user exists, not the user's status — User status isn't
  enforced anywhere yet. When it is, this guard should also require an
  :active user; reactivating the user should be a separate step that
  runs before this function, not inside it.
  """
  def restore_artist(%Artist{status: :active}), do: {:error, :already_active}

  def restore_artist(%Artist{} = artist) do
    case Accounts.get_user(artist.user_id) do
      nil ->
        {:error, :user_missing}

      _user ->
        case artist |> Artist.status_changeset(%{status: :inactive}) |> Repo.update() do
          # Preloaded for the same reason soft_delete_artist/1 preloads it:
          # the admin index's stream_insert renders artist.artist_images
          # directly.
          {:ok, updated} -> {:ok, Repo.preload(updated, [:artist_images])}
          error -> error
        end
    end
  end

  @doc """
  Permanently deletes an artist and everything that depends on them. Orders,
  order items, conversations, conversation events, products (and their
  images/options), product collections, artist images, and all three review
  types cascade at the DB level (see the
  `cascade_artist_delete_fks` migration). The one exception is `Flag` —
  `subject_id` is a polymorphic reference (it can point at an artist, a
  product, or any of three review tables depending on `subject_type`), so
  Postgres can't enforce a real FK on it and this function still cleans
  flags up by hand, via `ArtsyNeighbor.HardDelete` (which also row-locks the
  artist so no new order/review/conversation can be inserted against them
  mid-delete).

  Intended for admin/testing cleanup — for a normal "take this vendor down"
  action use soft_delete_artist/1 instead, which is reversible.

  For routine removal of artists, use soft_delete_artist/1 instead. The current function is for admin/testing cleanup and is irreversible. soft_delete_artist/1 only flag an artist as removed.
  """
  def hard_delete_artist(%Artist{} = artist) do
    HardDelete.delete_with_flags(artist, fn repo, locked_artist ->
      # Locked like the artist row: a photo being added to one of their
      # products right now references the product, not the artist, so
      # only a lock on the product makes it wait. Without this, such a
      # photo could slip in unseen, cascade away with the artist, and
      # leave its files behind. (A new product can't slip in: it
      # references the artist, whose row is already locked.)
      product_ids =
        repo.all(
          from(p in Product,
            where: p.artist_id == ^locked_artist.id,
            select: p.id,
            lock: "FOR UPDATE"
          )
        )

      %{
        flag_subjects: artist_flag_subjects(repo, locked_artist, product_ids),
        photo_paths: artist_photo_paths(repo, locked_artist, product_ids)
      }
    end)
  end

  # Their profile photos and all their products' photos: the rows
  # cascade away with the artist, and HardDelete deletes the files after
  # the commit.
  defp artist_photo_paths(repo, artist, product_ids) do
    profile_photo_paths =
      repo.all(from(i in ArtistImage, where: i.artist_id == ^artist.id, select: i.path))

    product_photo_paths =
      repo.all(from(i in ProductImage, where: i.product_id in ^product_ids, select: i.path))

    profile_photo_paths ++ product_photo_paths
  end

  # Every flaggable thing that disappears when this artist is deleted: the
  # artist themselves, their products, and all three kinds of review tied to
  # their orders/products. Computed before the delete (HardDelete runs this
  # first), since once the DB cascades run these ids can't be looked up.
  defp artist_flag_subjects(repo, artist, product_ids) do
    order_ids =
      repo.all(from(o in Order, where: o.artist_id == ^artist.id, select: o.id))

    vendor_review_ids =
      repo.all(from(vr in VendorReview, where: vr.artist_id == ^artist.id, select: vr.id))

    buyer_review_ids =
      repo.all(from(br in BuyerReview, where: br.order_id in ^order_ids, select: br.id))

    product_review_ids =
      repo.all(
        from(pr in ProductReview,
          where: pr.order_id in ^order_ids or pr.product_id in ^product_ids,
          select: pr.id
        )
      )

    %{
      "vendor" => [artist.id],
      "product" => product_ids,
      "vendor_review_of" => vendor_review_ids,
      "buyer_review_of" => buyer_review_ids,
      "product_review_of" => product_review_ids
    }
  end

  @doc """
  Creates a new ArtistImage for the given artist.
  artist_id is injected from the Artist struct — never from form params.
  """
  def create_artist_image(%Artist{} = artist, attrs \\ %{}) do
    %ArtistImage{}
    |> ArtistImage.changeset(Map.put(attrs, :artist_id, artist.id))
    |> Repo.insert()
  end

  @doc """
  Returns all images for the given artist, ordered by position ascending.
  """
  def get_images_for_artist(%Artist{} = artist) do
    ArtistImage
    |> where(artist_id: ^artist.id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  Swaps the position values of two ArtistImage records atomically.
  Used for reordering images up/down in the profile form.
  """
  def swap_image_positions(%ArtistImage{} = img1, %ArtistImage{} = img2) do
    Repo.transaction(fn ->
      {:ok, _} = update_artist_image(img1, %{position: img2.position})
      {:ok, _} = update_artist_image(img2, %{position: img1.position})
    end)
  end

  @doc """
  Updates an ArtistImage with the given attributes.
  """
  def update_artist_image(%ArtistImage{} = artist_image, attrs \\ %{}) do
    artist_image
    |> ArtistImage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an ArtistImage record.

  Refuses with `{:error, :last_photo_of_active_profile}` when it is the
  only photo of an :active (public) profile: a public profile must
  have a photo (see "Activation and profile photos" above). The artist
  uploads another photo first, or hides their profile from the
  dashboard. Hiding it automatically isn't done on purpose: that also
  makes all their products unavailable (deactivate_artist/1).

  Also returns `{:error, :not_found}` if the photo was already removed
  (e.g. in another browser tab).

  Once the row is deleted, the photo's files are deleted from storage
  too, in the background (`Images.delete_files_of_deleted_row/1`):
  new visitors then get "not found" at its address, though a browser
  that already showed it may keep its own copy for a while.
  """
  def delete_artist_image(%ArtistImage{} = artist_image) do
    artist_image
    |> delete_artist_image_row()
    |> Images.delete_files_of_deleted_row()
  end

  defp delete_artist_image_row(artist_image) do
    Repo.transact(fn ->
      # Locked, so the profile can't be activated while its last photo
      # is being removed (activate_artist/1 takes the same lock).
      artist = lock_artist(artist_image.artist_id)

      # Read the photo again under the lock: it may already be gone.
      current_image = Repo.get(ArtistImage, artist_image.id)

      cond do
        current_image == nil ->
          {:error, :not_found}

        artist.status == :active and count_profile_photos(artist.id) <= 1 ->
          {:error, :last_photo_of_active_profile}

        true ->
          Repo.delete(current_image)
      end
    end)
  end
end
