defmodule ArtsyNeighbor.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Accounts.Scope
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.HardDelete
  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Products.ProductOption
  alias ArtsyNeighbor.Products.ProductImage
  alias ArtsyNeighbor.Products.ProductCollection
  alias ArtsyNeighbor.Reviews.ProductReview

  # ---------------------------------------------------------------------------
  # Who is acting
  #
  # Every function that changes a work, its photos or a collection takes
  # the caller's scope (`socket.assigns.current_scope`) as its first
  # argument, as in `Orders`, and works out from it who is acting:
  #
  #   :owner - the user's artist profile owns the work or collection
  #   :admin - the user is an admin
  #
  # Each function lists the roles it allows. Anyone else gets
  # {:error, :unauthorized}. An owner whose profile has been removed
  # (Artists.soft_delete_artist/1) gets {:error, :artist_removed}: they
  # can still see their works, but no longer change them.
  #
  # Both are checked on the database as it is now, not on what the page
  # loaded: the struct a page passes in may be stale (an admin may have
  # moved the work to another artist since), and so may the scope. Each
  # change locks the row it changes (with_locked_product/4,
  # with_locked_collection/4) and checks the owner of the locked row, in
  # the same transaction as the change. The artist's status is read
  # with a shared lock (artist_removed?/1), so a removal can't happen
  # between the check and the change. A thing that no longer exists
  # gives {:error, :not_found}.
  #
  # Lock order, to avoid deadlocks: the row being changed first, then
  # the artist. Artists.soft_delete_artist/1 and deactivate_artist/1
  # also take the products first, then the artist.
  #
  # So pages never check "is this yours?" themselves, and a new page
  # can't forget to. Vendor pages look works and collections up with
  # get_own_product/2 and get_own_collection/2.
  # ---------------------------------------------------------------------------

  # {:ok, role} if the caller may act on something owned by the artist
  # with id `artist_id` in one of `allowed_roles`, otherwise
  # {:error, :unauthorized} or {:error, :artist_removed}.
  #
  # An admin who also owns the work counts as its owner, unless their
  # profile is removed: then they can still act as an admin, where the
  # function allows admins.
  defp authorize(scope, artist_id, allowed_roles) do
    acts_as_owner? = :owner in allowed_roles and owner?(scope, artist_id)
    acts_as_admin? = :admin in allowed_roles and Scope.admin?(scope)

    cond do
      acts_as_owner? and not artist_removed?(artist_id) -> {:ok, :owner}
      acts_as_admin? -> {:ok, :admin}
      acts_as_owner? -> {:error, :artist_removed}
      true -> {:error, :unauthorized}
    end
  end

  # True if the scope's artist profile is the artist with this id. False
  # for no scope (a logged-out visitor) or a user without a profile.
  defp owner?(%Scope{artist: %Artist{id: id}}, artist_id), do: id == artist_id
  defp owner?(_scope, _artist_id), do: false

  # Read with FOR SHARE: until the surrounding transaction ends, nobody
  # can change the artist's status (a removal waits for this change to
  # finish, then happens).
  defp artist_removed?(artist_id) do
    status =
      Artist
      |> where([a], a.id == ^artist_id)
      |> select([a], a.status)
      |> lock("FOR SHARE")
      |> Repo.one()

    status == :removed
  end

  # Runs `change` with the product as it is now, locked until the
  # transaction ends, if the caller may act on it. `change` gets the
  # locked product and returns {:ok, result} or {:error, reason};
  # an error undoes everything.
  defp with_locked_product(scope, product_id, allowed_roles, change) do
    Repo.transact(fn ->
      case lock_product(product_id) do
        nil ->
          {:error, :not_found}

        locked ->
          with {:ok, _role} <- authorize(scope, locked.artist_id, allowed_roles) do
            change.(locked)
          end
      end
    end)
  end

  # The same for a collection.
  defp with_locked_collection(scope, collection_id, allowed_roles, change) do
    Repo.transact(fn ->
      case lock_collection(collection_id) do
        nil ->
          {:error, :not_found}

        locked ->
          with {:ok, _role} <- authorize(scope, locked.artist_id, allowed_roles) do
            change.(locked)
          end
      end
    end)
  end

  @doc """
  The logged-in artist's own work with this id, with its photos and
  other associations loaded, or nil if it isn't theirs, doesn't exist,
  or `id` is nil (a forged id that `ArtsyNeighborWeb.Params.parse_id/1`
  turned into nil). Any status. For the vendor pages.
  """
  def get_own_product(%Scope{artist: %Artist{id: artist_id}}, id) when is_integer(id) do
    Product
    |> where([p], p.id == ^id and p.artist_id == ^artist_id)
    |> preload(^product_associations())
    |> Repo.one()
  end

  def get_own_product(_scope, _id), do: nil

  @doc """
  The logged-in artist's own collection with this id, or nil if it
  isn't theirs, doesn't exist, or `id` is nil. For the vendor pages.
  """
  def get_own_collection(%Scope{artist: %Artist{id: artist_id}}, id) when is_integer(id) do
    ProductCollection
    |> where([c], c.id == ^id and c.artist_id == ^artist_id)
    |> Repo.one()
  end

  def get_own_collection(_scope, _id), do: nil

  @doc """
  What a page tells the artist when a change was refused, for the two
  reasons in "Who is acting" above.
  """
  def refused_message(:artist_removed) do
    "Your artist profile has been removed, so your works and collections " <>
      "can't be changed. Please contact us if you think this is a mistake."
  end

  def refused_message(:unauthorized) do
    "That isn't one of your works or collections, so it can't be changed."
  end

  def refused_message(:not_found) do
    "That doesn't exist any more. It may have just been removed."
  end

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
  All products are loaded with associations. Works without a category
  are included (sorted last by category).
  """
  def filter_products(filter) do
    Product
    |> only_available()
    |> join(:inner, [p], a in assoc(p, :artist), as: :artist)
    # A left join, so works without a category (left empty, or their
    # category was deleted) are still listed; the home page's "See all
    # new works" leads here, and New works shows them too.
    |> join(:left, [p], c in assoc(p, :category), as: :category)
    |> with_category(filter["category_id"])
    |> with_artist(filter["artist"])
    |> with_search_term(filter["search"])
    |> sort_by(filter["sort_by"])
    |> preload([:artist, :category, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Same as filter_products/1 but not scoped to :available — for admin use,
  so an archived/unavailable product (see soft_delete_product/2) stays visible
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
    criteria, for the Shop tab of the artist's public page
    (ArtistLive.Show — /artists/:id/store). All products are loaded with
    associations.

    Only available products are returned (only_available/1). The caller
    (ArtistLive.Show.handle_params/3) already checks the artist's own
    status; only_available/1 checks it again here as defense in depth,
    like every other public product query in this file.

    For the owner's preview of a profile that isn't public yet, use
    `filter_artist_products_for_owner_preview/2`.
  """
  def filter_artist_products(artist_id, filter) do
    artist_products(artist_id, filter, :public)
  end

  @doc """
  Like `filter_artist_products/2`, but for the owner's preview of their
  own profile (`?preview=1`), which isn't public yet: the artist's own
  status is not checked. Only for a caller that has made sure the
  viewer owns the profile (ArtistLive.Show does).
  """
  def filter_artist_products_for_owner_preview(artist_id, filter) do
    artist_products(artist_id, filter, :owner_preview)
  end

  defp artist_products(artist_id, filter, audience) do
    Product
    |> shown_products(audience)
    |> where([p], p.artist_id == ^artist_id)
    |> join(:inner, [p], c in assoc(p, :category), as: :category)
    |> with_category(filter["category_id"])
    |> with_collection(filter["collection_id"])
    |> with_string(filter["search"])
    # The Shop tab shows the newest works first unless asked otherwise.
    |> sort_by(filter["sort_by"] || "newest")
    |> preload([:artist, :category, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Returns the categories an artist has available works in, with how
  many works each, as `{category_id, category_name, count}` tuples
  ordered by name. For the Shop tab's category dropdown ("Paintings
  (21)"). For the owner's preview, use
  `count_artist_products_by_category_for_owner_preview/1`.
  """
  def count_artist_products_by_category(artist_id) do
    artist_category_counts(artist_id, :public)
  end

  @doc """
  Like `count_artist_products_by_category/1`, but for the owner's
  preview of their own profile: the artist's own status is not checked.
  Only for a caller that has made sure the viewer owns the profile.
  """
  def count_artist_products_by_category_for_owner_preview(artist_id) do
    artist_category_counts(artist_id, :owner_preview)
  end

  # Counts the same works the Shop tab lists (its inner join on category
  # leaves out works without one), grouped by their category.
  defp artist_category_counts(artist_id, audience) do
    Product
    |> shown_products(audience)
    |> where([p], p.artist_id == ^artist_id)
    |> join(:inner, [p], c in assoc(p, :category), as: :category)
    |> group_by([category: c], [c.id, c.name])
    |> order_by([category: c], asc: c.name)
    |> select([p, category: c], {c.id, c.name, count(p.id)})
    |> Repo.all()
  end

  @doc """
  Returns an artist's `count` newest available works, newest first, with
  their artist, category and photos loaded.

  The artist page's "Featured works" shows these until artists can
  choose their own (NOTES.md #23), and so does the artist's card on the
  home page (`Artists.list_popular_artists/1`). For the owner's preview, use
  `list_newest_artist_products_for_owner_preview/2`.
  """
  def list_newest_artist_products(artist_id, count) do
    newest_artist_products(artist_id, count, :public)
  end

  @doc """
  Like `list_newest_artist_products/2`, but for the owner's preview of
  their own profile: the artist's own status is not checked. Only for a
  caller that has made sure the viewer owns the profile.
  """
  def list_newest_artist_products_for_owner_preview(artist_id, count) do
    newest_artist_products(artist_id, count, :owner_preview)
  end

  defp newest_artist_products(artist_id, count, audience) do
    Product
    |> shown_products(audience)
    |> where([p], p.artist_id == ^artist_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^count)
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

  # Sorts the products. Supported: "newest", "price_asc", "price_desc",
  # "artist", "category", "collection". Defaults to title order.
  defp sort_by(query, "newest"), do: order_by(query, [p], desc: p.inserted_at, desc: p.id)
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

  @doc """
  Gets a single product by id, whatever its status, or nil if there is
  none. Like get_product!/1 but doesn't raise, for ids that come from
  the browser. Not for public pages: those must only see :available
  products (get_product_with_associations/1).
  """
  def get_product_all_status(id), do: Repo.get(Product, id)

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
  The work shown in the home page's hero, with its artist, for the
  credit on the picture. The picture is a detail of that work, so it is
  credited whatever the work's status; `for_sale` says whether it may
  also link to the work's page (the same check as only_available/1).

  Returns `%{product: product, for_sale: true | false}`, or nil when
  there is no such work, or no id was set (nil).
  """
  def get_hero_work(nil), do: nil

  def get_hero_work(id) do
    case Repo.get(Product, id) do
      nil ->
        nil

      product ->
        for_sale =
          Product
          |> only_available()
          |> where([p], p.id == ^product.id)
          |> Repo.exists?()

        %{product: Repo.preload(product, :artist), for_sale: for_sale}
    end
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

  @doc """
  Narrows a product query to the works the public may see, i.e. the
  works for sale: `:available`, with an artist, and that artist
  `:active`. For other contexts too (`Categories.list_popular_categories/0`),
  so "for sale" means the same everywhere.
  """
  # A subquery, not a join — only_available/1 is composed into queries that
  # sometimes already join :artist under their own alias (filter_products/1,
  # filter_products_all_status/1), so adding a second join here under a
  # fixed alias would collide. Defense in depth, independent of whatever
  # cascades an artist-status change is supposed to trigger elsewhere
  # (Artists.soft_delete_artist/1, Artists.deactivate_artist/1): even if a
  # product's own status is wrong for some reason (a write path that
  # bypasses those cascades, a bug, direct DB access), this keeps public
  # queries from ever surfacing a product whose artist isn't :active.
  def only_available(query) do
    active_artist_ids = from(a in Artist, where: a.status == :active, select: a.id)

    query
    |> where([p], p.status == :available)
    |> where([p], not is_nil(p.artist_id))
    |> where([p], p.artist_id in subquery(active_artist_ids))
  end

  # Which products the artist page may show. Each artist-page query
  # above is written once, in a private function that takes the
  # audience, and calls this; its public functions only pick the
  # audience. So the two cases differ only here:
  #   * :public — only_available/1, for every visitor.
  #   * :owner_preview — the same, except the artist's own status is not
  #     checked: the owner previewing a profile that isn't public yet
  #     sees what visitors will see once it is.
  defp shown_products(query, :public), do: only_available(query)

  defp shown_products(query, :owner_preview) do
    query
    |> where([p], p.status == :available)
    |> where([p], not is_nil(p.artist_id))
  end

  defp images_by_position, do: from(i in ProductImage, order_by: [asc: i.position])

  @doc """
  Returns the `count` newest available works on the whole site, newest
  first, with their artist and photos loaded: the home page's "New
  works".
  """
  def list_newest_works(count) do
    Product
    |> only_available()
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^count)
    |> preload([:artist, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  A query for the artists who have works for sale, one row each, with
  when they added their newest one:
  `%{artist_id: 50, newest_work_at: ~U[...]}`. For other queries to join
  to, e.g. `Artists.list_popular_artists/1`.
  """
  def artists_with_works_for_sale_query do
    from(p in only_available(Product),
      group_by: p.artist_id,
      select: %{artist_id: p.artist_id, newest_work_at: max(p.inserted_at)}
    )
  end

  @doc """
  Returns up to `count` other available works by the same artist as
  `product`, newest first, with their artist and photos loaded: the
  product page's "More by <artist>".
  """
  def list_more_by_artist(product, count) do
    Product
    |> only_available()
    |> where([p], p.artist_id == ^product.artist_id and p.id != ^product.id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^count)
    |> preload([:artist, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Returns up to `count` available works by other artists in the same
  category as `product`, newest first, with their artist and photos
  loaded: the product page's "You may also like". A work without a
  category (its category was deleted) has none.
  """
  def list_similar_works(%Product{category_id: nil}, _count), do: []

  def list_similar_works(product, count) do
    Product
    |> only_available()
    |> where([p], p.category_id == ^product.category_id)
    |> where([p], p.artist_id != ^product.artist_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^count)
    |> preload([:artist, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  An artist's works that are for sale (only_available/1: :available,
  with the artist :active), with their photos, by title. Used for the
  vendor's "+ Add item" list on an open order: only works for sale can
  go in an order.
  """
  def list_available_products_by_artist(artist_id) do
    Product
    |> where([p], p.artist_id == ^artist_id)
    |> only_available()
    |> order_by([p], asc: p.title)
    |> preload(product_images: ^images_by_position())
    |> Repo.all()
  end

  @doc """
  True if the work with this id is for sale right now: the same rule as
  only_available/1, checked fresh in the database (a product struct a
  page loaded earlier may be out of date). Orders uses this before
  putting a work in an order.
  """
  def for_sale?(product_id) when is_integer(product_id) do
    Product
    |> where([p], p.id == ^product_id)
    |> only_available()
    |> Repo.exists?()
  end

  def for_sale?(_no_id), do: false

  @doc """
  All of an artist's products, whatever their status — for the vendor's
  own dashboard, where they need to see and manage every product they
  own, including ones they've archived (see soft_delete_product/2).
  """
  def get_products_by_artist_all_status(artist_id) do
    Product
    |> where([p], p.artist_id == ^artist_id)
    |> preload([:artist, :category, :collection, product_images: ^images_by_position()])
    |> Repo.all()
  end

  @doc """
  Creates a product owned by the logged-in artist (`scope.artist`).

  The owner is never taken from `attrs`, so a hand-made request can't
  put the work on another artist's page (audit S-3). The admin form,
  which picks the artist, uses `AdminProducts.create_product/2`.

  Returns `{:error, :unauthorized}` for a scope without an artist
  profile, and `{:error, :artist_removed}` if that profile is removed
  (see "Who is acting" at the top).

  ## Examples

      iex> create_product(scope, %{field: value})
      {:ok, %Product{}}

      iex> create_product(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(%Scope{artist: %Artist{id: artist_id}} = scope, attrs) do
    # In a transaction, so the artist can't be removed between the check
    # and the insert (see "Who is acting").
    Repo.transact(fn ->
      with {:ok, _role} <- authorize(scope, artist_id, [:owner]) do
        # New products always start as :draft (Product.changeset/2 doesn't
        # take a status); see "Publishing and photos" below.
        %Product{artist_id: artist_id}
        |> Product.changeset(attrs)
        |> save_product()
      end
    end)
  end

  def create_product(_scope, _attrs), do: {:error, :unauthorized}

  @doc """
  Updates a product, for its owner or an admin. Never changes its
  owner or its status (`Product.changeset/2` takes neither).

  The changes are applied to the product as it is now in the database
  (only the changed fields are written). Returns that product, without
  its associations loaded, or `{:error, :not_found}` if it was deleted.

  ## Examples

      iex> update_product(scope, product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(scope, product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

      iex> update_product(someone_elses_scope, product, %{field: new_value})
      {:error, :unauthorized}

  """
  def update_product(scope, %Product{} = product, attrs) do
    with_locked_product(scope, product.id, [:owner, :admin], fn locked ->
      locked
      |> Product.changeset(attrs)
      |> save_product()
    end)
  end

  @doc """
  Inserts or updates a product from a changeset, after the checks every
  product save needs: a product with no collection chosen goes into its
  artist's default collection, and a collection belonging to another
  artist is refused.

  Takes a changeset, never a map of params: the owner is whatever the
  changeset says, so the caller must have chosen it. It doesn't check
  who is acting, so pages never call it: they use `create_product/2`
  and `update_product/3`, or `AdminProducts`, which builds its
  changesets with `Product.admin_changeset/2` and checks for an admin.
  """
  def save_product(%Ecto.Changeset{} = changeset) do
    changeset
    |> put_default_collection()
    |> validate_collection_owner()
    |> Repo.insert_or_update()
  end

  # A product with no collection chosen goes into its artist's default
  # collection (is_default), which every artist gets when their profile
  # is created. Without this it would be missing from the vendor
  # dashboard, which lists products by collection.
  defp put_default_collection(changeset) do
    collection_id = Ecto.Changeset.get_field(changeset, :collection_id)
    artist_id = Ecto.Changeset.get_field(changeset, :artist_id)

    if is_nil(collection_id) and not is_nil(artist_id) do
      Ecto.Changeset.put_change(changeset, :collection_id, default_collection_id(artist_id))
    else
      changeset
    end
  end

  # A product may only be in one of its own artist's collections.
  # Otherwise a hand-made request from the vendor form could show a work
  # inside another artist's collection, on their page (audit S-3). It
  # also catches the admin form moving a work to another artist while
  # leaving it in the old artist's collection. A collection id that
  # doesn't exist is refused the same way.
  #
  # Checked only for a new product, or when its collection or owner
  # changes: an edit that changes neither (the price, the order of works)
  # can't break the rule, so it doesn't need the extra query.
  defp validate_collection_owner(changeset) do
    collection_id = Ecto.Changeset.get_field(changeset, :collection_id)
    artist_id = Ecto.Changeset.get_field(changeset, :artist_id)

    new_product? = changeset.data.__meta__.state == :built

    needs_check? =
      new_product? or
        Ecto.Changeset.changed?(changeset, :collection_id) or
        Ecto.Changeset.changed?(changeset, :artist_id)

    if is_nil(collection_id) or not needs_check? do
      changeset
    else
      collection_artist_id =
        ProductCollection
        |> where([c], c.id == ^collection_id)
        |> select([c], c.artist_id)
        |> Repo.one()

      if collection_artist_id != nil and collection_artist_id == artist_id do
        changeset
      else
        Ecto.Changeset.add_error(
          changeset,
          :collection_id,
          "Please choose one of this artist's own collections."
        )
      end
    end
  end

  # --- Publishing and photos ------------------------------------------
  #
  # The rule: a product can only be :available (for sale, shown to the
  # public) while it has at least one photo. Kept here, in the context,
  # so every form and any future code follows it:
  #   * the general create_product/2 and update_product/3 can't change
  #     the status at all; new products start as :draft;
  #   * publish_product/2 is the only way to :available, and refuses a
  #     product without a photo;
  #   * delete_product_image/2 moves an :available product back to
  #     :draft when its last photo is removed.
  # (Seeds and test fixtures insert published products directly, as
  # stand-ins for existing data.)
  #
  # Temporary until the vendor dashboard lets artists switch each work
  # between draft / available / unavailable / archived (NOTES #16).

  @doc """
  Makes a product :available (for sale), if it has at least one photo.

  Works from :draft and :unavailable, for the work's owner or an
  admin. Returns `{:ok, product}`, or `{:error, :no_photos}`, or
  `{:error, :archived}` for an archived product (that one needs
  restore_product/2 first), or `{:error, :unauthorized}`. An already
  :available product is returned unchanged.
  """
  def publish_product(scope, %Product{} = product) do
    # Under the product's lock, so a photo can't be removed meanwhile.
    with_locked_product(scope, product.id, [:owner, :admin], fn locked ->
      cond do
        locked.status == :available ->
          {:ok, locked}

        locked.status == :archived ->
          {:error, :archived}

        count_photos(locked.id) == 0 ->
          {:error, :no_photos}

        true ->
          locked
          |> Product.status_changeset(%{status: :available})
          |> Repo.update()
      end
    end)
  end

  defp count_photos(product_id) do
    ProductImage
    |> where([i], i.product_id == ^product_id)
    |> Repo.aggregate(:count)
  end

  # Locks the product's row until the surrounding transaction ends and
  # returns the product as it is now, or nil if it no longer exists.
  # Every change to a product or its photos takes this lock first, so
  # they can't overlap (e.g. the last photo removed while the product is
  # being published).
  defp lock_product(product_id) do
    Product
    |> where([p], p.id == ^product_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @doc """
  Swaps two works of the same collection in its order, for moving a
  work up or down on the vendor dashboard. For the works' owner or an
  admin; two works of different artists are refused
  (`{:error, :unauthorized}`).

  The collection's works are first numbered 1, 2, 3, ... in the order
  the dashboard shows them (products_by_position/1). New works have no
  position yet, and a deleted collection's works keep theirs when they
  move to the default one, so swapping the stored numbers alone could
  do nothing.

  Returns `{:ok, works_in_new_order}`. If one of the two has meanwhile
  moved to another collection or been deleted, nothing changes and the
  result is `{:ok, works_in_current_order}`: the page then shows the
  current order.
  """
  def swap_product_positions(scope, %Product{} = a, %Product{} = b) do
    Repo.transact(fn ->
      works = lock_collection_works(a.id)
      fresh_a = Enum.find(works, fn work -> work.id == a.id end)
      fresh_b = Enum.find(works, fn work -> work.id == b.id end)

      if is_nil(fresh_a) do
        {:error, :not_found}
      else
        with {:ok, _role} <- authorize(scope, fresh_a.artist_id, [:owner, :admin]) do
          cond do
            fresh_b != nil -> renumber_works(swap_in_list(works, fresh_a, fresh_b))
            someone_elses_work?(b.id, fresh_a.artist_id) -> {:error, :unauthorized}
            # b has moved to another collection, or is gone: no change.
            true -> {:ok, works}
          end
        end
      end
    end)
  end

  # True if the work with this id exists and belongs to another artist.
  defp someone_elses_work?(product_id, artist_id) do
    case product_artist_id(product_id) do
      nil -> false
      owner_id -> owner_id != artist_id
    end
  end

  # Locks all the works in the collection the work with this id is in,
  # and returns them in the dashboard's order (products_by_position/1;
  # sorted by the database, which compares titles the same way there).
  # [] if the work is gone. One statement, so two moves at the same
  # moment take turns instead of each waiting for a row the other holds.
  defp lock_collection_works(product_id) do
    collection_id =
      Product
      |> where([p], p.id == ^product_id)
      |> select([p], p.collection_id)
      |> Repo.one()

    if is_nil(collection_id) do
      []
    else
      Product
      |> where([p], p.collection_id == ^collection_id)
      |> order_by([p], asc_nulls_last: p.position, asc: p.title, asc: p.id)
      |> lock("FOR UPDATE")
      |> Repo.all()
    end
  end

  # The list with `a` and `b` in each other's place.
  defp swap_in_list(works, a, b) do
    Enum.map(works, fn work ->
      cond do
        work.id == a.id -> b
        work.id == b.id -> a
        true -> work
      end
    end)
  end

  # Gives the works positions 1, 2, 3, ... in this order, writing only
  # the ones that change.
  defp renumber_works(works) do
    renumbered =
      for {work, position} <- Enum.with_index(works, 1) do
        if work.position == position do
          work
        else
          {:ok, updated} = update_product_position(work, position)
          updated
        end
      end

    {:ok, renumbered}
  end

  defp update_product_position(product, position) do
    product
    |> Product.position_changeset(%{position: position})
    |> Repo.update()
  end

  @doc """
  Marks a product as :archived — a soft, reversible removal. This is the
  action a vendor takes to pull down their own listing; the product row and
  its data are kept, just hidden from public queries (see only_available/1).
  For permanent admin/testing cleanup that also removes dependent `Flag`
  rows, see hard_delete_product/2 instead, which is irreversible.

  For the work's owner or an admin.
  """
  def soft_delete_product(scope, %Product{} = product) do
    with_locked_product(scope, product.id, [:owner, :admin], fn locked ->
      locked
      |> Product.status_changeset(%{status: :archived})
      |> Repo.update()
    end)
  end

  @doc """
  Reverses soft_delete_product/2. Lands on :unavailable, not :available —
  an "un-archived, not yet republished" state, mirroring
  Artists.restore_artist/1 landing on :inactive.

  Restoring alone does not make a product purchasable again: that is a
  separate step, publish_product/2 (:unavailable -> :available, needs a
  photo). publish_product/2 refuses :archived products on purpose, so
  coming back from archive always goes through the checks below first.
  Neither vendors nor admins have a button for that second step yet
  (NOTES #16).

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

  For the work's owner or an admin (`{:error, :unauthorized}` otherwise).
  Returns the product as it is now, with only `:artist` and `:category`
  loaded.
  """
  def restore_product(scope, %Product{} = product) do
    with_locked_product(scope, product.id, [:owner, :admin], fn locked ->
      restore_checked(locked)
    end)
  end

  defp restore_checked(product) do
    # Read fresh, under the product's lock: the artist may have been
    # restored or removed, or the category deleted, since the page
    # loaded the product.
    product = Repo.preload(product, [:artist, :category])

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
  `HardDelete.delete_with_flags/3` for the full list of error reasons.

  Admins only (`{:error, :unauthorized}` for anyone else, the work's
  owner too: vendors archive their works with soft_delete_product/2).

  ## Examples

      iex> hard_delete_product(admin_scope, product)
      {:ok, %Product{}}

      iex> hard_delete_product(admin_scope, previously_ordered_product)
      {:error, {:database_error, "..."}}

  """
  def hard_delete_product(scope, %Product{} = product) do
    with {:ok, _role} <- authorize(scope, product.artist_id, [:admin]) do
      delete_with_flags(product)
    end
  end

  defp delete_with_flags(product) do
    HardDelete.delete_with_flags(product, fn repo, locked_product ->
      product_review_ids =
        repo.all(
          from(pr in ProductReview, where: pr.product_id == ^locked_product.id, select: pr.id)
        )

      # The photo rows cascade away with the product; their files are
      # deleted after the commit. (The product's row lock already makes
      # a photo being added at this moment wait.)
      photo_paths =
        repo.all(
          from(i in ProductImage, where: i.product_id == ^locked_product.id, select: i.path)
        )

      %{
        flag_subjects: %{
          "product" => [locked_product.id],
          "product_review_of" => product_review_ids
        },
        photo_paths: photo_paths
      }
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
  Adds a photo row to `product`, for the work's owner or an admin. Only
  `path` and `position` are taken from `attrs`; the photo always
  belongs to `product`.

  ## Examples

      iex> create_product_image(scope, product, %{path: key, position: 1})
      {:ok, %ProductImage{}}

      iex> create_product_image(scope, product, %{path: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_product_image(scope, %Product{} = product, attrs) do
    with_locked_product(scope, product.id, [:owner, :admin], fn locked ->
      %ProductImage{product_id: locked.id}
      |> ProductImage.changeset(attrs)
      |> Repo.insert()
    end)
  end

  @doc """
  Deletes a product_image. If it was the last photo of an :available
  product, the product goes back to :draft (it can't be for sale
  without a photo); callers can re-read the product to tell the artist.

  For the work's owner or an admin. Returns `{:ok, %ProductImage{}}`,
  `{:error, :not_found}` if the photo (or its whole work) was already
  removed (e.g. in another browser tab), or `{:error, :unauthorized}`.

  Once the row is deleted, the photo's files are deleted from storage
  too, in the background (`Images.delete_files_of_deleted_row/1`):
  new visitors then get "not found" at its address, though a browser
  that already showed it may keep its own copy for a while.

  """
  def delete_product_image(scope, %ProductImage{} = product_image) do
    scope
    |> delete_product_image_row(product_image)
    |> Images.delete_files_of_deleted_row()
  end

  defp delete_product_image_row(scope, product_image) do
    with_locked_product(scope, product_image.product_id, [:owner, :admin], fn product ->
      # The photo is read again, under the product's lock: it may
      # already be gone, e.g. removed in another browser tab. (Deleting
      # a row that no longer exists would raise.)
      case Repo.get(ProductImage, product_image.id) do
        nil ->
          {:error, :not_found}

        current_image ->
          with {:ok, deleted} <- Repo.delete(current_image),
               {:ok, _product} <- draft_if_no_photos_left(product) do
            {:ok, deleted}
          end
      end
    end)
  end

  # After a photo is removed: an :available product with no photos left
  # goes back to :draft (see "Publishing and photos" above).
  defp draft_if_no_photos_left(product) do
    if product.status == :available and count_photos(product.id) == 0 do
      product
      |> Product.status_changeset(%{status: :draft})
      |> Repo.update()
    else
      {:ok, product}
    end
  end

  @doc """
  Swaps the positions of two photos of the same work, in one
  transaction. Used to move a photo up or down on the product forms.
  For the work's owner or an admin; photos of two different works are
  refused (`{:error, :unauthorized}`), and `{:error, :not_found}` if
  either photo was removed meanwhile.
  """
  def swap_image_positions(scope, %ProductImage{} = a, %ProductImage{} = b) do
    with_locked_product(scope, a.product_id, [:owner, :admin], fn product ->
      # Read again under the product's lock (see delete_product_image/2).
      fresh_a = Repo.get(ProductImage, a.id)
      fresh_b = Repo.get(ProductImage, b.id)

      cond do
        is_nil(fresh_a) or is_nil(fresh_b) ->
          {:error, :not_found}

        fresh_a.product_id != product.id or fresh_b.product_id != product.id ->
          {:error, :unauthorized}

        true ->
          {:ok, _} = update_image_position(fresh_a, fresh_b.position)
          {:ok, _} = update_image_position(fresh_b, fresh_a.position)
          {:ok, [fresh_a.id, fresh_b.id]}
      end
    end)
  end

  # The owner of the work with this id, read from the database.
  defp product_artist_id(product_id) do
    Product
    |> where([p], p.id == ^product_id)
    |> select([p], p.artist_id)
    |> Repo.one()
  end

  defp update_image_position(product_image, position) do
    product_image
    |> ProductImage.position_changeset(%{position: position})
    |> Repo.update()
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
  Returns all collections for an artist, ordered by position, with the
  default collection last (as on the public pages). Each collection has
  its products preloaded (ordered by position nulls last, then title).
  """
  def list_collections_for_artist(artist_id) do
    ProductCollection
    |> where([c], c.artist_id == ^artist_id)
    # false sorts before true: the default collection comes last.
    |> order_by([c], asc: c.is_default, asc: c.position)
    |> preload(products: ^products_by_position(artist_id))
    |> Repo.all()
  end

  @doc """
  Returns the collections a visitor should see on an artist's page,
  ordered by position. Each has only its available works preloaded
  (ordered like `list_collections_for_artist/1`).

  Left out: collections with no available works. The artist's default
  collection (`is_default`) is shown only when it has available works,
  and always last: it is a catch-all rather than a collection the
  artist made. For the owner's preview, use
  `list_collections_for_owner_preview/1`.
  """
  def list_public_collections_for_artist(artist_id) do
    shown_collections(artist_id, :public)
  end

  @doc """
  Like `list_public_collections_for_artist/1`, but for the owner's
  preview of their own profile: the artist's own status is not checked.
  Only for a caller that has made sure the viewer owns the profile.
  """
  def list_collections_for_owner_preview(artist_id) do
    shown_collections(artist_id, :owner_preview)
  end

  defp shown_collections(artist_id, audience) do
    # Works without a category are left out, as the Shop tab's list
    # leaves them out (artist_products/3 joins on category), so a
    # collection's chip count matches what pressing it shows. A work
    # loses its category only when an admin hard-deletes that category.
    available_products =
      Product
      |> shown_products(audience)
      # Only the artist's own works, even if a work from someone else
      # ever ended up in one of their collections (audit S-3; saving a
      # product already refuses that).
      |> where([p], p.artist_id == ^artist_id)
      |> where([p], not is_nil(p.category_id))
      |> order_by([p], asc_nulls_last: p.position, asc: p.title)
      |> preload(product_images: ^images_by_position())

    ProductCollection
    |> where([c], c.artist_id == ^artist_id)
    # false sorts before true: the default collection comes last.
    |> order_by([c], asc: c.is_default, asc: c.position)
    |> preload(products: ^available_products)
    |> Repo.all()
    |> Enum.reject(fn collection -> collection.products == [] end)
  end

  # Returns a query for the artist's products, ordered by position
  # (nulls last), then title. Only the artist's own works, even if a
  # work from someone else ever ended up in one of their collections
  # (audit S-3; saving a product already refuses that).
  defp products_by_position(artist_id) do
    from(p in Product,
      where: p.artist_id == ^artist_id,
      # The same order as lock_collection_works/1, which moving a work
      # relies on; the id makes it the same even for equal titles.
      order_by: [asc_nulls_last: p.position, asc: p.title, asc: p.id],
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
  Gets a single collection, or nil if there is none. For ids that come
  from the browser.
  """
  def get_collection(id), do: Repo.get(ProductCollection, id)

  @doc """
  The id of the artist's default collection (`is_default`), or nil if
  the artist has none. There is at most one: a unique index says so.
  """
  def default_collection_id(artist_id) do
    ProductCollection
    |> where([c], c.artist_id == ^artist_id and c.is_default)
    |> select([c], c.id)
    |> Repo.one()
  end

  @doc """
  Creates a collection owned by the logged-in artist (`scope.artist`),
  after their other collections. Only the name is taken from `attrs`:
  the owner comes from the scope, and the position is worked out here
  (audit S-4). Never a default collection: each artist's one is made
  with the profile (`Artists.create_artist/1`).

  Returns `{:error, :unauthorized}` for a scope without an artist
  profile, and `{:error, :artist_removed}` if that profile is removed.
  """
  def create_collection(%Scope{artist: %Artist{id: artist_id}} = scope, attrs) do
    # The artist's row is locked while the position is worked out and
    # the collection inserted, so two collections made at the same
    # moment (two tabs) take turns and get different positions. It is
    # locked before the check, so the check's shared lock doesn't have
    # to be turned into this one while another tab holds it too.
    Repo.transact(fn ->
      lock_artist(artist_id)

      with {:ok, _role} <- authorize(scope, artist_id, [:owner]) do
        %ProductCollection{artist_id: artist_id, position: next_collection_position(artist_id)}
        |> ProductCollection.changeset(attrs)
        |> Repo.insert()
      end
    end)
  end

  def create_collection(_scope, _attrs), do: {:error, :unauthorized}

  # Locks the artist's row until the surrounding transaction ends. A
  # missing artist locks nothing; the insert then fails on its own
  # (assoc_constraint).
  defp lock_artist(artist_id) do
    Artist
    |> where([a], a.id == ^artist_id)
    |> lock("FOR UPDATE")
    |> select([a], a.id)
    |> Repo.one()
  end

  # max(position) + 1 for the artist's collections, or 1 if there are
  # none. max rather than a count, so a deleted collection's position
  # isn't reused while a later one still has it.
  defp next_collection_position(artist_id) do
    max_position =
      ProductCollection
      |> where([c], c.artist_id == ^artist_id)
      |> select([c], max(c.position))
      |> Repo.one()

    (max_position || 0) + 1
  end

  @doc """
  Renames a collection: only the name is taken from `attrs`
  (`ProductCollection.changeset/2`). The default collection may be
  renamed too. For the collection's owner or an admin.
  """
  def update_collection(scope, %ProductCollection{} = collection, attrs) do
    with_locked_collection(scope, collection.id, [:owner, :admin], fn locked ->
      locked
      |> ProductCollection.changeset(attrs)
      |> Repo.update()
    end)
  end

  # Locks the collection's row until the surrounding transaction ends
  # and returns it as it is now, or nil if it no longer exists.
  defp lock_collection(collection_id) do
    ProductCollection
    |> where([c], c.id == ^collection_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  @doc """
  Deletes a collection and moves its products to the artist's default
  collection, in one transaction so neither happens without the other.
  For the collection's owner or an admin.

  The default collection itself can't be deleted: returns
  `{:error, :default_collection}`, so works always have somewhere to go.
  """
  def delete_collection(scope, %ProductCollection{} = collection) do
    with_locked_collection(scope, collection.id, [:owner, :admin], fn locked ->
      delete_unless_default(locked)
    end)
  end

  defp delete_unless_default(%ProductCollection{is_default: true}) do
    {:error, :default_collection}
  end

  # Runs inside with_locked_collection/4's transaction.
  defp delete_unless_default(%ProductCollection{} = collection) do
    default_id = ensure_default_collection(collection.artist_id)

    from(p in Product, where: p.collection_id == ^collection.id)
    |> Repo.update_all(set: [collection_id: default_id])

    Repo.delete(collection)
  end

  # The id of the artist's default collection. Every artist gets one with
  # their profile, so this only makes one for an artist created some
  # other way; then a deleted collection's works still have somewhere to
  # go instead of ending up in no collection (where the dashboard
  # wouldn't show them).
  defp ensure_default_collection(artist_id) do
    case default_collection_id(artist_id) do
      nil ->
        lock_artist(artist_id)

        %ProductCollection{
          artist_id: artist_id,
          position: next_collection_position(artist_id),
          is_default: true
        }
        |> ProductCollection.changeset(%{name: Artists.default_collection_name()})
        |> Repo.insert!()
        |> Map.fetch!(:id)

      default_id ->
        default_id
    end
  end

  @doc """
  Returns a changeset for tracking collection changes.
  """
  def change_collection(%ProductCollection{} = collection, attrs \\ %{}) do
    ProductCollection.changeset(collection, attrs)
  end

  @doc """
  Swaps the positions of two collections of the same artist, in one
  transaction. Used to reorder collections on the vendor dashboard. For
  the collections' owner or an admin; collections of two different
  artists are refused (`{:error, :unauthorized}`), and
  `{:error, :not_found}` if either was deleted meanwhile.
  """
  def swap_collection_positions(scope, %ProductCollection{} = a, %ProductCollection{} = b) do
    Repo.transact(fn ->
      # Both rows in one statement, in id order, so two swaps at the same
      # moment take turns instead of each waiting for a row the other holds.
      locked =
        ProductCollection
        |> where([c], c.id in ^[a.id, b.id])
        |> order_by([c], asc: c.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      fresh_a = Enum.find(locked, fn collection -> collection.id == a.id end)
      fresh_b = Enum.find(locked, fn collection -> collection.id == b.id end)

      cond do
        is_nil(fresh_a) or is_nil(fresh_b) ->
          {:error, :not_found}

        fresh_a.artist_id != fresh_b.artist_id ->
          {:error, :unauthorized}

        true ->
          with {:ok, _role} <- authorize(scope, fresh_a.artist_id, [:owner, :admin]) do
            {:ok, _} = update_collection_position(fresh_a, fresh_b.position)
            {:ok, _} = update_collection_position(fresh_b, fresh_a.position)
            {:ok, [fresh_a.id, fresh_b.id]}
          end
      end
    end)
  end

  defp update_collection_position(collection, position) do
    collection
    |> ProductCollection.position_changeset(%{position: position})
    |> Repo.update()
  end
end
