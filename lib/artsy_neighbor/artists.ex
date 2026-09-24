defmodule ArtsyNeighbor.Artists do
  @moduledoc """
  The Artists context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo
  alias Ecto.Multi

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.HardDelete
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists.ArtistImage
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Reviews.VendorReview
  alias ArtsyNeighbor.Reviews.BuyerReview
  alias ArtsyNeighbor.Reviews.ProductReview

  @doc "The name of the default collection created for every new artist."
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
  Creates a new artist and atomically inserts a default "Uncategorized" collection.
  Returns {:ok, artist} or {:error, changeset}.

  Two calling conventions:
  - create_artist(attrs) — builds the changeset using activation_changeset (full validation).
    Used by the admin form and seeds.
  - create_artist(changeset) — accepts a pre-built changeset, e.g. from registration_changeset
    (step 1 only validation). Used by save_onboarding_progress/2.

  In both cases the Multi transaction is identical: artist insert + collection insert.
  """
  def create_artist(%Ecto.Changeset{} = changeset) do
    Multi.new()
    |> Multi.insert(:artist, changeset)
    |> Multi.insert(:collection, fn %{artist: artist} ->
      ProductCollection.changeset(%ProductCollection{}, %{
        name: default_collection_name(),
        position: 1,
        artist_id: artist.id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{artist: artist}} -> {:ok, artist}
      {:error, :artist, changeset, _} -> {:error, changeset}
      {:error, :collection, _changeset, _} -> {:error, :collection_creation_failed}
    end
  end

  def create_artist(attrs) when is_map(attrs) do
    create_artist(Artist.activation_changeset(%Artist{}, attrs))
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
  Updates an existing artist with the given attributes.

  If this update includes a status transition from :active to :inactive —
  from any caller, not just deactivate_artist/1's own dedicated vendor
  self-service path — also cascades the artist's currently-:available
  products to :unavailable, the same way deactivate_artist/1 does. This
  matters because :status is just one field among many on this general
  update (e.g. the admin edit form's status dropdown, or a future one),
  and without it, an admin changing an artist to :inactive here wouldn't
  hide their products the way the vendor's own dashboard toggle does —
  same class of gap only_available/1's own artist-status check exists to
  catch at the query layer, but the cascade keeps product rows themselves
  consistent too, not just query results.

  Unlike deactivate_artist/1, this does NOT refuse the update when the
  artist isn't already :active — a general profile edit (bio, address,
  etc., possibly bundled with an unrelated status change) shouldn't fail
  outright over that; it just means no cascade applies for other
  transitions (:removed -> :inactive, e.g., already has no :available
  products left to cascade, since soft_delete_artist/1 already archived
  them all).
  """
  def update_artist(%Ecto.Changeset{} = changeset) do
    do_update_artist(changeset)
  end

  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    do_update_artist(change_artist(artist, attrs))
  end

  # changeset.data is always the pre-change struct — true whether the
  # changeset arrived pre-built (update_artist/1) or was just built here
  # from an %Artist{} + attrs (update_artist/2) — so there's no need for a
  # separate "original status" argument computed differently per call site.
  defp do_update_artist(changeset) do
    original_status = changeset.data.status

    if original_status == :active and Ecto.Changeset.get_change(changeset, :status) == :inactive do
      Repo.transaction(fn ->
        case Repo.update(changeset) do
          {:ok, updated} ->
            cascade_available_products_to_unavailable(updated.id)
            updated

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    else
      Repo.update(changeset)
    end
  end

  # Shared by deactivate_artist/1 and update_artist/2's own transition
  # detection above, so "an artist leaving :active hides their available
  # products" holds the same way regardless of which function performed
  # the transition. A thin, readably-named wrapper around
  # cascade_products_status/3 below, which also backs soft_delete_artist/1
  # — one implementation of "bulk-update an artist's products' status" for
  # every entry point, not two independently-maintained copies of the same
  # Repo.update_all.
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
  Vendor self-service: deactivates an artist's own profile (:active ->
  :inactive) and cascades their currently-:available products to
  :unavailable. This same cascade also happens automatically from the
  general update_artist/2 for any :active -> :inactive transition (e.g.
  the admin edit form's own status dropdown) — see that function's own
  doc comment — so the invariant holds regardless of entry point, not
  just this vendor-facing one. Also independently backed by
  only_available/1's own artist-status check at the query layer — cascade
  and query-layer check are defense in depth for the same problem, not a
  substitute for one another.

  Only touches :available products, not :archived ones — a product the
  vendor already archived themselves stays archived; this is a pause, not
  a removal, so it shouldn't disturb a deliberate per-product choice.
  Compare soft_delete_artist/1, which unconditionally forces every product
  to :archived regardless of prior status, because it's a full removal.

  Refuses (returns {:error, :not_active}) unless the artist is currently
  :active — deactivating only means something as a transition away from
  active; calling this on an already-:inactive or :removed artist would be
  meaningless at best, or (for :removed) actively wrong, since it would
  silently move a removed artist to :inactive as a side effect. Unlike
  this function, update_artist/2's version of the same cascade does NOT
  refuse the whole update on this same precondition — see its own doc
  comment for why.

  Does not cascade back on reactivation — re-activating (:inactive ->
  :active, via the same dashboard toggle, calling update_artist/2 directly
  since no cascade is needed for that direction) does not automatically
  restore any product's status. A vendor's products stay :unavailable
  until they're brought back individually; that "mark available" action
  doesn't exist yet (see restore_product/1's own doc comment).
  """
  def deactivate_artist(%Artist{status: :active} = artist) do
    Repo.transaction(fn ->
      cascade_available_products_to_unavailable(artist.id)

      case artist |> Artist.status_changeset(%{status: :inactive}) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
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
  User (Accounts has no delete_user/1), so this can't be hit today — it's
  a defensive guard for when that changes, not a live check. This is
  deliberately a minimal existence check, not an active/inactive check:
  User has no status field yet (that's Phase 7 of
  docs/plans/2026-09-17-entity-removal-consistency.md, deferred on
  purpose — User touches auth and has several FK/polymorphic landmines
  that each need their own decision). Once Phase 7 adds User status, this
  guard should be extended to also require the user be active — and
  whatever separate procedure reactivates a user should run before this
  function is called, not inside it, the same way a vendor has to
  reactivate their own profile separately after this function restores
  them to :inactive.
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
      artist_flag_subjects(repo, locked_artist)
    end)
  end

  # Every flaggable thing that disappears when this artist is deleted: the
  # artist themselves, their products, and all three kinds of review tied to
  # their orders/products. Computed before the delete (HardDelete runs this
  # first), since once the DB cascades run these ids can't be looked up.
  defp artist_flag_subjects(repo, artist) do
    order_ids =
      repo.all(from(o in Order, where: o.artist_id == ^artist.id, select: o.id))

    product_ids =
      repo.all(from(p in Product, where: p.artist_id == ^artist.id, select: p.id))

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
  """
  def delete_artist_image(%ArtistImage{} = artist_image) do
    Repo.delete(artist_image)
  end
end
