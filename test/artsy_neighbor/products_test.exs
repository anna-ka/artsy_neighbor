defmodule ArtsyNeighbor.ProductsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.{Product, ProductImage, ProductCollection}
  alias ArtsyNeighbor.Reviews
  alias ArtsyNeighbor.Reviews.Flag
  alias ArtsyNeighbor.Reviews.ProductReview
  alias ArtsyNeighbor.Orders.OrderItem
  alias ArtsyNeighbor.Repo

  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.CategoriesFixtures
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.OrdersFixtures
  import ArtsyNeighbor.ReviewsFixtures

  # ============================================================
  # Basic CRUD — products
  # ============================================================

  describe "products - basic CRUD" do
    @invalid_attrs %{title: nil, details: nil, descr: nil, price: nil}

    test "list_products/0 returns all products" do
      product = product_fixture()
      result = Products.list_products()
      assert length(result) == 1
      assert hd(result).id == product.id
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert Products.get_product!(product.id).id == product.id
    end

    test "get_product!/1 raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(0) end
    end

    test "create_product/1 with valid data creates a product" do
      artist = artist_fixture()
      category = category_fixture()

      valid_attrs = %{
        title: "some title",
        details: "some details",
        descr: "some descr",
        price: "120.5",
        artist_id: artist.id,
        category_id: category.id
      }

      assert {:ok, %Product{} = product} = Products.create_product(valid_attrs)
      assert product.title == "some title"
      assert product.details == "some details"
      assert product.descr == "some descr"
      assert product.price == Decimal.new("120.5")
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product(@invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()

      update_attrs = %{
        title: "updated title",
        details: "updated details",
        descr: "updated description here",
        price: "456.7"
      }

      assert {:ok, %Product{} = product} = Products.update_product(product, update_attrs)
      assert product.title == "updated title"
      assert product.price == Decimal.new("456.7")
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = Products.update_product(product, @invalid_attrs)
      assert product.id == Products.get_product!(product.id).id
    end

    test "hard_delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %Product{}} = Products.hard_delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(product.id) end
    end

    # Flag.subject_id is a polymorphic reference (no real DB-level FK), so
    # hard_delete_product/1 has to clean up matching flags by hand rather than
    # relying on a cascade — same class of cleanup as
    # Artists.hard_delete_artist/1's flag handling.
    test "hard_delete_product/1 removes flags reporting the product directly" do
      reporter = user_fixture()
      product = product_fixture()

      {:ok, flag} =
        Reviews.create_flag(%{
          subject_type: "product",
          subject_id: product.id,
          reason: "This listing appears to be selling something illegal.",
          reporter_id: reporter.id
        })

      {:ok, _} = Products.hard_delete_product(product)

      assert Repo.get(Flag, flag.id) == nil
    end

    test "hard_delete_product/1 does not remove a flag on a different product" do
      reporter = user_fixture()
      product_a = product_fixture()
      product_b = product_fixture()

      {:ok, flag_b} =
        Reviews.create_flag(%{
          subject_type: "product",
          subject_id: product_b.id,
          reason: "Unrelated flag on a different product entirely.",
          reporter_id: reporter.id
        })

      {:ok, _} = Products.hard_delete_product(product_a)

      assert Repo.get(Flag, flag_b.id) != nil
    end

    # HardDelete re-reads (and row-locks) the product before deleting it, so
    # a stale struct for an already-deleted product — e.g. the admin clicked
    # "delete" in two tabs — comes back as an error tuple. Before the shared
    # helper, Repo.delete/1 on the stale struct raised Ecto.StaleEntryError.
    test "hard_delete_product/1 returns {:error, :not_found} if the product is already gone" do
      product = product_fixture()
      {:ok, _} = Products.hard_delete_product(product)

      assert Products.hard_delete_product(product) == {:error, :not_found}
    end

    # order_items.product_id is on_delete: :nothing. The resulting
    # constraint error is rescued into an error tuple whose text names the
    # blocking constraint — the admin product index shows it in a flash.
    test "hard_delete_product/1 refuses a product that appears in an order" do
      buyer = user_fixture()
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})
      order = order_fixture(%{buyer_id: buyer.id, artist_id: artist.id})

      {:ok, _item} =
        %OrderItem{}
        |> OrderItem.changeset(%{
          order_id: order.id,
          product_id: product.id,
          quantity: 1,
          unit_price: "50.00",
          product_title: product.title
        })
        |> Repo.insert()

      assert {:error, {:database_error, message}} = Products.hard_delete_product(product)
      assert message =~ "order_items_product_id_fkey"
      assert Repo.get(Product, product.id) != nil
    end

    # product_reviews.product_id is on_delete: :delete_all, so the product's
    # reviews go with it — and so must flags reporting those reviews, which
    # would otherwise be left pointing at a deleted review id.
    test "hard_delete_product/1 removes flags reporting the product's reviews" do
      buyer = user_fixture()
      reporter = user_fixture()
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})

      order =
        order_fixture(%{buyer_id: buyer.id, artist_id: artist.id}) |> complete_order(1)

      review =
        product_review_fixture(%{
          order_id: order.id,
          reviewer_id: buyer.id,
          product_id: product.id
        })

      {:ok, flag} =
        Reviews.create_flag(%{
          subject_type: "product_review_of",
          subject_id: review.id,
          reason: "This review looks fake and possibly defamatory.",
          reporter_id: reporter.id
        })

      {:ok, _} = Products.hard_delete_product(product)

      assert Repo.get(ProductReview, review.id) == nil
      assert Repo.get(Flag, flag.id) == nil
    end

    # soft_delete_product/1 — soft, reversible removal (status -> :archived),
    # the vendor-facing counterpart to hard_delete_product/1. Mirrors
    # Artists.soft_delete_artist/1 vs. Artists.hard_delete_artist/1.
    test "soft_delete_product/1 sets status to :archived" do
      product = product_fixture()

      assert {:ok, updated} = Products.soft_delete_product(product)
      assert updated.status == :archived
    end

    test "soft_delete_product/1 does not delete the row or affect other fields" do
      product = product_fixture()

      assert {:ok, updated} = Products.soft_delete_product(product)
      assert updated.id == product.id
      assert updated.title == product.title
      assert Products.get_product!(product.id).status == :archived
    end

    test "change_product/1 returns a product changeset" do
      product = product_fixture()
      assert %Ecto.Changeset{} = Products.change_product(product)
    end

    # restore_product/1 — reverses soft_delete_product/1, but lands on
    # :unavailable, not :available — mirroring Artists.restore_artist/1's
    # own landing on :inactive rather than assuming a product is
    # automatically safe to show the moment it's un-archived. There is
    # currently no separate action that moves a product on from
    # :unavailable to :available — a known, deliberately-left-open gap
    # (see the function's own doc comment).
    test "restore_product/1 sets status to :unavailable, not :available" do
      product = product_fixture()
      {:ok, archived} = Products.soft_delete_product(product)

      assert {:ok, restored} = Products.restore_product(archived)
      assert restored.status == :unavailable
      assert Products.get_product!(product.id).status == :unavailable
    end

    # Guards against restoring a product unless its artist is currently
    # :active — belt-and-suspenders with only_available/1's own
    # independent artist-status check, and gives a more specific error
    # than a silently-empty query result would.
    test "refuses to restore a product whose artist is :removed" do
      artist = artist_fixture(%{status: :active})
      product = product_fixture(%{artist_id: artist.id})
      {:ok, _} = Products.soft_delete_product(product)
      # soft_delete_artist/1 cascades every one of the artist's products to
      # :archived, overwriting whatever status they were at before.
      {:ok, _} = Artists.soft_delete_artist(artist)
      archived = Products.get_product!(product.id)
      assert archived.status == :archived

      assert {:error, :artist_not_active} = Products.restore_product(archived)
    end

    # restore_artist/1 only ever lands on :inactive, never :active (see its
    # own docstring) — so restore_product/1 must keep refusing right after,
    # not just while the artist is still :removed.
    test "still refuses once the artist is restored to :inactive, not yet :active" do
      artist = artist_fixture(%{status: :active})
      product = product_fixture(%{artist_id: artist.id})

      {:ok, _} = Artists.soft_delete_artist(artist)
      assert Products.get_product!(product.id).status == :archived

      {:ok, restored_artist} = Artists.restore_artist(Artists.get_artist!(artist.id))
      assert restored_artist.status == :inactive

      archived_product = Products.get_product!(product.id)
      assert {:error, :artist_not_active} = Products.restore_product(archived_product)
    end

    test "succeeds (landing on :unavailable) once the vendor has actively re-activated to :active" do
      artist = artist_fixture(%{status: :active})
      product = product_fixture(%{artist_id: artist.id})

      {:ok, _} = Artists.soft_delete_artist(artist)
      {:ok, _} = Artists.restore_artist(Artists.get_artist!(artist.id))
      # Simulates the vendor's own dashboard active/inactive toggle, which
      # goes through Artists.update_artist/2, not status_changeset directly.
      {:ok, _} = Artists.update_artist(Artists.get_artist!(artist.id), %{status: :active})

      archived_product = Products.get_product!(product.id)
      assert {:ok, restored_product} = Products.restore_product(archived_product)
      assert restored_product.status == :unavailable
    end

    # Regression test for a preload-staleness bug: without force: true, a
    # product struct fetched *before* the artist's status changed would
    # carry a stale :artist association into the guard check.
    test "reflects the artist's current status even if the product struct's :artist was preloaded before a status change" do
      artist = artist_fixture(%{status: :active})
      product = product_fixture(%{artist_id: artist.id})
      product_with_stale_artist = Products.get_product_with_associations_all_status(product.id)
      assert product_with_stale_artist.artist.status == :active

      {:ok, _} = Products.soft_delete_product(product)
      {:ok, _} = Artists.soft_delete_artist(artist)

      # product_with_stale_artist's :artist association still says :active —
      # the guard must re-check the DB, not trust it.
      assert {:error, :artist_not_active} = Products.restore_product(product_with_stale_artist)
    end

    # Guards against restoring a product whose category has been deleted
    # out from under it — products.category_id is on_delete: :nilify_all,
    # and Category has no soft-delete of its own yet (Phase 3), so this can
    # already happen today via AdminCategories.delete_category/1.
    test "refuses to restore a product whose category no longer exists" do
      artist = artist_fixture(%{status: :active})
      category = category_fixture()
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      {:ok, archived} = Products.soft_delete_product(product)

      Repo.delete!(category)
      product_with_nil_category = Products.get_product!(product.id)
      assert product_with_nil_category.category_id == nil

      assert {:error, :category_missing} = Products.restore_product(archived)
    end

    test "reflects the category's current existence even if the product struct's :category was preloaded before it was deleted" do
      artist = artist_fixture(%{status: :active})
      category = category_fixture()
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      product_with_stale_category = Products.get_product_with_associations_all_status(product.id)
      assert product_with_stale_category.category.id == category.id

      {:ok, _} = Products.soft_delete_product(product)
      Repo.delete!(category)

      assert {:error, :category_missing} = Products.restore_product(product_with_stale_category)
    end
  end

  # ============================================================
  # Product changeset validation
  # ============================================================

  describe "product changeset" do
    setup do
      artist = artist_fixture()
      category = category_fixture()

      valid = %{
        title: "A nice title",
        descr: "A good description here",
        details: "some details",
        price: "50.00",
        artist_id: artist.id,
        category_id: category.id
      }

      %{valid: valid}
    end

    test "requires title, descr, details, price, artist_id, category_id", %{valid: valid} do
      for field <- [:title, :descr, :details, :price, :artist_id, :category_id] do
        attrs = Map.delete(valid, field)
        assert {:error, changeset} = Products.create_product(attrs)
        assert changeset.errors[field], "expected error on #{field}"
      end
    end

    test "rejects title shorter than 3 characters", %{valid: valid} do
      assert {:error, changeset} = Products.create_product(%{valid | title: "AB"})
      assert changeset.errors[:title]
    end

    test "rejects title longer than 100 characters", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(%{valid | title: String.duplicate("a", 101)})

      assert changeset.errors[:title]
    end

    test "rejects descr shorter than 10 characters", %{valid: valid} do
      assert {:error, changeset} = Products.create_product(%{valid | descr: "short"})
      assert changeset.errors[:descr]
    end

    test "rejects price of zero", %{valid: valid} do
      assert {:error, changeset} = Products.create_product(%{valid | price: "0"})
      assert changeset.errors[:price]
    end

    test "rejects negative price", %{valid: valid} do
      assert {:error, changeset} = Products.create_product(%{valid | price: "-5.00"})
      assert changeset.errors[:price]
    end

    test "rejects invalid units", %{valid: valid} do
      assert {:error, changeset} = Products.create_product(Map.put(valid, :units, "mm"))
      assert changeset.errors[:units]
    end

    test "accepts units 'cm' and 'in'", %{valid: valid} do
      assert {:ok, _} = Products.create_product(Map.put(valid, :units, "cm"))
      artist2 = artist_fixture()

      assert {:ok, _} =
               Products.create_product(Map.merge(valid, %{units: "in", artist_id: artist2.id}))
    end

    test "rejects zero or negative dimensions", %{valid: valid} do
      assert {:error, cs} = Products.create_product(Map.put(valid, :width, "0"))
      assert cs.errors[:width]

      assert {:error, cs} = Products.create_product(Map.put(valid, :length, "-1"))
      assert cs.errors[:length]

      assert {:error, cs} = Products.create_product(Map.put(valid, :height, "0"))
      assert cs.errors[:height]
    end

    test "accepts product with optional dimension fields", %{valid: valid} do
      assert {:ok, product} =
               Products.create_product(
                 Map.merge(valid, %{
                   width: "30.0",
                   length: "40.0",
                   height: "5.0",
                   materials: "Oil on canvas",
                   unique_work: true
                 })
               )

      assert product.materials == "Oil on canvas"
      assert product.unique_work == true
    end
  end

  # ============================================================
  # list_products_with_associations/0 — backs the home page's product
  # grid, including "featured products" (Enum.take/2 of this list in
  # HomeLive), so its scoping is public-facing.
  # ============================================================

  describe "list_products_with_associations/0" do
    test "returns available products with associations preloaded" do
      product = product_fixture()
      results = Products.list_products_with_associations()
      result = Enum.find(results, &(&1.id == product.id))
      assert result
      assert %ArtsyNeighbor.Artists.Artist{} = result.artist
    end

    test "excludes an archived product" do
      product = product_fixture()
      {:ok, _} = Products.soft_delete_product(product)
      results = Products.list_products_with_associations()
      refute Enum.any?(results, &(&1.id == product.id))
    end

    # Regression test: same artist-status check as filter_products/1 and
    # get_product_with_associations/1, via the shared only_available/1.
    test "excludes a product whose artist is not :active" do
      artist = artist_fixture(%{status: :active})
      product = product_fixture(%{artist_id: artist.id})
      force_artist_status(artist, :inactive)

      results = Products.list_products_with_associations()
      refute Enum.any?(results, &(&1.id == product.id))
    end
  end

  # ============================================================
  # Querying — by artist / by category
  # ============================================================

  describe "get_products_by_artist/1" do
    test "returns only products belonging to the given artist" do
      artist1 = artist_fixture()
      artist2 = artist_fixture()
      category = category_fixture()

      p1 = product_fixture(%{artist_id: artist1.id, category_id: category.id})
      _p2 = product_fixture(%{artist_id: artist2.id, category_id: category.id})

      results = Products.get_products_by_artist(artist1.id)
      assert length(results) == 1
      assert hd(results).id == p1.id
    end

    test "returns empty list for artist with no products" do
      artist = artist_fixture()
      assert Products.get_products_by_artist(artist.id) == []
    end

    test "excludes archived products — this is exactly the gap get_products_by_artist_all_status/1 exists to fix" do
      artist = artist_fixture()
      product = product_fixture(%{artist_id: artist.id})
      {:ok, _} = Products.soft_delete_product(product)

      assert Products.get_products_by_artist(artist.id) == []
    end
  end

  describe "get_products_by_artist_all_status/1" do
    test "includes archived and unavailable products, unlike get_products_by_artist/1" do
      artist = artist_fixture()
      available = product_fixture(%{artist_id: artist.id})
      archived = product_fixture(%{artist_id: artist.id})
      {:ok, _} = Products.soft_delete_product(archived)

      results = Products.get_products_by_artist_all_status(artist.id)
      ids = Enum.map(results, & &1.id)

      assert available.id in ids
      assert archived.id in ids
    end

    test "is still scoped to the given artist" do
      artist1 = artist_fixture()
      artist2 = artist_fixture()
      p1 = product_fixture(%{artist_id: artist1.id})
      _p2 = product_fixture(%{artist_id: artist2.id})

      results = Products.get_products_by_artist_all_status(artist1.id)
      assert Enum.map(results, & &1.id) == [p1.id]
    end
  end

  describe "get_products_by_category/1" do
    test "returns only products in the given category" do
      artist = artist_fixture()
      cat1 = category_fixture()
      cat2 = category_fixture()

      p1 = product_fixture(%{artist_id: artist.id, category_id: cat1.id})
      _p2 = product_fixture(%{artist_id: artist.id, category_id: cat2.id})

      results = Products.get_products_by_category(cat1.id)
      assert length(results) == 1
      assert hd(results).id == p1.id
    end

    test "returns empty list for category with no products" do
      category = category_fixture()
      assert Products.get_products_by_category(category.id) == []
    end
  end

  describe "get_product_with_associations!/1" do
    test "preloads artist, category, and images" do
      product = product_fixture()
      result = Products.get_product_with_associations!(product.id)
      assert result.id == product.id
      assert %ArtsyNeighbor.Artists.Artist{} = result.artist
      assert %ArtsyNeighbor.Categories.Category{} = result.category
      assert is_list(result.product_images)
    end
  end

  describe "get_product_with_associations/1" do
    test "returns the product when available" do
      product = product_fixture()
      result = Products.get_product_with_associations(product.id)
      assert result.id == product.id
    end

    test "returns nil for an archived product (regression: this used to leak to the public /products/:id page)" do
      product = product_fixture()
      {:ok, _} = Products.soft_delete_product(product)
      refute Products.get_product_with_associations(product.id)
    end

    test "returns nil for an unavailable product" do
      product = product_fixture()
      {:ok, product} = Products.update_product(product, %{status: :unavailable})
      refute Products.get_product_with_associations(product.id)
    end

    test "returns nil for a nonexistent product" do
      refute Products.get_product_with_associations(-1)
    end

    # Regression test: only_available/1 now checks the owning artist's
    # status too, not just the product's own. Uses force_artist_status/2
    # (a raw bypass of every Artists context function, cascades included)
    # to isolate this query-layer check on its own — the product's own
    # status stays :available throughout.
    test "returns nil for an :available product whose artist is not :active, even though the product's own status is untouched" do
      artist = artist_fixture(%{status: :active})
      product = product_fixture(%{artist_id: artist.id})
      assert Products.get_product_with_associations(product.id)

      force_artist_status(artist, :inactive)

      assert Products.get_product!(product.id).status == :available
      refute Products.get_product_with_associations(product.id)
    end
  end

  describe "get_product_with_associations_all_status/1" do
    test "returns an archived product (the admin escape hatch)" do
      product = product_fixture()
      {:ok, product} = Products.soft_delete_product(product)
      result = Products.get_product_with_associations_all_status(product.id)
      assert result.id == product.id
      assert result.status == :archived
    end

    test "returns a product with a nil artist (orphaned by a hard-deleted artist, e.g. via the pre-cascade-migration on_delete: :nilify_all behavior) without raising" do
      product = product_fixture()
      # Simulate the FK's on_delete: :nilify_all nulling the column directly,
      # the same way the DB would — not something create/update_product's
      # changeset would ever allow directly, since artist_id is required there.
      {:ok, product} = product |> Ecto.Changeset.change(artist_id: nil) |> Repo.update()

      result = Products.get_product_with_associations_all_status(product.id)
      assert result.id == product.id
      refute result.artist
    end

    test "returns a product with a nil category (orphaned by a deleted category, products.category_id is on_delete: :nilify_all) without raising" do
      product = product_fixture()
      {:ok, product} = product |> Ecto.Changeset.change(category_id: nil) |> Repo.update()

      result = Products.get_product_with_associations_all_status(product.id)
      assert result.id == product.id
      refute result.category
    end
  end

  # ============================================================
  # filter_products/1
  # ============================================================

  describe "filter_products/1" do
    setup do
      artist1 = artist_fixture(%{nickname: "PainterAlice"})
      artist2 = artist_fixture(%{nickname: "SculptorBob"})
      cat_painting = category_fixture(%{name: "Paintings"})
      cat_sculpture = category_fixture(%{name: "Sculpture"})

      p1 =
        product_fixture(%{
          title: "Sunset View",
          price: "100.0",
          artist_id: artist1.id,
          category_id: cat_painting.id
        })

      p2 =
        product_fixture(%{
          title: "Bronze Horse",
          price: "500.0",
          artist_id: artist2.id,
          category_id: cat_sculpture.id
        })

      p3 =
        product_fixture(%{
          title: "Morning Mist",
          price: "250.0",
          artist_id: artist1.id,
          category_id: cat_painting.id
        })

      %{
        p1: p1,
        p2: p2,
        p3: p3,
        artist1: artist1,
        artist2: artist2,
        cat_painting: cat_painting,
        cat_sculpture: cat_sculpture
      }
    end

    test "empty filter returns all products", %{p1: p1, p2: p2, p3: p3} do
      results = Products.filter_products(%{})
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      assert p2.id in ids
      assert p3.id in ids
    end

    test "filter by category_id returns only that category's products",
         %{p1: p1, p2: p2, p3: p3, cat_painting: cat} do
      results = Products.filter_products(%{"category_id" => to_string(cat.id)})
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      assert p3.id in ids
      refute p2.id in ids
    end

    test "filter by artist nickname returns only that artist's products",
         %{p1: p1, p2: p2, p3: p3, artist1: artist1} do
      results = Products.filter_products(%{"artist" => artist1.nickname})
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      assert p3.id in ids
      refute p2.id in ids
    end

    test "filter by search term matches product title", %{p2: p2} do
      results = Products.filter_products(%{"search" => "Bronze"})
      ids = Enum.map(results, & &1.id)
      assert p2.id in ids
    end

    test "filter by search term matches artist nickname", %{p2: p2} do
      results = Products.filter_products(%{"search" => "SculptorBob"})
      ids = Enum.map(results, & &1.id)
      assert p2.id in ids
    end

    # Regression test: public search must not surface a product whose
    # artist isn't :active, even though the product's own status is
    # untouched — see only_available/1's own artist-status subquery.
    test "excludes a product whose artist is not :active", %{p2: p2, artist2: artist2} do
      force_artist_status(artist2, :inactive)

      results = Products.filter_products(%{})
      ids = Enum.map(results, & &1.id)
      refute p2.id in ids
    end

    # Regression test for a real bug found while reviewing this session's
    # diff: with_artist_search_term/1 used to be a bare `or_where`, which
    # in Ecto ORs against the *entire* accumulated WHERE clause, not just
    # the other search conditions — so searching by an artist's own
    # nickname bypassed only_available/1 (and any category/artist filter)
    # entirely. Confirmed live before the fix: an :inactive artist's
    # :unavailable product was still returned by this exact search.
    test "does NOT surface a product whose artist is not :active, even when searching by that artist's own nickname",
         %{p2: p2, artist2: artist2} do
      force_artist_status(artist2, :inactive)

      results = Products.filter_products(%{"search" => artist2.nickname})
      ids = Enum.map(results, & &1.id)
      refute p2.id in ids
    end

    # Same bug, different symptom: the buggy `or_where` also bypassed
    # with_category/1 whenever a search term happened to match some
    # artist's nickname, regardless of which category was actually being
    # filtered for. p1/p3 (cat_painting, artist1) don't match "SculptorBob"
    # in their own title/category text or artist nickname, and p2 (the
    # only product that does match, via artist2's nickname) isn't in
    # cat_painting — so the correct result for this combination is empty.
    # Before the fix, the category filter was bypassed entirely and this
    # returned p2 despite the category_id filter.
    test "does not bypass an active category filter when the search term matches an unrelated artist's nickname",
         %{p2: p2, cat_painting: cat_painting, artist2: artist2} do
      results =
        Products.filter_products(%{
          "category_id" => to_string(cat_painting.id),
          "search" => artist2.nickname
        })

      ids = Enum.map(results, & &1.id)
      refute p2.id in ids
      assert ids == []
    end

    test "sort_by price_asc returns cheapest first", %{p1: p1, p2: p2, p3: p3} do
      results = Products.filter_products(%{"sort_by" => "price_asc"})
      ids = Enum.map(results, & &1.id)

      assert Enum.find_index(ids, &(&1 == p1.id)) <
               Enum.find_index(ids, &(&1 == p3.id))

      assert Enum.find_index(ids, &(&1 == p3.id)) <
               Enum.find_index(ids, &(&1 == p2.id))
    end

    test "sort_by price_desc returns most expensive first", %{p1: p1, p2: p2, p3: p3} do
      results = Products.filter_products(%{"sort_by" => "price_desc"})
      ids = Enum.map(results, & &1.id)

      assert Enum.find_index(ids, &(&1 == p2.id)) <
               Enum.find_index(ids, &(&1 == p3.id))

      assert Enum.find_index(ids, &(&1 == p3.id)) <
               Enum.find_index(ids, &(&1 == p1.id))
    end
  end

  # ============================================================
  # filter_products_all_status/1 — admin's counterpart to filter_products/1.
  # Without it, an archived product would vanish from the admin list the
  # moment it's archived, with no way to find or restore it.
  # ============================================================

  describe "filter_products_all_status/1" do
    test "includes archived and unavailable products, unlike filter_products/1" do
      artist = artist_fixture()
      category = category_fixture()
      available = product_fixture(%{artist_id: artist.id, category_id: category.id})
      archived = product_fixture(%{artist_id: artist.id, category_id: category.id})
      {:ok, _} = Products.soft_delete_product(archived)

      all_ids = Products.filter_products_all_status(%{}) |> Enum.map(& &1.id)
      available_only_ids = Products.filter_products(%{}) |> Enum.map(& &1.id)

      assert available.id in all_ids
      assert archived.id in all_ids
      assert archived.id not in available_only_ids
    end

    test "still supports the same filters as filter_products/1" do
      artist = artist_fixture(%{nickname: "FilterTestArtist"})
      category = category_fixture()
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})

      results = Products.filter_products_all_status(%{"artist" => "FilterTestArtist"})
      assert Enum.map(results, & &1.id) == [product.id]
    end

    # Same with_search_term/1 fix as filter_products/1's own regression
    # test — a search term matching one artist's nickname must not bypass
    # an active category filter, admin view included.
    test "does not bypass an active category filter when the search term matches an unrelated artist's nickname" do
      artist_a = artist_fixture(%{nickname: "AdminFilterArtistA"})
      artist_b = artist_fixture(%{nickname: "AdminFilterArtistB"})
      cat_a = category_fixture(%{name: "AdminFilterCatA"})
      cat_b = category_fixture(%{name: "AdminFilterCatB"})
      _product_a = product_fixture(%{artist_id: artist_a.id, category_id: cat_a.id})
      product_b = product_fixture(%{artist_id: artist_b.id, category_id: cat_b.id})

      results =
        Products.filter_products_all_status(%{
          "category_id" => to_string(cat_a.id),
          "search" => artist_b.nickname
        })

      ids = Enum.map(results, & &1.id)
      refute product_b.id in ids
      assert ids == []
    end
  end

  # ============================================================
  # filter_artist_products/2
  # ============================================================

  describe "filter_artist_products/2" do
    setup do
      artist = artist_fixture()
      other_artist = artist_fixture()
      cat1 = category_fixture()
      cat2 = category_fixture()

      {:ok, collection} =
        Products.create_collection(%{
          name: "Summer Series",
          position: 2,
          artist_id: artist.id
        })

      uncategorized_collection =
        artist.id
        |> Products.list_collections_for_artist()
        |> Enum.find(&(&1.name == ArtsyNeighbor.Artists.default_collection_name()))

      p1 =
        product_fixture(%{
          title: "In Collection",
          artist_id: artist.id,
          category_id: cat1.id,
          collection_id: collection.id
        })

      p2 = product_fixture(%{title: "No Collection", artist_id: artist.id, category_id: cat2.id})
      _other = product_fixture(%{artist_id: other_artist.id, category_id: cat1.id})

      %{
        artist: artist,
        p1: p1,
        p2: p2,
        collection: collection,
        uncategorized: uncategorized_collection,
        cat1: cat1,
        cat2: cat2
      }
    end

    test "returns only the given artist's products", %{artist: artist, p1: p1, p2: p2} do
      results = Products.filter_artist_products(artist.id, %{})
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      assert p2.id in ids
      assert length(results) == 2
    end

    # Regression test: filter_artist_products/2 used to have no status
    # filter at all, so an :archived product still showed up on the
    # artist's own public store page (ArtistLive.Store).
    test "excludes an archived product", %{artist: artist, p1: p1} do
      {:ok, _} = Products.soft_delete_product(p1)

      results = Products.filter_artist_products(artist.id, %{})
      refute p1.id in Enum.map(results, & &1.id)
    end

    test "excludes an unavailable product", %{artist: artist, p1: p1} do
      {:ok, _} = Products.update_product(p1, %{status: :unavailable})

      results = Products.filter_artist_products(artist.id, %{})
      refute p1.id in Enum.map(results, & &1.id)
    end

    test "filter by category returns only matching products",
         %{artist: artist, p1: p1, p2: p2, cat1: cat1} do
      results = Products.filter_artist_products(artist.id, %{"category_id" => to_string(cat1.id)})
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      refute p2.id in ids
    end

    test "filter by collection returns only products in that collection",
         %{artist: artist, p1: p1, p2: p2, collection: collection} do
      results =
        Products.filter_artist_products(artist.id, %{"collection_id" => to_string(collection.id)})

      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      refute p2.id in ids
    end
  end

  # ============================================================
  # ProductImage
  # ============================================================

  describe "product images" do
    @invalid_attrs %{position: nil, path: nil}

    test "create and retrieve product images" do
      product = product_fixture()

      assert {:ok, %ProductImage{} = img} =
               Products.create_product_image(%{
                 position: 1,
                 path: "/uploads/a.jpg",
                 product_id: product.id
               })

      assert Products.get_product_image!(img.id).path == "/uploads/a.jpg"
    end

    test "list_images_for_product returns images ordered by position" do
      product = product_fixture()

      {:ok, img3} =
        Products.create_product_image(%{position: 3, path: "/c.jpg", product_id: product.id})

      {:ok, img1} =
        Products.create_product_image(%{position: 1, path: "/a.jpg", product_id: product.id})

      {:ok, img2} =
        Products.create_product_image(%{position: 2, path: "/b.jpg", product_id: product.id})

      results = Products.list_images_for_product(product.id)
      assert Enum.map(results, & &1.id) == [img1.id, img2.id, img3.id]
    end

    test "list_images_for_product is scoped to the given product" do
      product1 = product_fixture()
      product2 = product_fixture()

      {:ok, img1} =
        Products.create_product_image(%{position: 1, path: "/a.jpg", product_id: product1.id})

      {:ok, _img2} =
        Products.create_product_image(%{position: 1, path: "/b.jpg", product_id: product2.id})

      results = Products.list_images_for_product(product1.id)
      assert length(results) == 1
      assert hd(results).id == img1.id
    end

    test "swap_image_positions exchanges position values" do
      product = product_fixture()

      {:ok, img_a} =
        Products.create_product_image(%{position: 1, path: "/a.jpg", product_id: product.id})

      {:ok, img_b} =
        Products.create_product_image(%{position: 2, path: "/b.jpg", product_id: product.id})

      assert {:ok, _} = Products.swap_image_positions(img_a, img_b)

      assert Products.get_product_image!(img_a.id).position == 2
      assert Products.get_product_image!(img_b.id).position == 1
    end

    test "delete_product_image removes it" do
      product_image = product_image_fixture()
      assert {:ok, %ProductImage{}} = Products.delete_product_image(product_image)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product_image!(product_image.id) end
    end

    test "create_product_image/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Products.create_product_image(@invalid_attrs)
    end
  end

  # ============================================================
  # ProductCollection
  # ============================================================

  describe "product collections" do
    test "create_collection creates a collection for an artist" do
      artist = artist_fixture()

      assert {:ok, %ProductCollection{} = collection} =
               Products.create_collection(%{
                 name: "Summer Works",
                 position: 2,
                 artist_id: artist.id
               })

      assert collection.name == "Summer Works"
      assert collection.artist_id == artist.id
    end

    test "Artists.create_artist/1 automatically creates an Uncategorized collection" do
      artist = artist_fixture()
      collections = Products.list_collections_for_artist(artist.id)
      assert Enum.any?(collections, &(&1.name == ArtsyNeighbor.Artists.default_collection_name()))
    end

    test "list_collections_for_artist returns collections ordered by position" do
      artist = artist_fixture()
      # The Uncategorized collection is already at position 1 (created by create_artist)
      {:ok, _col2} =
        Products.create_collection(%{name: "Series B", position: 3, artist_id: artist.id})

      {:ok, _col3} =
        Products.create_collection(%{name: "Series C", position: 2, artist_id: artist.id})

      results = Products.list_collections_for_artist(artist.id)
      positions = Enum.map(results, & &1.position)
      assert positions == Enum.sort(positions)

      names = Enum.map(results, & &1.name)
      assert "Series C" in names
      assert "Series B" in names

      assert Enum.find_index(names, &(&1 == "Series C")) <
               Enum.find_index(names, &(&1 == "Series B"))
    end

    test "list_collections_for_artist is scoped to the given artist" do
      artist1 = artist_fixture()
      artist2 = artist_fixture()

      {:ok, _} =
        Products.create_collection(%{
          name: "Artist1 Collection",
          position: 2,
          artist_id: artist1.id
        })

      results = Products.list_collections_for_artist(artist2.id)
      names = Enum.map(results, & &1.name)
      refute "Artist1 Collection" in names
    end

    test "delete_collection reassigns its products to the Uncategorized collection" do
      artist = artist_fixture()

      {:ok, target} =
        Products.create_collection(%{name: "Temporary", position: 2, artist_id: artist.id})

      fallback =
        Products.list_collections_for_artist(artist.id)
        |> Enum.find(&(&1.name == ArtsyNeighbor.Artists.default_collection_name()))

      category = category_fixture()

      product =
        product_fixture(%{
          artist_id: artist.id,
          category_id: category.id,
          collection_id: target.id
        })

      assert {:ok, _} = Products.delete_collection(target)

      updated = Products.get_product!(product.id)
      assert updated.collection_id == fallback.id
    end

    test "delete_collection sets collection_id to nil when Uncategorized collection is the one being deleted" do
      artist = artist_fixture()

      uncategorized =
        Products.list_collections_for_artist(artist.id)
        |> Enum.find(&(&1.name == ArtsyNeighbor.Artists.default_collection_name()))

      category = category_fixture()

      product =
        product_fixture(%{
          artist_id: artist.id,
          category_id: category.id,
          collection_id: uncategorized.id
        })

      assert {:ok, _} = Products.delete_collection(uncategorized)

      updated = Products.get_product!(product.id)
      assert updated.collection_id == nil
    end

    test "swap_collection_positions exchanges position values" do
      artist = artist_fixture()
      {:ok, col_a} = Products.create_collection(%{name: "A", position: 2, artist_id: artist.id})
      {:ok, col_b} = Products.create_collection(%{name: "B", position: 3, artist_id: artist.id})

      assert {:ok, _} = Products.swap_collection_positions(col_a, col_b)

      assert Products.get_collection!(col_a.id).position == 3
      assert Products.get_collection!(col_b.id).position == 2
    end

    test "update_collection changes collection attributes" do
      artist = artist_fixture()

      {:ok, collection} =
        Products.create_collection(%{name: "Old Name", position: 2, artist_id: artist.id})

      assert {:ok, updated} = Products.update_collection(collection, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end

  # ============================================================
  # swap_product_positions/2
  # ============================================================

  describe "swap_product_positions/2" do
    test "exchanges position values between two products" do
      artist = artist_fixture()
      category = category_fixture()
      p1 = product_fixture(%{artist_id: artist.id, category_id: category.id, position: 1})
      p2 = product_fixture(%{artist_id: artist.id, category_id: category.id, position: 2})

      assert {:ok, _} = Products.swap_product_positions(p1, p2)

      assert Products.get_product!(p1.id).position == 2
      assert Products.get_product!(p2.id).position == 1
    end
  end

  # Bypasses every Artists context function (update_artist/2 included,
  # which now cascades an :active -> :inactive transition itself — see
  # Artists.update_artist/2's own doc comment) to simulate artist status
  # changing by some path this test suite doesn't know about. Used only to
  # isolate only_available/1's own independent artist-status check at the
  # query layer, the "defense in depth" half of that invariant, from the
  # cascades that are supposed to keep product rows themselves consistent.
  defp force_artist_status(artist, status) do
    Repo.update_all(
      from(a in ArtsyNeighbor.Artists.Artist, where: a.id == ^artist.id),
      set: [status: Atom.to_string(status)]
    )
  end
end
