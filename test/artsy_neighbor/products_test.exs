defmodule ArtsyNeighbor.ProductsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Admin.AdminProducts
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

    test "create_product/2 with valid data creates a product" do
      artist = artist_fixture()
      category = category_fixture()

      valid_attrs = %{
        title: "some title",
        details: "some details",
        descr: "some descr",
        price: "120.5",
        category_id: category.id
      }

      assert {:ok, %Product{} = product} =
               Products.create_product(owner_scope(artist), valid_attrs)

      assert product.title == "some title"
      assert product.details == "some details"
      assert product.descr == "some descr"
      assert product.price == Decimal.new("120.5")
    end

    test "create_product/2 with invalid data returns error changeset" do
      artist = artist_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Products.create_product(owner_scope(artist), @invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()

      update_attrs = %{
        title: "updated title",
        details: "updated details",
        descr: "updated description here",
        price: "456.7"
      }

      assert {:ok, %Product{} = product} =
               Products.update_product(owner_scope(product), product, update_attrs)

      assert product.title == "updated title"
      assert product.price == Decimal.new("456.7")
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Products.update_product(owner_scope(product), product, @invalid_attrs)

      assert product.id == Products.get_product!(product.id).id
    end

    test "hard_delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %Product{}} = Products.hard_delete_product(admin_scope_fixture(), product)
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

      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), product)

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

      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), product_a)

      assert Repo.get(Flag, flag_b.id) != nil
    end

    # HardDelete re-reads (and row-locks) the product before deleting it, so
    # a stale struct for an already-deleted product — e.g. the admin clicked
    # "delete" in two tabs — comes back as an error tuple. Before the shared
    # helper, Repo.delete/1 on the stale struct raised Ecto.StaleEntryError.
    test "hard_delete_product/1 returns {:error, :not_found} if the product is already gone" do
      product = product_fixture()
      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), product)

      assert Products.hard_delete_product(admin_scope_fixture(), product) == {:error, :not_found}
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

      assert {:error, {:database_error, message}} =
               Products.hard_delete_product(admin_scope_fixture(), product)

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

      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), product)

      assert Repo.get(ProductReview, review.id) == nil
      assert Repo.get(Flag, flag.id) == nil
    end

    # soft_delete_product/1 — soft, reversible removal (status -> :archived),
    # the vendor-facing counterpart to hard_delete_product/1. Mirrors
    # Artists.soft_delete_artist/1 vs. Artists.hard_delete_artist/1.
    test "soft_delete_product/1 sets status to :archived" do
      product = product_fixture()

      assert {:ok, updated} = Products.soft_delete_product(owner_scope(product), product)
      assert updated.status == :archived
    end

    test "soft_delete_product/1 does not delete the row or affect other fields" do
      product = product_fixture()

      assert {:ok, updated} = Products.soft_delete_product(owner_scope(product), product)
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
      {:ok, archived} = Products.soft_delete_product(owner_scope(product), product)

      assert {:ok, restored} = Products.restore_product(admin_scope_fixture(), archived)
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
      {:ok, _} = Products.soft_delete_product(owner_scope(product), product)
      # soft_delete_artist/1 cascades every one of the artist's products to
      # :archived, overwriting whatever status they were at before.
      {:ok, _} = Artists.soft_delete_artist(artist)
      archived = Products.get_product!(product.id)
      assert archived.status == :archived

      assert {:error, :artist_not_active} =
               Products.restore_product(admin_scope_fixture(), archived)
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

      assert {:error, :artist_not_active} =
               Products.restore_product(admin_scope_fixture(), archived_product)
    end

    test "succeeds (landing on :unavailable) once the vendor has actively re-activated to :active" do
      artist = artist_fixture(%{status: :active})
      artist_image_fixture(artist)
      product = product_fixture(%{artist_id: artist.id})

      {:ok, _} = Artists.soft_delete_artist(artist)
      {:ok, _} = Artists.restore_artist(Artists.get_artist!(artist.id))
      # The vendor's own dashboard "Activate profile".
      {:ok, _} = Artists.activate_artist(Artists.get_artist!(artist.id))

      archived_product = Products.get_product!(product.id)

      assert {:ok, restored_product} =
               Products.restore_product(admin_scope_fixture(), archived_product)

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

      {:ok, _} = Products.soft_delete_product(owner_scope(product), product)
      {:ok, _} = Artists.soft_delete_artist(artist)

      # product_with_stale_artist's :artist association still says :active —
      # the guard must re-check the DB, not trust it.
      assert {:error, :artist_not_active} =
               Products.restore_product(admin_scope_fixture(), product_with_stale_artist)
    end

    # Guards against restoring a product whose category has been deleted
    # out from under it — products.category_id is on_delete: :nilify_all,
    # so AdminCategories.hard_delete_category/1 leaves it nil.
    test "refuses to restore a product whose category no longer exists" do
      artist = artist_fixture(%{status: :active})
      category = category_fixture()
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      {:ok, archived} = Products.soft_delete_product(owner_scope(product), product)

      Repo.delete!(category)
      product_with_nil_category = Products.get_product!(product.id)
      assert product_with_nil_category.category_id == nil

      assert {:error, :category_missing} =
               Products.restore_product(admin_scope_fixture(), archived)
    end

    test "reflects the category's current existence even if the product struct's :category was preloaded before it was deleted" do
      artist = artist_fixture(%{status: :active})
      category = category_fixture()
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      product_with_stale_category = Products.get_product_with_associations_all_status(product.id)
      assert product_with_stale_category.category.id == category.id

      {:ok, _} = Products.soft_delete_product(owner_scope(product), product)
      Repo.delete!(category)

      assert {:error, :category_missing} =
               Products.restore_product(admin_scope_fixture(), product_with_stale_category)
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

    test "requires title, descr, details, price, category_id", %{valid: valid} do
      # (The owner always comes from the scope, so it can't be missing.)
      for field <- [:title, :descr, :details, :price, :category_id] do
        attrs = Map.delete(valid, field)
        assert {:error, changeset} = Products.create_product(owner_scope(valid.artist_id), attrs)
        assert changeset.errors[field], "expected error on #{field}"
      end
    end

    test "Product.changeset/2 requires an owner on the struct", %{valid: valid} do
      changeset = Product.changeset(%Product{}, valid)
      assert changeset.errors[:artist_id]
    end

    test "rejects title shorter than 3 characters", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(owner_scope(valid.artist_id), %{valid | title: "AB"})

      assert changeset.errors[:title]
    end

    test "rejects title longer than 100 characters", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(owner_scope(valid.artist_id), %{
                 valid
                 | title: String.duplicate("a", 101)
               })

      assert changeset.errors[:title]
    end

    test "rejects descr shorter than 10 characters", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(owner_scope(valid.artist_id), %{valid | descr: "short"})

      assert changeset.errors[:descr]
    end

    test "rejects price of zero", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(owner_scope(valid.artist_id), %{valid | price: "0"})

      assert changeset.errors[:price]
    end

    test "rejects negative price", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(owner_scope(valid.artist_id), %{valid | price: "-5.00"})

      assert changeset.errors[:price]
    end

    test "rejects invalid units", %{valid: valid} do
      assert {:error, changeset} =
               Products.create_product(owner_scope(valid.artist_id), Map.put(valid, :units, "mm"))

      assert changeset.errors[:units]
    end

    test "accepts units 'cm' and 'in'", %{valid: valid} do
      assert {:ok, _} =
               Products.create_product(owner_scope(valid.artist_id), Map.put(valid, :units, "cm"))

      artist2 = artist_fixture()

      assert {:ok, _} =
               Products.create_product(owner_scope(artist2), Map.put(valid, :units, "in"))
    end

    test "rejects zero or negative dimensions", %{valid: valid} do
      assert {:error, cs} =
               Products.create_product(owner_scope(valid.artist_id), Map.put(valid, :width, "0"))

      assert cs.errors[:width]

      assert {:error, cs} =
               Products.create_product(
                 owner_scope(valid.artist_id),
                 Map.put(valid, :length, "-1")
               )

      assert cs.errors[:length]

      assert {:error, cs} =
               Products.create_product(owner_scope(valid.artist_id), Map.put(valid, :height, "0"))

      assert cs.errors[:height]
    end

    test "accepts product with optional dimension fields", %{valid: valid} do
      assert {:ok, product} =
               Products.create_product(
                 owner_scope(valid.artist_id),
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
  # list_products_with_associations/0 — backs the dev style guide's
  # samples; its scoping is public-facing all the same.
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
      {:ok, _} = Products.soft_delete_product(owner_scope(product), product)
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

  describe "list_newest_works/1" do
    test "the newest works on the site, by any artist, at most `count`" do
      oldest = product_fixture() |> made_days_ago(30)
      newest = product_fixture() |> made_days_ago(1)
      middle = product_fixture() |> made_days_ago(10)

      ids = Products.list_newest_works(2) |> Enum.map(fn p -> p.id end)
      assert ids == [newest.id, middle.id]

      ids = Products.list_newest_works(8) |> Enum.map(fn p -> p.id end)
      assert ids == [newest.id, middle.id, oldest.id]
    end

    test "leaves out works that aren't for sale" do
      archived = product_fixture()
      {:ok, _} = Products.soft_delete_product(owner_scope(archived), archived)

      assert Products.list_newest_works(8) == []
    end
  end

  describe "list_more_by_artist/2" do
    test "the artist's other works, newest first, at most `count`" do
      artist = artist_fixture()
      shown = product_fixture(%{artist_id: artist.id})
      oldest = product_fixture(%{artist_id: artist.id}) |> made_days_ago(30)
      newest = product_fixture(%{artist_id: artist.id}) |> made_days_ago(1)
      middle = product_fixture(%{artist_id: artist.id}) |> made_days_ago(10)
      _by_someone_else = product_fixture()

      ids = Products.list_more_by_artist(shown, 2) |> Enum.map(fn p -> p.id end)
      assert ids == [newest.id, middle.id]

      ids = Products.list_more_by_artist(shown, 4) |> Enum.map(fn p -> p.id end)
      assert ids == [newest.id, middle.id, oldest.id]
    end

    test "leaves out works that aren't for sale" do
      artist = artist_fixture()
      shown = product_fixture(%{artist_id: artist.id})
      archived = product_fixture(%{artist_id: artist.id})
      {:ok, _} = Products.soft_delete_product(owner_scope(archived), archived)

      assert Products.list_more_by_artist(shown, 4) == []
    end
  end

  describe "get_products_by_artist_all_status/1" do
    test "includes archived and unavailable products" do
      artist = artist_fixture()
      available = product_fixture(%{artist_id: artist.id})
      archived = product_fixture(%{artist_id: artist.id})
      {:ok, _} = Products.soft_delete_product(owner_scope(archived), archived)

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

  describe "list_similar_works/2" do
    test "other artists' works in the same category, newest first, at most `count`" do
      category = category_fixture()
      shown = product_fixture(%{category_id: category.id})
      older = product_fixture(%{category_id: category.id}) |> made_days_ago(20)
      newer = product_fixture(%{category_id: category.id}) |> made_days_ago(2)
      _same_artist = product_fixture(%{artist_id: shown.artist_id, category_id: category.id})
      _other_category = product_fixture()

      ids = Products.list_similar_works(shown, 4) |> Enum.map(fn p -> p.id end)
      assert ids == [newer.id, older.id]

      ids = Products.list_similar_works(shown, 1) |> Enum.map(fn p -> p.id end)
      assert ids == [newer.id]
    end

    test "leaves out works that aren't for sale" do
      category = category_fixture()
      shown = product_fixture(%{category_id: category.id})
      archived = product_fixture(%{category_id: category.id})
      {:ok, _} = Products.soft_delete_product(owner_scope(archived), archived)

      assert Products.list_similar_works(shown, 4) == []
    end

    test "a work without a category (its category was deleted) has none" do
      category = category_fixture()
      _same_category = product_fixture(%{category_id: category.id})
      shown = product_fixture(%{category_id: category.id})

      assert Products.list_similar_works(%{shown | category_id: nil}, 4) == []
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
      {:ok, _} = Products.soft_delete_product(owner_scope(product), product)
      refute Products.get_product_with_associations(product.id)
    end

    test "returns nil for an unavailable product" do
      product = product_fixture(%{status: :unavailable})
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
      {:ok, product} = Products.soft_delete_product(owner_scope(product), product)
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

    # Regression test: the home page's New works shows works without a
    # category, and its "See all new works" leads here.
    test "includes a work without a category, also when searching and sorting",
         %{p1: p1} do
      uncategorized =
        product_fixture(%{title: "Sunset Without Category"})
        |> Ecto.Changeset.change(category_id: nil)
        |> Repo.update!()

      ids = Products.filter_products(%{}) |> Enum.map(fn p -> p.id end)
      assert uncategorized.id in ids

      ids = Products.filter_products(%{"search" => "Sunset"}) |> Enum.map(fn p -> p.id end)
      assert uncategorized.id in ids
      assert p1.id in ids

      ids = Products.filter_products(%{"sort_by" => "category"}) |> Enum.map(fn p -> p.id end)
      assert List.last(ids) == uncategorized.id

      ids = Products.filter_products(%{"sort_by" => "newest"}) |> Enum.map(fn p -> p.id end)
      assert uncategorized.id in ids
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

    # Regression test: the nickname part of the search used to be a bare
    # `or_where`, which in Ecto ORs against the *entire* WHERE clause built
    # so far — so searching by an artist's own nickname bypassed
    # only_available/1 (and any category/artist filter) entirely.
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
    # With the bug, this returned p2 despite the category_id filter.
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
      {:ok, _} = Products.soft_delete_product(owner_scope(archived), archived)

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
        Products.create_collection(owner_scope(artist), %{name: "Summer Series"})

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
    # Shop tab of the artist's public page (ArtistLive.Show).
    test "excludes an archived product", %{artist: artist, p1: p1} do
      {:ok, _} = Products.soft_delete_product(owner_scope(p1), p1)

      results = Products.filter_artist_products(artist.id, %{})
      refute p1.id in Enum.map(results, & &1.id)
    end

    test "excludes an unavailable product", %{artist: artist, p1: p1} do
      {:ok, _} = p1 |> Product.status_changeset(%{status: :unavailable}) |> Repo.update()

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
               Products.create_product_image(owner_scope(product), product, %{
                 position: 1,
                 path: "/uploads/a.jpg"
               })

      assert Products.get_product_image!(img.id).path == "/uploads/a.jpg"
    end

    test "list_images_for_product returns images ordered by position" do
      product = product_fixture()

      {:ok, img3} =
        Products.create_product_image(owner_scope(product), product, %{
          position: 3,
          path: "/c.jpg"
        })

      {:ok, img1} =
        Products.create_product_image(owner_scope(product), product, %{
          position: 1,
          path: "/a.jpg"
        })

      {:ok, img2} =
        Products.create_product_image(owner_scope(product), product, %{
          position: 2,
          path: "/b.jpg"
        })

      results = Products.list_images_for_product(product.id)
      assert Enum.map(results, & &1.id) == [img1.id, img2.id, img3.id]
    end

    test "list_images_for_product is scoped to the given product" do
      product1 = product_fixture()
      product2 = product_fixture()

      {:ok, img1} =
        Products.create_product_image(owner_scope(product1), product1, %{
          position: 1,
          path: "/a.jpg"
        })

      {:ok, _img2} =
        Products.create_product_image(owner_scope(product2), product2, %{
          position: 1,
          path: "/b.jpg"
        })

      results = Products.list_images_for_product(product1.id)
      assert length(results) == 1
      assert hd(results).id == img1.id
    end

    test "swap_image_positions exchanges position values" do
      product = product_fixture()

      {:ok, img_a} =
        Products.create_product_image(owner_scope(product), product, %{
          position: 1,
          path: "/a.jpg"
        })

      {:ok, img_b} =
        Products.create_product_image(owner_scope(product), product, %{
          position: 2,
          path: "/b.jpg"
        })

      assert {:ok, _} = Products.swap_image_positions(owner_scope(img_a), img_a, img_b)

      assert Products.get_product_image!(img_a.id).position == 2
      assert Products.get_product_image!(img_b.id).position == 1
    end

    test "delete_product_image removes it" do
      product_image = product_image_fixture()

      assert {:ok, %ProductImage{}} =
               Products.delete_product_image(owner_scope(product_image), product_image)

      assert_raise Ecto.NoResultsError, fn -> Products.get_product_image!(product_image.id) end
    end

    test "create_product_image/3 with invalid data returns error changeset" do
      product = product_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Products.create_product_image(owner_scope(product), product, @invalid_attrs)
    end
  end

  # ============================================================
  # Publishing and photos: a product can only be :available while
  # it has at least one photo.
  # ============================================================

  describe "publishing and photos" do
    # A product made the way the forms make it: through create_product/2,
    # so it starts as :draft.
    defp draft_product do
      artist = artist_fixture()
      category = category_fixture()

      {:ok, product} =
        Products.create_product(owner_scope(artist), %{
          title: "Draft work",
          descr: "A work that isn't finished yet",
          details: "Details",
          price: "50",
          category_id: category.id
        })

      product
    end

    defp add_photo(product, position \\ 1) do
      {:ok, image} =
        Products.create_product_image(owner_scope(product), product, %{
          path: "/photo-#{position}.jpg",
          position: position
        })

      image
    end

    test "a new product starts as :draft" do
      assert draft_product().status == :draft
    end

    test "create_product/2 ignores a status: a new product is always a draft" do
      artist = artist_fixture()
      category = category_fixture()

      assert {:ok, product} =
               Products.create_product(owner_scope(artist), %{
                 title: "Eager work",
                 descr: "Wants to be for sale at once",
                 details: "Details",
                 price: "50",
                 category_id: category.id,
                 status: :available
               })

      assert product.status == :draft
    end

    test "publish_product/1 refuses a product without photos" do
      product = draft_product()

      assert {:error, :no_photos} = Products.publish_product(owner_scope(product), product)
      assert Products.get_product!(product.id).status == :draft
    end

    test "publish_product/1 makes a draft with a photo :available" do
      product = draft_product()
      add_photo(product)

      assert {:ok, published} = Products.publish_product(owner_scope(product), product)
      assert published.status == :available
    end

    test "publish_product/1 also works from :unavailable" do
      product = product_fixture(%{status: :unavailable})
      add_photo(product)

      assert {:ok, %Product{status: :available}} =
               Products.publish_product(owner_scope(product), product)
    end

    test "publish_product/1 refuses an archived product" do
      product = product_fixture(%{status: :archived})
      add_photo(product)

      assert {:error, :archived} = Products.publish_product(owner_scope(product), product)
    end

    test "publish_product/1 reads the current status, not the given struct's" do
      product = draft_product()
      add_photo(product)
      {:ok, _} = Products.soft_delete_product(owner_scope(product), product)

      # `product` still says :draft, but the database says :archived.
      assert {:error, :archived} = Products.publish_product(owner_scope(product), product)
    end

    test "update_product/2 ignores a status, so it can't skip publish_product/1" do
      # e.g. a hand-made request from the edit form, for an archived
      # product with photos: it must not come back as :available.
      product = product_fixture(%{status: :archived})
      add_photo(product)

      assert {:ok, updated} =
               Products.update_product(owner_scope(product), product, %{
                 status: :available,
                 title: "New title"
               })

      assert updated.title == "New title"
      assert Products.get_product!(product.id).status == :archived
    end

    test "delete_product_image/1 of an already removed photo returns :not_found" do
      product = draft_product()
      image = add_photo(product)
      {:ok, _} = Products.delete_product_image(owner_scope(image), image)

      assert {:error, :not_found} = Products.delete_product_image(owner_scope(image), image)
    end

    test "removing the last photo of an :available product makes it :draft" do
      product = draft_product()
      image = add_photo(product)
      {:ok, product} = Products.publish_product(owner_scope(product), product)

      assert {:ok, %ProductImage{}} = Products.delete_product_image(owner_scope(image), image)
      assert Products.get_product!(product.id).status == :draft
    end

    test "removing one of several photos leaves the product :available" do
      product = draft_product()
      first = add_photo(product, 1)
      add_photo(product, 2)
      {:ok, product} = Products.publish_product(owner_scope(product), product)

      assert {:ok, _} = Products.delete_product_image(owner_scope(first), first)
      assert Products.get_product!(product.id).status == :available
    end

    test "removing the last photo of an :unavailable product leaves it :unavailable" do
      product = product_fixture(%{status: :unavailable})
      image = add_photo(product)

      assert {:ok, _} = Products.delete_product_image(owner_scope(image), image)
      assert Products.get_product!(product.id).status == :unavailable
    end

    test "a draft is not shown to the public" do
      product = draft_product()
      add_photo(product)

      assert Products.get_product_with_associations(product.id) == nil
    end

    test "deactivating the artist leaves drafts alone" do
      product = draft_product()
      artist = Artists.get_artist!(product.artist_id)

      {:ok, _} = Artists.deactivate_artist(artist)
      assert Products.get_product!(product.id).status == :draft
    end
  end

  describe "products without a collection" do
    # The vendor dashboard lists products by collection, so a product
    # without one would be missing there.
    test "create_product/1 puts it in the artist's \"Uncategorized\" collection" do
      artist = artist_fixture()
      category = category_fixture()
      [default_collection] = Products.list_collections_for_artist(artist.id)

      {:ok, product} =
        Products.create_product(owner_scope(artist), %{
          title: "No collection",
          descr: "A work without a collection",
          details: "Details",
          price: "50",
          category_id: category.id
        })

      assert default_collection.name == "Uncategorized"
      assert product.collection_id == default_collection.id
    end

    test "update_product/2 puts it back there when the collection is cleared" do
      artist = artist_fixture()
      [default_collection] = Products.list_collections_for_artist(artist.id)

      {:ok, other} =
        Products.create_collection(owner_scope(artist), %{name: "Watercolours"})

      product = product_fixture(%{artist_id: artist.id, collection_id: other.id})

      {:ok, updated} =
        Products.update_product(owner_scope(product), product, %{collection_id: nil})

      assert updated.collection_id == default_collection.id
    end

    test "a chosen collection is kept" do
      artist = artist_fixture()

      {:ok, other} =
        Products.create_collection(owner_scope(artist), %{name: "Watercolours"})

      product = product_fixture(%{artist_id: artist.id, collection_id: other.id})

      {:ok, updated} = Products.update_product(owner_scope(product), product, %{title: "Renamed"})
      assert updated.collection_id == other.id
    end
  end

  # Audit S-3: a work belongs to one artist, and can only be in that
  # artist's collections.
  describe "a product's owner and collection" do
    setup do
      artist = artist_fixture()
      other_artist = artist_fixture()

      {:ok, other_collection} =
        Products.create_collection(owner_scope(other_artist), %{name: "Someone else's oils"})

      %{
        artist: artist,
        other_artist: other_artist,
        other_collection: other_collection,
        category: category_fixture()
      }
    end

    defp work_attrs(category) do
      %{
        title: "Kelp forest",
        descr: "A linocut of a kelp forest",
        details: "Printed on washi paper",
        price: "90",
        category_id: category.id
      }
    end

    test "create_product/2 ignores an artist_id in the attrs", %{
      artist: artist,
      other_artist: other_artist,
      category: category
    } do
      attrs = Map.put(work_attrs(category), :artist_id, other_artist.id)
      {:ok, product} = Products.create_product(owner_scope(artist), attrs)
      assert product.artist_id == artist.id
    end

    test "update_product/2 ignores an artist_id in the attrs", %{
      artist: artist,
      other_artist: other_artist
    } do
      product = product_fixture(%{artist_id: artist.id})

      {:ok, updated} =
        Products.update_product(owner_scope(product), product, %{artist_id: other_artist.id})

      assert updated.artist_id == artist.id
    end

    test "create_product/2 refuses another artist's collection", %{
      artist: artist,
      other_collection: other_collection,
      category: category
    } do
      attrs = Map.put(work_attrs(category), :collection_id, other_collection.id)

      assert {:error, changeset} = Products.create_product(owner_scope(artist), attrs)
      assert changeset.errors[:collection_id]
      assert Products.get_products_by_artist_all_status(artist.id) == []
    end

    test "update_product/2 refuses another artist's collection, or one that doesn't exist", %{
      artist: artist,
      other_collection: other_collection
    } do
      product = product_fixture(%{artist_id: artist.id})

      assert {:error, changeset} =
               Products.update_product(owner_scope(product), product, %{
                 collection_id: other_collection.id
               })

      assert changeset.errors[:collection_id]

      assert {:error, changeset} =
               Products.update_product(owner_scope(product), product, %{collection_id: -1})

      assert changeset.errors[:collection_id]
    end

    test "AdminProducts.update_product/3 can move a work to another artist", %{
      artist: artist,
      other_artist: other_artist,
      other_collection: other_collection
    } do
      product = product_fixture(%{artist_id: artist.id})

      {:ok, moved} =
        AdminProducts.update_product(admin_scope_fixture(), product, %{
          artist_id: other_artist.id,
          collection_id: other_collection.id
        })

      assert moved.artist_id == other_artist.id
      assert moved.collection_id == other_collection.id
    end

    test "AdminProducts.update_product/3: a work moved without a collection goes into the new artist's default one",
         %{artist: artist, other_artist: other_artist} do
      {:ok, collection} =
        Products.create_collection(owner_scope(artist), %{name: "Prints"})

      product = product_fixture(%{artist_id: artist.id, collection_id: collection.id})
      other_default = Products.get_collection!(Products.default_collection_id(other_artist.id))

      {:ok, moved} =
        AdminProducts.update_product(admin_scope_fixture(), product, %{artist_id: other_artist.id})

      assert other_default.name == "Uncategorized"
      assert moved.artist_id == other_artist.id
      assert moved.collection_id == other_default.id
    end

    test "AdminProducts.update_product/3 refuses to move a work into another of the old artist's collections",
         %{artist: artist, other_artist: other_artist} do
      {:ok, prints} =
        Products.create_collection(owner_scope(artist), %{name: "Prints"})

      {:ok, oils} =
        Products.create_collection(owner_scope(artist), %{name: "Oils"})

      product = product_fixture(%{artist_id: artist.id, collection_id: prints.id})

      assert {:error, changeset} =
               AdminProducts.update_product(admin_scope_fixture(), product, %{
                 artist_id: other_artist.id,
                 collection_id: oils.id
               })

      assert changeset.errors[:collection_id]
      assert Products.get_product!(product.id).artist_id == artist.id
    end

    # The check runs only for a new work or when the collection or owner
    # changes (an edit that changes neither can't break the rule).
    test "an edit that changes neither the collection nor the owner isn't checked", %{
      artist: artist,
      other_collection: other_collection
    } do
      product = product_fixture(%{artist_id: artist.id})

      # Bad data made directly in the database, which saving refuses.
      Repo.update_all(
        from(p in Product, where: p.id == ^product.id),
        set: [collection_id: other_collection.id]
      )

      product = Products.get_product!(product.id)

      assert {:ok, updated} =
               Products.update_product(owner_scope(product), product, %{price: "75"})

      assert updated.price == Decimal.new("75")
    end

    # Defence in depth: even if another artist's work got into a
    # collection some other way, the collection lists don't show it.
    test "the collection lists leave out works by other artists", %{
      artist: artist,
      other_artist: other_artist,
      other_collection: other_collection
    } do
      intruder = product_fixture(%{artist_id: artist.id, title: "Intruder"})
      own = product_fixture(%{artist_id: other_artist.id, title: "Own work"})

      Repo.update_all(
        from(p in Product, where: p.id in ^[intruder.id, own.id]),
        set: [collection_id: other_collection.id]
      )

      for collections <- [
            Products.list_collections_for_artist(other_artist.id),
            Products.list_public_collections_for_artist(other_artist.id),
            Products.list_collections_for_owner_preview(other_artist.id)
          ] do
        titles = for c <- collections, p <- c.products, do: p.title
        assert "Own work" in titles
        refute "Intruder" in titles
      end
    end
  end

  # ============================================================
  # ProductCollection
  # ============================================================

  describe "product collections" do
    test "create_collection/2 creates a collection for an artist, after their others" do
      artist = artist_fixture()

      assert {:ok, %ProductCollection{} = collection} =
               Products.create_collection(owner_scope(artist), %{name: "Summer Works"})

      assert collection.name == "Summer Works"
      assert collection.artist_id == artist.id
      assert collection.is_default == false
      # The default collection made with the profile is at position 1.
      assert collection.position == 2
    end

    test "Artists.create_artist/1 creates the artist's default collection" do
      artist = artist_fixture()
      [collection] = Products.list_collections_for_artist(artist.id)

      assert collection.is_default
      assert collection.name == ArtsyNeighbor.Artists.default_collection_name()
      assert Products.default_collection_id(artist.id) == collection.id
    end

    test "list_collections_for_artist returns collections ordered by position" do
      artist = artist_fixture()
      {:ok, series_b} = Products.create_collection(owner_scope(artist), %{name: "Series B"})
      {:ok, series_c} = Products.create_collection(owner_scope(artist), %{name: "Series C"})
      {:ok, _} = Products.swap_collection_positions(owner_scope(series_b), series_b, series_c)

      names =
        artist.id
        |> Products.list_collections_for_artist()
        |> Enum.map(fn collection -> collection.name end)

      # The default collection comes last, whatever its position.
      assert names == ["Series C", "Series B", "Uncategorized"]
    end

    test "list_collections_for_artist is scoped to the given artist" do
      artist1 = artist_fixture()
      artist2 = artist_fixture()

      {:ok, _} = Products.create_collection(owner_scope(artist1), %{name: "Artist1 Collection"})

      results = Products.list_collections_for_artist(artist2.id)
      names = Enum.map(results, fn collection -> collection.name end)
      refute "Artist1 Collection" in names
    end

    test "delete_collection reassigns its products to the default collection, even renamed" do
      artist = artist_fixture()
      default_id = Products.default_collection_id(artist.id)

      default = Products.get_collection!(default_id)
      {:ok, _} = Products.update_collection(owner_scope(artist), default, %{name: "Other"})

      {:ok, target} = Products.create_collection(owner_scope(artist), %{name: "Temporary"})
      product = product_fixture(%{artist_id: artist.id, collection_id: target.id})

      assert {:ok, _} = Products.delete_collection(owner_scope(target), target)

      assert Products.get_product!(product.id).collection_id == default_id
    end

    test "delete_collection refuses the default collection, and its works stay in it" do
      artist = artist_fixture()
      default = Products.get_collection!(Products.default_collection_id(artist.id))
      product = product_fixture(%{artist_id: artist.id, collection_id: default.id})

      assert {:error, :default_collection} =
               Products.delete_collection(owner_scope(default), default)

      assert Products.get_collection!(default.id)
      assert Products.get_product!(product.id).collection_id == default.id
    end

    # Every artist gets a default collection with their profile; this is
    # for one made some other way, without one.
    test "delete_collection makes a default collection if the artist has none" do
      artist = artist_fixture()

      Repo.update_all(
        from(c in ProductCollection, where: c.artist_id == ^artist.id),
        set: [is_default: false]
      )

      {:ok, target} = Products.create_collection(owner_scope(artist), %{name: "Temporary"})
      product = product_fixture(%{artist_id: artist.id, collection_id: target.id})

      assert {:ok, _} = Products.delete_collection(owner_scope(target), target)

      new_default = Products.get_collection!(Products.default_collection_id(artist.id))
      assert new_default.name == "Uncategorized"
      assert Products.get_product!(product.id).collection_id == new_default.id
    end

    test "swap_collection_positions exchanges position values" do
      artist = artist_fixture()
      {:ok, col_a} = Products.create_collection(owner_scope(artist), %{name: "A"})
      {:ok, col_b} = Products.create_collection(owner_scope(artist), %{name: "B"})

      assert {:ok, _} = Products.swap_collection_positions(owner_scope(col_a), col_a, col_b)

      assert Products.get_collection!(col_a.id).position == col_b.position
      assert Products.get_collection!(col_b.id).position == col_a.position
    end

    test "update_collection changes collection attributes" do
      artist = artist_fixture()
      {:ok, collection} = Products.create_collection(owner_scope(artist), %{name: "Old Name"})

      assert {:ok, updated} =
               Products.update_collection(owner_scope(collection), collection, %{name: "New Name"})

      assert updated.name == "New Name"
    end
  end

  # Audit S-4: a collection's owner, position and default flag are set
  # by the server; only the name comes from a form.
  describe "a collection's owner and default flag" do
    setup do
      %{artist: artist_fixture(), other_artist: artist_fixture()}
    end

    test "create_collection/2 takes only the name from the attrs", %{
      artist: artist,
      other_artist: other_artist
    } do
      {:ok, collection} =
        Products.create_collection(owner_scope(artist), %{
          name: "Prints",
          artist_id: other_artist.id,
          position: 99,
          is_default: true
        })

      assert collection.artist_id == artist.id
      assert collection.position == 2
      refute collection.is_default
    end

    test "update_collection/2 takes only the name from the attrs", %{
      artist: artist,
      other_artist: other_artist
    } do
      {:ok, collection} = Products.create_collection(owner_scope(artist), %{name: "Prints"})

      {:ok, updated} =
        Products.update_collection(owner_scope(collection), collection, %{
          name: "Linocuts",
          artist_id: other_artist.id,
          position: 99,
          is_default: true
        })

      assert updated.name == "Linocuts"
      assert updated.artist_id == artist.id
      assert updated.position == collection.position
      refute updated.is_default
    end

    test "a renamed default collection still takes works with no collection", %{
      artist: artist
    } do
      default = Products.get_collection!(Products.default_collection_id(artist.id))

      {:ok, _} =
        Products.update_collection(owner_scope(default), default, %{name: "Odds and ends"})

      {:ok, product} =
        Products.create_product(owner_scope(artist), %{
          title: "Small study",
          descr: "A small study in oils",
          details: "Unframed",
          price: "40",
          category_id: category_fixture().id
        })

      assert product.collection_id == default.id
    end

    # Before is_default, a second "Uncategorized" made every
    # delete_collection/1 crash (Ecto.MultipleResultsError).
    test "a second collection named Uncategorized is an ordinary one", %{artist: artist} do
      default_id = Products.default_collection_id(artist.id)
      {:ok, second} = Products.create_collection(owner_scope(artist), %{name: "Uncategorized"})
      {:ok, other} = Products.create_collection(owner_scope(artist), %{name: "Prints"})

      refute second.is_default
      assert {:ok, _} = Products.delete_collection(owner_scope(other), other)
      assert {:ok, _} = Products.delete_collection(owner_scope(second), second)
      assert Products.default_collection_id(artist.id) == default_id
    end

    test "an artist can't have two default collections", %{artist: artist} do
      result =
        %ProductCollection{artist_id: artist.id, position: 5, is_default: true}
        |> ProductCollection.changeset(%{name: "Second default"})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert changeset.errors[:artist_id]
    end
  end

  # ============================================================
  # swap_product_positions/3
  # ============================================================

  describe "swap_product_positions/3" do
    # A work in the artist's default collection, as the site makes them.
    defp work_in_default(artist, attrs) do
      collection_id = Products.default_collection_id(artist.id)
      product_fixture(Map.merge(%{artist_id: artist.id, collection_id: collection_id}, attrs))
    end

    defp positions(works) do
      Enum.map(works, fn work -> Products.get_product!(work.id).position end)
    end

    test "exchanges two works' places in their collection" do
      artist = artist_fixture()
      p1 = work_in_default(artist, %{position: 1})
      p2 = work_in_default(artist, %{position: 2})

      assert {:ok, _} = Products.swap_product_positions(owner_scope(p1), p1, p2)
      assert positions([p1, p2]) == [2, 1]
    end

    # New works have no position, so swapping the stored numbers alone
    # did nothing (code review, 2026-11-23).
    test "works without positions are numbered in the dashboard's order first" do
      artist = artist_fixture()
      a = work_in_default(artist, %{title: "Apple"})
      b = work_in_default(artist, %{title: "banana"})
      c = work_in_default(artist, %{title: "Cherry"})

      # Shown by title while none has a position: Apple, banana, Cherry
      # (the database's order, which ignores case).
      assert {:ok, _} = Products.swap_product_positions(owner_scope(a), b, c)
      assert positions([a, b, c]) == [1, 3, 2]
    end

    test "works with the same position (e.g. from a deleted collection) move too" do
      artist = artist_fixture()
      a = work_in_default(artist, %{title: "Apple", position: 1})
      b = work_in_default(artist, %{title: "Banana", position: 1})

      assert {:ok, _} = Products.swap_product_positions(owner_scope(a), a, b)
      assert positions([a, b]) == [2, 1]
    end

    test "nothing changes if the other work has moved to another collection" do
      artist = artist_fixture()
      a = work_in_default(artist, %{position: 1})
      b = work_in_default(artist, %{position: 2})
      {:ok, prints} = Products.create_collection(owner_scope(artist), %{name: "Prints"})
      {:ok, _moved} = Products.update_product(owner_scope(b), b, %{collection_id: prints.id})

      assert {:ok, _} = Products.swap_product_positions(owner_scope(a), a, b)
      assert positions([a, b]) == [1, 2]
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

  # ---------------------------------------------------------------------------
  # Who may act (2026-11-23)
  #
  # The Products functions that change works, photos and collections work
  # out the caller's role from their scope ("Who is acting" in
  # products.ex). These tests call them as the wrong person and check both
  # the refusal and that nothing changed. (The tests above act as the
  # owner, or as an admin for the admin-only functions.)
  # ---------------------------------------------------------------------------

  # An artist with two collections, two draft works in the first one, and
  # two photos on the first work: enough for every function to succeed
  # when the right person calls it.
  defp owned_things do
    artist = artist_fixture()
    {:ok, prints} = Products.create_collection(owner_scope(artist), %{name: "Prints"})
    {:ok, oils} = Products.create_collection(owner_scope(artist), %{name: "Oils"})

    work =
      product_fixture(%{
        artist_id: artist.id,
        collection_id: prints.id,
        position: 1,
        status: :draft
      })

    other_work =
      product_fixture(%{artist_id: artist.id, collection_id: prints.id, position: 2})

    photo_a = product_image_fixture(%{product_id: work.id, position: 1})
    photo_b = product_image_fixture(%{product_id: work.id, position: 2})

    %{
      artist: artist,
      work: work,
      other_work: other_work,
      photo_a: photo_a,
      photo_b: photo_b,
      prints: prints,
      oils: oils
    }
  end

  # Calls every function that changes one of those things, as this scope,
  # and returns the results by function name. A keyword list, so they
  # run in this order: the ones that need a photo or collection still
  # there come before the ones that delete it. (Creating works and
  # collections is tested on its own: it acts on the caller's own
  # profile, so another artist would simply succeed.)
  defp try_everything(scope, things) do
    [
      update_product: Products.update_product(scope, things.work, %{title: "Changed"}),
      publish_product: Products.publish_product(scope, things.work),
      swap_product_positions:
        Products.swap_product_positions(scope, things.work, things.other_work),
      create_product_image:
        Products.create_product_image(scope, things.work, %{path: "/added.jpg", position: 3}),
      swap_image_positions: Products.swap_image_positions(scope, things.photo_a, things.photo_b),
      delete_product_image: Products.delete_product_image(scope, things.photo_a),
      update_collection: Products.update_collection(scope, things.prints, %{name: "Changed"}),
      swap_collection_positions:
        Products.swap_collection_positions(scope, things.prints, things.oils),
      delete_collection: Products.delete_collection(scope, things.prints),
      soft_delete_product: Products.soft_delete_product(scope, things.work),
      restore_product: Products.restore_product(scope, things.work)
    ]
  end

  # The parts of those things that any of the functions would change.
  defp state_of(things) do
    work = Repo.get!(Product, things.work.id)

    photos =
      Repo.all(
        from(i in ProductImage,
          where: i.product_id == ^things.work.id,
          order_by: i.id,
          select: {i.path, i.position}
        )
      )

    collections =
      Repo.all(
        from(c in ProductCollection,
          where: c.artist_id == ^things.artist.id,
          order_by: c.id,
          select: {c.name, c.position}
        )
      )

    %{
      work: {work.title, work.status, work.position, work.collection_id},
      other_work_position: Repo.get!(Product, things.other_work.id).position,
      photos: photos,
      collections: collections
    }
  end

  describe "who may act" do
    test "anyone but the owner or an admin is refused everything, and nothing changes" do
      things = owned_things()
      before = state_of(things)

      # Another artist, a logged-in user without a profile, and a
      # logged-out visitor (no scope at all).
      other_artist = owner_scope(artist_fixture())
      plain_user = user_scope_fixture()

      for scope <- [other_artist, plain_user, nil] do
        for {function, result} <- try_everything(scope, things) do
          assert {function, result} == {function, {:error, :unauthorized}}
        end

        assert Products.hard_delete_product(scope, things.work) == {:error, :unauthorized}
      end

      assert state_of(things) == before
    end

    test "an artist whose profile was removed can't change their works or collections" do
      things = owned_things()
      # Made before the removal, like a page that was already open: the
      # status is read from the database, not from the scope.
      scope = owner_scope(things.artist)
      {:ok, _removed} = Artists.soft_delete_artist(things.artist)
      before = state_of(things)

      for {function, result} <- try_everything(scope, things) do
        assert {function, result} == {function, {:error, :artist_removed}}
      end

      assert Products.create_product(scope, %{title: "New"}) == {:error, :artist_removed}
      assert Products.create_collection(scope, %{name: "New"}) == {:error, :artist_removed}
      assert state_of(things) == before
    end

    test "an artist whose profile is only inactive can still change their works" do
      things = owned_things()
      {:ok, _inactive} = Artists.deactivate_artist(things.artist)
      results = try_everything(owner_scope(things.artist), things)

      # Restoring an archived work has its own rule: it needs an
      # :active artist (restore_product/2).
      {restore_result, others} = Keyword.pop(results, :restore_product)
      assert restore_result == {:error, :artist_not_active}

      for {function, result} <- others do
        assert {function, match?({:ok, _}, result)} == {function, true}
      end
    end

    test "an admin may do everything" do
      things = owned_things()

      for {function, result} <- try_everything(admin_scope_fixture(), things) do
        assert {function, match?({:ok, _}, result)} == {function, true}
      end

      assert {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), things.work)
    end

    test "the owner can't hard delete a work; they archive it instead" do
      things = owned_things()

      assert Products.hard_delete_product(owner_scope(things.work), things.work) ==
               {:error, :unauthorized}

      assert Repo.get(Product, things.work.id)
    end

    test "works and collections can only be created for the caller's own profile" do
      category = category_fixture()
      attrs = %{title: "A new work", descr: "Some descr", details: "Details", price: "10"}
      attrs = Map.put(attrs, :category_id, category.id)

      # No artist profile: a plain user, an admin (who uses
      # AdminProducts instead), a logged-out visitor.
      for scope <- [user_scope_fixture(), admin_scope_fixture(), nil] do
        assert Products.create_product(scope, attrs) == {:error, :unauthorized}
        assert Products.create_collection(scope, %{name: "Prints"}) == {:error, :unauthorized}
      end
    end

    test "a swap refuses things of two different artists, or photos of two works" do
      things = owned_things()
      theirs = owned_things()
      scope = owner_scope(things.artist)
      before = state_of(things)

      assert Products.swap_product_positions(scope, things.work, theirs.work) ==
               {:error, :unauthorized}

      assert Products.swap_collection_positions(scope, things.prints, theirs.prints) ==
               {:error, :unauthorized}

      # Both works are this artist's, but the photos belong to different works.
      photo_of_other_work = product_image_fixture(%{product_id: things.other_work.id})

      assert Products.swap_image_positions(scope, things.photo_a, photo_of_other_work) ==
               {:error, :unauthorized}

      assert state_of(things) == before
    end

    test "AdminProducts refuses anyone but an admin" do
      things = owned_things()
      owner = owner_scope(things.artist)
      category = category_fixture()

      attrs = %{
        title: "A new work",
        descr: "Some descr",
        details: "Details",
        price: "10",
        category_id: category.id,
        artist_id: things.artist.id
      }

      for scope <- [owner, user_scope_fixture(), nil] do
        assert AdminProducts.create_product(scope, attrs) == {:error, :unauthorized}

        assert AdminProducts.update_product(scope, things.work, %{title: "Changed"}) ==
                 {:error, :unauthorized}
      end

      assert Repo.get!(Product, things.work.id).title == things.work.title
    end
  end

  # The page passes in the struct it loaded, which may be out of date.
  # The checks use the row as it is now (code review, 2026-11-23).
  describe "changes check the database, not the page's copy" do
    test "the old owner can't change a work an admin has moved to another artist" do
      things = owned_things()
      new_owner = artist_fixture()
      old_owner = owner_scope(things.artist)
      # The page's copy still says it's the old owner's.
      stale = things.work

      {:ok, _moved} =
        AdminProducts.update_product(admin_scope_fixture(), things.work, %{
          artist_id: new_owner.id
        })

      assert Products.update_product(old_owner, stale, %{title: "Mine"}) ==
               {:error, :unauthorized}

      assert Products.publish_product(old_owner, stale) == {:error, :unauthorized}
      assert Products.soft_delete_product(old_owner, stale) == {:error, :unauthorized}
      assert Products.delete_product_image(old_owner, things.photo_a) == {:error, :unauthorized}

      assert Products.swap_image_positions(old_owner, things.photo_a, things.photo_b) ==
               {:error, :unauthorized}

      work = Repo.get!(Product, things.work.id)
      assert work.title == things.work.title
      assert work.status == :draft
    end

    test "the new owner can, with the old copy" do
      things = owned_things()
      new_owner = artist_fixture()
      stale = things.work

      {:ok, _moved} =
        AdminProducts.update_product(admin_scope_fixture(), things.work, %{
          artist_id: new_owner.id
        })

      assert {:ok, updated} =
               Products.update_product(owner_scope(new_owner), stale, %{title: "Ours"})

      assert updated.title == "Ours"
      assert updated.artist_id == new_owner.id
    end

    test "something deleted meanwhile gives :not_found, not a crash" do
      things = owned_things()
      scope = owner_scope(things.artist)
      {:ok, _} = Products.delete_collection(scope, things.oils)

      assert Products.update_collection(scope, things.oils, %{name: "Gone"}) ==
               {:error, :not_found}

      assert Products.delete_collection(scope, things.oils) == {:error, :not_found}

      assert Products.swap_collection_positions(scope, things.prints, things.oils) ==
               {:error, :not_found}

      {:ok, _} = Products.delete_product_image(scope, things.photo_b)

      assert Products.swap_image_positions(scope, things.photo_a, things.photo_b) ==
               {:error, :not_found}

      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), things.work)

      assert Products.update_product(scope, things.work, %{title: "Gone"}) == {:error, :not_found}
      assert Products.publish_product(scope, things.work) == {:error, :not_found}
      assert Products.soft_delete_product(scope, things.work) == {:error, :not_found}
      assert Products.restore_product(scope, things.work) == {:error, :not_found}
      assert Products.delete_product_image(scope, things.photo_a) == {:error, :not_found}

      assert Products.create_product_image(scope, things.work, %{path: "/x.jpg", position: 1}) ==
               {:error, :not_found}

      assert Products.swap_product_positions(scope, things.work, things.other_work) ==
               {:error, :not_found}
    end
  end

  describe "get_own_product/2 and get_own_collection/2" do
    test "find the artist's own work or collection, and nothing else" do
      things = owned_things()
      theirs = owned_things()
      scope = owner_scope(things.artist)

      assert Products.get_own_product(scope, things.work.id).id == things.work.id
      assert Products.get_own_collection(scope, things.prints.id).id == things.prints.id

      # Someone else's, a forged id that parse_id/1 made nil, a missing
      # one, and an admin (who has no profile: admins use the admin pages).
      assert Products.get_own_product(scope, theirs.work.id) == nil
      assert Products.get_own_collection(scope, theirs.prints.id) == nil
      assert Products.get_own_product(scope, nil) == nil
      assert Products.get_own_product(scope, -1) == nil
      assert Products.get_own_product(admin_scope_fixture(), things.work.id) == nil
      assert Products.get_own_collection(nil, things.prints.id) == nil
    end

    test "get_own_product/2 loads the photos, in order" do
      things = owned_things()
      product = Products.get_own_product(owner_scope(things.artist), things.work.id)

      assert Enum.map(product.product_images, fn image -> image.id end) ==
               [things.photo_a.id, things.photo_b.id]
    end
  end

  describe "positions and photos only change through their own functions" do
    test "update_product/3 ignores a position in the params" do
      things = owned_things()

      {:ok, updated} =
        Products.update_product(owner_scope(things.work), things.work, %{position: 99})

      assert updated.position == 1
    end

    test "a photo can't be moved to another work" do
      things = owned_things()

      changeset =
        ProductImage.changeset(things.photo_a, %{product_id: things.other_work.id, position: 5})

      {:ok, updated} = Repo.update(changeset)
      assert updated.product_id == things.work.id
      assert updated.position == 5
    end
  end

  # The scope of the logged-in artist who owns `thing`: an artist (or
  # an artist's id), a work, a collection or a photo. Built with
  # Scope.for_user/1, as for a real visitor, so the tests go through
  # the same checks as the pages ("Who is acting" in Products).
  defp owner_scope(%ArtsyNeighbor.Artists.Artist{} = artist), do: artist_scope_fixture(artist)

  defp owner_scope(artist_id) when is_integer(artist_id) do
    owner_scope(Repo.get!(ArtsyNeighbor.Artists.Artist, artist_id))
  end

  defp owner_scope(%Product{artist_id: artist_id}), do: owner_scope(artist_id)
  defp owner_scope(%ProductCollection{artist_id: artist_id}), do: owner_scope(artist_id)

  defp owner_scope(%ProductImage{product_id: product_id}),
    do: owner_scope(Repo.get!(Product, product_id))

  # Sets when the product was added, `days` ago, so "newest first" can be
  # tested without depending on the order the fixtures were made in.
  defp made_days_ago(product, days) do
    added_at =
      DateTime.utc_now()
      |> DateTime.add(-days, :day)
      |> DateTime.truncate(:second)

    product
    |> Ecto.Changeset.change(inserted_at: added_at)
    |> Repo.update!()
  end
end
