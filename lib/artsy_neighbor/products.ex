defmodule ArtsyNeighbor.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.HardDelete
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Products.ProductOption
  alias ArtsyNeighbor.Products.ProductImage
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Reviews.ProductReview

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products()
      [%Product{}, ...]

  """
  def list_products do
    Repo.all(Product)
  end

  @doc """
  Returns the list of products with
  product_images, artist, and category associations preloaded.

  """
  def list_products_with_associations do
    Product
    |> only_available()
    |> preload([:product_images, :artist, :category])
    |> Repo.all()
  end

  @doc """
  Filters products based on the provided filter criteria.
  All products are loaded with associations.
  """
  def filter_products(filter) do
    Product
    |> only_available()
    |> join(:inner, [p], a in assoc(p, :artist), as: :artist)
    |> join(:inner, [p], c in assoc(p, :category), as: :category)
    |> with_category(filter["category_id"])
    |> with_artist(filter["artist"])
    |> with_search_term(filter["search"])
    |> sort_by(filter["sort_by"])
    |> preload([:artist, :category, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Same as filter_products/1 but not scoped to :available — for admin use,
  so an archived/unavailable product (see soft_delete_product/1) stays visible
  and manageable in the admin product list instead of silently
  disappearing the moment it's archived.
  """
  def filter_products_all_status(filter) do
    Product
    |> join(:inner, [p], a in assoc(p, :artist), as: :artist)
    |> join(:inner, [p], c in assoc(p, :category), as: :category)
    |> with_category(filter["category_id"])
    |> with_artist(filter["artist"])
    |> with_search_term(filter["search"])
    |> sort_by(filter["sort_by"])
    |> preload([:artist, :category, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
    Filters products for a specific artist based on the provided filter
    criteria, for the artist's own public store page
    (ArtistLive.Store — /artist/:id/store). All products are loaded with
    associations.

    Only available products are returned (only_available/1). The caller
    (ArtistLive.Store.handle_params/3) already checks the artist's own
    status; only_available/1 checks it again here as defense in depth,
    like every other public product query in this file.
  """
  def filter_artist_products(artist_id, filter) do
    Product
    |> only_available()
    |> where([p], p.artist_id == ^artist_id)
    |> join(:inner, [p], c in assoc(p, :category), as: :category)
    |> with_category(filter["category_id"])
    |> with_collection(filter["collection_id"])
    |> with_string(filter["search"])
    |> sort_by(filter["sort_by"])
    |> preload([:artist, :category, product_images: ^images_by_position()])
    |> Repo.all()
  end

  # Returns the list of products that have particular category.
  defp with_category(query, nil), do: query
  defp with_category(query, ""), do: query

  defp with_category(query, category_id) do
    id = String.to_integer(category_id)
    where(query, [p], p.category_id == ^id)
  end

  # Returns the list of products that have particular collection (artist-defined).
  defp with_collection(query, nil), do: query
  defp with_collection(query, ""), do: query

  defp with_collection(query, collection_id) do
    id = String.to_integer(collection_id)
    where(query, [p], p.collection_id == ^id)
  end

  # Returns the list of products that have a particular artist's nickname.
  defp with_artist(query, nil), do: query
  defp with_artist(query, ""), do: query

  defp with_artist(query, artist_name) do
    search = "%#{artist_name}%"
    where(query, [artist: a], ilike(a.nickname, ^search))
  end

  # Matches the search term against title, category name/description, OR
  # the artist's nickname — used by filter_products/1 and
  # filter_products_all_status/1, both of which join :artist.
  #
  # All four conditions are ORed inside a single `where`, which is then
  # ANDed with the rest of the query. Don't split this into `or_where`
  # calls: Ecto's or_where ORs against the *entire* WHERE clause built so
  # far, so a nickname match would bypass only_available/1 and every
  # other filter.
  defp with_search_term(query, nil), do: query
  defp with_search_term(query, ""), do: query

  defp with_search_term(query, search_term) do
    search = "%#{search_term}%"

    where(
      query,
      [p, artist: a, category: c],
      ilike(p.title, ^search) or
        ilike(c.name, ^search) or
        ilike(c.description, ^search) or
        ilike(a.nickname, ^search)
    )
  end

  # Returns the list of products that have a particular string in their
  # title, or in their category name or description. Used by
  # filter_artist_products/2, which is already scoped to one known
  # artist_id — matching the artist's own nickname wouldn't add anything
  # there, so it doesn't need with_search_term/2's extra OR clause (and
  # doesn't join :artist at all).
  defp with_string(query, nil), do: query
  defp with_string(query, ""), do: query

  defp with_string(query, string) do
    search = "%#{string}%"

    where(
      query,
      [p, category: c],
      ilike(p.title, ^search) or
        ilike(c.name, ^search) or
        ilike(c.description, ^search)
    )
  end

  # Sorts the products. Supported: "price_asc", "price_desc", "artist", "category".
  # Defaults to title order.
  defp sort_by(query, "price_asc"), do: order_by(query, [p], asc: p.price)
  defp sort_by(query, "price_desc"), do: order_by(query, [p], desc: p.price)
  defp sort_by(query, "artist"), do: order_by(query, [artist: a], asc: a.nickname)
  defp sort_by(query, "category"), do: order_by(query, [category: c], asc: c.name)
  defp sort_by(query, "collection"), do: order_by(query, [collection: c], asc: c.position)
  defp sort_by(query, _), do: order_by(query, [p], asc: p.title)

  @doc """
  Gets a single product.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{}

      iex> get_product!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product!(id), do: Repo.get!(Product, id)

  # The full set of associations a product's detail views (public, vendor,
  # admin) need preloaded. Pulled into one place so get_product_with_associations!/1,
  # get_product_with_associations/1, and get_product_with_associations_all_status/1
  # can't quietly drift apart the way three hand-copied lists would.
  defp product_associations do
    [
      :product_options,
      :artist,
      :category,
      :collection,
      product_images: images_by_position()
    ]
  end

  @doc """
  Gets a single product with all associations preloaded.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product_with_associations!(123)
      %Product{product_images: [...], artist: %Artist{}, category: %Category{}}

      iex> get_product_with_associations!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product_with_associations!(id) do
    Repo.get!(Product, id)
    |> Repo.preload(product_associations())
  end

  @doc """
  Gets a single product with all associations preloaded, scoped to public
  visibility (status: :available, with an artist still attached) — same
  predicate as only_available/1. Returns nil if the product doesn't exist
  OR isn't currently public (unavailable/archived), so a direct hit on an
  archived product's URL 404s the same way a bad id does, instead of
  leaking the product page. For the admin equivalent, which needs to see a
  product regardless of status, see get_product_with_associations_all_status/1.
  """
  def get_product_with_associations(id) do
    Product
    |> only_available()
    |> preload(^product_associations())
    |> Repo.get(id)
  end

  @doc """
  Same as get_product_with_associations/1 but not scoped to :available — the
  admin-only escape hatch, mirroring get_products_by_artist_all_status/1's
  naming. Returns nil if the product doesn't exist at all.
  """
  def get_product_with_associations_all_status(id) do
    Product
    |> preload(^product_associations())
    |> Repo.get(id)
  end

  # A subquery, not a join — only_available/1 is composed into queries that
  # sometimes already join :artist under their own alias (filter_products/1,
  # filter_products_all_status/1), so adding a second join here under a
  # fixed alias would collide. Defense in depth, independent of whatever
  # cascades an artist-status change is supposed to trigger elsewhere
  # (Artists.soft_delete_artist/1, Artists.deactivate_artist/1): even if a
  # product's own status is wrong for some reason (a write path that
  # bypasses those cascades, a bug, direct DB access), this keeps public
  # queries from ever surfacing a product whose artist isn't :active.
  defp only_available(query) do
    active_artist_ids = from(a in Artist, where: a.status == :active, select: a.id)

    query
    |> where([p], p.status == :available)
    |> where([p], not is_nil(p.artist_id))
    |> where([p], p.artist_id in subquery(active_artist_ids))
  end

  defp images_by_position, do: from(i in ProductImage, order_by: [asc: i.position])

  @doc """
  Gets products by a specific artist.

  ## Examples

      iex> get_products_by_artist(artist_id)
      [%Product{artist_id: artist_id, ...}, ...]

  """
  def get_products_by_artist(artist_id) do
    Product
    |> only_available()
    |> where([p], p.artist_id == ^artist_id)
    |> preload([:artist, :category, :collection, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Same as get_products_by_artist/1 but not scoped to :available — for the
  vendor's own dashboard, where they need to see and manage every product
  they own, including ones they've archived (see soft_delete_product/1).
  get_products_by_artist/1 is public-facing and would hide an archived
  product from its own owner.
  """
  def get_products_by_artist_all_status(artist_id) do
    Product
    |> where([p], p.artist_id == ^artist_id)
    |> preload([:artist, :category, :collection, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Returns products that have a specific category.
  ## Examples

      iex> get_products_by_category(category_id)
      [%Product{category_id: category_id, ...}, ...]

  """
  def get_products_by_category(category_id) do
    Product
    |> only_available()
    |> where([p], p.category_id == ^category_id)
    |> preload([:product_images, :artist, :category])
    |> Repo.all()
  end

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{field: value})
      {:ok, %Product{}}

      iex> create_product(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Assigns sequential positions (1, 2, 3…) to a list of products in the given
  order, in a single transaction. Used to reorder products within a collection.
  Works correctly even when some or all products currently have nil positions.
  """
  def swap_product_positions(%Product{} = a, %Product{} = b) do
    Repo.transaction(fn ->
      {:ok, _} = update_product(a, %{position: b.position})
      {:ok, _} = update_product(b, %{position: a.position})
    end)
  end

  @doc """
  Marks a product as :archived — a soft, reversible removal. This is the
  action a vendor takes to pull down their own listing; the product row and
  its data are kept, just hidden from public queries (see only_available/1).
  For permanent admin/testing cleanup that also removes dependent `Flag`
  rows, see hard_delete_product/1 instead, which is irreversible.
  """
  def soft_delete_product(%Product{} = product) do
    product
    |> Product.status_changeset(%{status: :archived})
    |> Repo.update()
  end

  @doc """
  Reverses soft_delete_product/1. Lands on :unavailable, not :available —
  an "un-archived, not yet republished" state, mirroring
  Artists.restore_artist/1 landing on :inactive.

  Known gap: nothing yet — vendor or admin — moves a product from
  :unavailable to :available, so restoring alone does not make a product
  purchasable again. A "mark available" action still needs to be built.

  Refuses (returns {:error, :artist_not_active}) unless the owning artist
  is currently :active. only_available/1 also checks this at query time;
  the check here gives a specific error instead of a silently empty
  result. Requiring :active (not just "not :removed") matters because
  Artists.restore_artist/1 only lands on :inactive, so a just-restored
  artist's products stay blocked until the vendor re-activates.

  Refuses (returns {:error, :category_missing}) if the product's category
  no longer exists (products.category_id is on_delete: :nilify_all, so
  AdminCategories.hard_delete_category/1 leaves it nil). It checks only
  that the category exists, not that it is :active.
  """
  def restore_product(%Product{} = product) do
    # force: true — a caller may pass in a product whose :artist/:category
    # associations were preloaded before a since-changed status (e.g.
    # fetched, then the artist was restored/removed, or the category
    # deleted, in between); these checks have to reflect current DB state,
    # not whatever the struct already carries.
    product = Repo.preload(product, [:artist, :category], force: true)

    cond do
      is_nil(product.artist) or product.artist.status != :active ->
        {:error, :artist_not_active}

      is_nil(product.category) ->
        {:error, :category_missing}

      true ->
        product
        |> Product.status_changeset(%{status: :unavailable})
        |> Repo.update()
    end
  end

  @doc """
  Deletes a product, and any `Flag` rows reporting it directly (subject_type
  "product") — `Flag.subject_id` is a polymorphic reference with no real DB
  FK, so it can't cascade and has to be cleaned up here by hand. Same class
  of cleanup as `Artists.hard_delete_artist/1`'s flag handling, and done by
  the same shared helper, `ArtsyNeighbor.HardDelete`. That helper also
  row-locks the product for the duration of the delete, so no order item
  or product review can be inserted against it mid-delete.

  The product's reviews (`product_reviews.product_id` is
  `on_delete: :delete_all`) cascade away with it, so flags reporting those
  reviews ("product_review_of") are cleaned up here too.

  `order_items.product_id` is `on_delete: :nothing`, so a product that
  appears in any order can't be hard-deleted — that fails with
  `{:error, {:database_error, message}}`. See
  `HardDelete.delete_with_flags/2` for the full list of error reasons.

  ## Examples

      iex> hard_delete_product(product)
      {:ok, %Product{}}

      iex> hard_delete_product(previously_ordered_product)
      {:error, {:database_error, "..."}}

  """
  def hard_delete_product(%Product{} = product) do
    HardDelete.delete_with_flags(product, fn repo, locked_product ->
      product_review_ids =
        repo.all(
          from(pr in ProductReview, where: pr.product_id == ^locked_product.id, select: pr.id)
        )

      %{"product" => [locked_product.id], "product_review_of" => product_review_ids}
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{data: %Product{}}

  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  @doc """
  Returns all product images.
  """
  def list_product_images do
    Repo.all(ProductImage)
  end

  @doc """
  Returns the list of product images for a specific product, ordered by position.

  ## Examples

      iex> list_images_for_product(product_id)
      [%ProductImage{}, ...]

  """
  def list_images_for_product(product_id) do
    ProductImage
    |> where([i], i.product_id == ^product_id)
    |> order_by([i], asc: i.position)
    |> Repo.all()
  end

  @doc """
  Gets a single product_image.

  Raises `Ecto.NoResultsError` if the Product image does not exist.

  ## Examples

      iex> get_product_image!(123)
      %ProductImage{}

      iex> get_product_image!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product_image!(id), do: Repo.get!(ProductImage, id)

  @doc """
  Creates a product_image.

  ## Examples

      iex> create_product_image(%{field: value})
      {:ok, %ProductImage{}}

      iex> create_product_image(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product_image(attrs) do
    %ProductImage{}
    |> ProductImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product_image.

  ## Examples

      iex> update_product_image(product_image, %{field: new_value})
      {:ok, %ProductImage{}}

      iex> update_product_image(product_image, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product_image(%ProductImage{} = product_image, attrs) do
    product_image
    |> ProductImage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product_image.

  ## Examples

      iex> delete_product_image(product_image)
      {:ok, %ProductImage{}}

      iex> delete_product_image(product_image)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product_image(%ProductImage{} = product_image) do
    Repo.delete(product_image)
  end

  @doc """
  Swaps the position values of two ProductImage records in a single transaction.
  Used to move images up or down in the display order.
  """
  def swap_image_positions(%ProductImage{} = a, %ProductImage{} = b) do
    Repo.transaction(fn ->
      {:ok, _} = update_product_image(a, %{position: b.position})
      {:ok, _} = update_product_image(b, %{position: a.position})
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product_image changes.

  ## Examples

      iex> change_product_image(product_image)
      %Ecto.Changeset{data: %ProductImage{}}

  """
  def change_product_image(%ProductImage{} = product_image, attrs \\ %{}) do
    ProductImage.changeset(product_image, attrs)
  end

  @doc """
  Returns the list of product_options.

  ## Examples

      iex> list_product_options()
      [%ProductOption{}, ...]

  """
  def list_product_options do
    Repo.all(ProductOption)
  end

  @doc """
  Gets a single product_option.

  Raises `Ecto.NoResultsError` if the Product option does not exist.

  ## Examples

      iex> get_product_option!(123)
      %ProductOption{}

      iex> get_product_option!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product_option!(id), do: Repo.get!(ProductOption, id)

  @doc """
  Creates a product_option.

  ## Examples

      iex> create_product_option(%{field: value})
      {:ok, %ProductOption{}}

      iex> create_product_option(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product_option(attrs) do
    %ProductOption{}
    |> ProductOption.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product_option.

  ## Examples

      iex> update_product_option(product_option, %{field: new_value})
      {:ok, %ProductOption{}}

      iex> update_product_option(product_option, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product_option(%ProductOption{} = product_option, attrs) do
    product_option
    |> ProductOption.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product_option.

  ## Examples

      iex> delete_product_option(product_option)
      {:ok, %ProductOption{}}

      iex> delete_product_option(product_option)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product_option(%ProductOption{} = product_option) do
    Repo.delete(product_option)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product_option changes.

  ## Examples

      iex> change_product_option(product_option)
      %Ecto.Changeset{data: %ProductOption{}}

  """
  def change_product_option(%ProductOption{} = product_option, attrs \\ %{}) do
    ProductOption.changeset(product_option, attrs)
  end

  # ============================================================
  # ProductCollection functions
  # ============================================================

  @doc """
  Returns all collections for an artist, ordered by position.
  Each collection has its products preloaded (ordered by position nulls last, then title).
  """
  def list_collections_for_artist(artist_id) do
    ProductCollection
    |> where([c], c.artist_id == ^artist_id)
    |> order_by([c], asc: c.position)
    |> preload(products: ^products_by_position())
    |> Repo.all()
  end

  @doc """
  Returns all collections for an artist, ordered by position.
  Does not preload products. Used when only collection names and IDs are needed (e.g. for filter dropdown).
  """
  def list_collections_for_artist_no_preloads(artist_id) do
    ProductCollection
    |> where([c], c.artist_id == ^artist_id)
    |> order_by([c], asc: c.position)
    |> Repo.all()
  end

  # Returns a query for products ordered by position (nulls last), then title.
  defp products_by_position do
    from(p in Product,
      order_by: [asc_nulls_last: p.position, asc: p.title],
      preload: [
        :artist,
        :category,
        product_images: ^from(i in ProductImage, order_by: [asc: i.position])
      ]
    )
  end

  @doc """
  Gets a single collection. Raises if it does not exist.
  """
  def get_collection!(id), do: Repo.get!(ProductCollection, id)

  @doc """
  Creates a collection.
  """
  def create_collection(attrs) do
    %ProductCollection{}
    |> ProductCollection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a collection.
  """
  def update_collection(%ProductCollection{} = collection, attrs) do
    collection
    |> ProductCollection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a collection and reassigns its products to the artist's "All Works"
  collection. Both operations run in a single transaction so neither happens
  without the other.
  """
  def delete_collection(%ProductCollection{} = collection) do
    # Find the "All Works" fallback collection for this artist (if it exists and
    # is not the collection being deleted).
    default_id =
      ProductCollection
      |> where([c], c.artist_id == ^collection.artist_id)
      |> where([c], c.name == ^ArtsyNeighbor.Artists.default_collection_name())
      |> where([c], c.id != ^collection.id)
      |> select([c], c.id)
      |> Repo.one()

    Repo.transaction(fn ->
      # Reassign all products in this collection to the default (or nil if none).
      from(p in Product, where: p.collection_id == ^collection.id)
      |> Repo.update_all(set: [collection_id: default_id])

      Repo.delete!(collection)
    end)
  end

  @doc """
  Returns a changeset for tracking collection changes.
  """
  def change_collection(%ProductCollection{} = collection, attrs \\ %{}) do
    ProductCollection.changeset(collection, attrs)
  end

  @doc """
  Swaps the position values of two ProductCollection records in a single transaction.
  Used to reorder collections on the vendor dashboard.
  """
  def swap_collection_positions(%ProductCollection{} = a, %ProductCollection{} = b) do
    Repo.transaction(fn ->
      {:ok, _} = update_collection(a, %{position: b.position})
      {:ok, _} = update_collection(b, %{position: a.position})
    end)
  end
end
