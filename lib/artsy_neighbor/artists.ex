defmodule ArtsyNeighbor.Artists do
  @moduledoc """
  The Artists context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo
  alias Ecto.Multi

  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists.ArtistImage
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Reviews.VendorReview
  alias ArtsyNeighbor.Reviews.BuyerReview
  alias ArtsyNeighbor.Reviews.ProductReview
  alias ArtsyNeighbor.Reviews.Flag

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
  """
  def update_artist(%Ecto.Changeset{} = changeset) do
    Repo.update(changeset)
  end

  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    artist
    |> change_artist(attrs)
    |> Repo.update()
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
  Marks an artist as :removed and sets all their products to :unavailable.
  Under normal circumstances Artists are never hard-deleted — they are permanent records.
  For exceptions (admin/testing cleanup) see hard_delete_artist/1 below, which is irreversible and cascades to all dependent records.
  """
  def soft_delete_artist(%Artist{} = artist) do
    Repo.transaction(fn ->
      Repo.update_all(
        from(p in Product, where: p.artist_id == ^artist.id),
        set: [status: "unavailable", updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      case artist |> Artist.status_changeset(%{status: :removed}) |> Repo.update() do
        {:ok, updated} -> Repo.preload(updated, [:artist_images])
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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
  flags up by hand.

  Intended for admin/testing cleanup — for a normal "take this vendor down"
  action use soft_delete_artist/1 instead, which is reversible.

  For routine removal of artists, use soft_delete_artist/1 instead. The current function is for admin/testing cleanup and is irreversible. soft_delete_artist/1 only flag an artist as removed.
  """
  def hard_delete_artist(%Artist{} = artist) do
    Multi.new()
    |> Multi.run(:locked_artist, fn repo, _changes ->
      # Lock the artist row for the duration of this transaction. Postgres
      # takes a FOR KEY SHARE lock on the referenced row for every
      # FK-checked insert, so holding FOR UPDATE here blocks any concurrent
      # insert of an order/conversation/review against this artist_id until
      # we commit or roll back.
      {:ok, repo.one!(from(a in Artist, where: a.id == ^artist.id, lock: "FOR UPDATE"))}
    end)
    |> Multi.run(:flag_subject_ids, fn repo, %{locked_artist: locked_artist} ->
      # Collected up front, before anything cascades away, so we still know
      # which review ids belonged to this artist once they're gone.
      order_ids =
        repo.all(from(o in Order, where: o.artist_id == ^locked_artist.id, select: o.id))

      product_ids =
        repo.all(from(p in Product, where: p.artist_id == ^locked_artist.id, select: p.id))

      vendor_review_ids =
        repo.all(
          from(vr in VendorReview, where: vr.artist_id == ^locked_artist.id, select: vr.id)
        )

      buyer_review_ids =
        repo.all(from(br in BuyerReview, where: br.order_id in ^order_ids, select: br.id))

      product_review_ids =
        repo.all(
          from(pr in ProductReview,
            where: pr.order_id in ^order_ids or pr.product_id in ^product_ids,
            select: pr.id
          )
        )

      {:ok,
       %{
         vendor: [locked_artist.id],
         product: product_ids,
         vendor_review_of: vendor_review_ids,
         buyer_review_of: buyer_review_ids,
         product_review_of: product_review_ids
       }}
    end)
    |> Multi.run(:deleted_flags, fn repo, %{flag_subject_ids: ids} ->
      {count, _} =
        repo.delete_all(
          from(f in Flag,
            where:
              (f.subject_type == "vendor" and f.subject_id in ^ids.vendor) or
                (f.subject_type == "product" and f.subject_id in ^ids.product) or
                (f.subject_type == "vendor_review_of" and f.subject_id in ^ids.vendor_review_of) or
                (f.subject_type == "buyer_review_of" and f.subject_id in ^ids.buyer_review_of) or
                (f.subject_type == "product_review_of" and f.subject_id in ^ids.product_review_of)
          )
        )

      {:ok, count}
    end)
    |> Multi.run(:deleted_artist, fn repo, %{locked_artist: locked_artist} ->
      repo.delete(locked_artist)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{deleted_artist: deleted}} -> {:ok, deleted}
      {:error, _failed_step, reason, _changes_so_far} -> {:error, reason}
    end
  rescue
    error in [Ecto.ConstraintError, Postgrex.Error] ->
      # A constraint violation Multi's own {:error, ...} tuple can't catch
      # (e.g. a row we didn't know to account for) — fail cleanly instead of
      # letting the exception propagate and crash the caller.
      {:error, {:constraint_error, Exception.message(error)}}
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
