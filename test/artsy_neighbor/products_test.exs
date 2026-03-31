defmodule ArtsyNeighbor.ProductsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.{Product, ProductImage, ProductCollection}

  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.CategoriesFixtures

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
      valid_attrs = %{title: "some title", details: "some details", descr: "some descr",
                      price: "120.5", artist_id: artist.id, category_id: category.id}

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
      update_attrs = %{title: "updated title", details: "updated details",
                       descr: "updated description here", price: "456.7"}

      assert {:ok, %Product{} = product} = Products.update_product(product, update_attrs)
      assert product.title == "updated title"
      assert product.price == Decimal.new("456.7")
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = Products.update_product(product, @invalid_attrs)
      assert product.id == Products.get_product!(product.id).id
    end

    test "delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %Product{}} = Products.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset" do
      product = product_fixture()
      assert %Ecto.Changeset{} = Products.change_product(product)
    end
  end

  # ============================================================
  # Product changeset validation
  # ============================================================

  describe "product changeset" do
    setup do
      artist = artist_fixture()
      category = category_fixture()
      valid = %{title: "A nice title", descr: "A good description here", details: "some details",
                price: "50.00", artist_id: artist.id, category_id: category.id}
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
      assert {:error, changeset} = Products.create_product(%{valid | title: String.duplicate("a", 101)})
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
      assert {:ok, _} = Products.create_product(Map.merge(valid, %{units: "in", artist_id: artist2.id}))
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
      assert {:ok, product} = Products.create_product(Map.merge(valid, %{
        width: "30.0", length: "40.0", height: "5.0", materials: "Oil on canvas", unique_work: true
      }))
      assert product.materials == "Oil on canvas"
      assert product.unique_work == true
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

  # ============================================================
  # filter_products/1
  # ============================================================

  describe "filter_products/1" do
    setup do
      artist1 = artist_fixture(%{nickname: "PainterAlice"})
      artist2 = artist_fixture(%{nickname: "SculptorBob"})
      cat_painting = category_fixture(%{name: "Paintings"})
      cat_sculpture = category_fixture(%{name: "Sculpture"})

      p1 = product_fixture(%{title: "Sunset View",  price: "100.0",
                              artist_id: artist1.id, category_id: cat_painting.id})
      p2 = product_fixture(%{title: "Bronze Horse", price: "500.0",
                              artist_id: artist2.id, category_id: cat_sculpture.id})
      p3 = product_fixture(%{title: "Morning Mist", price: "250.0",
                              artist_id: artist1.id, category_id: cat_painting.id})

      %{p1: p1, p2: p2, p3: p3,
        artist1: artist1, artist2: artist2,
        cat_painting: cat_painting, cat_sculpture: cat_sculpture}
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

    test "sort_by price_asc returns cheapest first", %{p1: p1, p2: p2, p3: p3} do
      results = Products.filter_products(%{"sort_by" => "price_asc"})
      ids = Enum.map(results, & &1.id)
      assert Enum.find_index(ids, & &1 == p1.id) <
             Enum.find_index(ids, & &1 == p3.id)
      assert Enum.find_index(ids, & &1 == p3.id) <
             Enum.find_index(ids, & &1 == p2.id)
    end

    test "sort_by price_desc returns most expensive first", %{p1: p1, p2: p2, p3: p3} do
      results = Products.filter_products(%{"sort_by" => "price_desc"})
      ids = Enum.map(results, & &1.id)
      assert Enum.find_index(ids, & &1 == p2.id) <
             Enum.find_index(ids, & &1 == p3.id)
      assert Enum.find_index(ids, & &1 == p3.id) <
             Enum.find_index(ids, & &1 == p1.id)
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

      {:ok, collection} = Products.create_collection(%{
        name: "Summer Series", position: 2, artist_id: artist.id
      })
      uncategorized_collection = artist.id
        |> Products.list_collections_for_artist()
        |> Enum.find(&(&1.name == ArtsyNeighbor.Artists.default_collection_name()))

      p1 = product_fixture(%{title: "In Collection",
                              artist_id: artist.id, category_id: cat1.id,
                              collection_id: collection.id})
      p2 = product_fixture(%{title: "No Collection",
                              artist_id: artist.id, category_id: cat2.id})
      _other = product_fixture(%{artist_id: other_artist.id, category_id: cat1.id})

      %{artist: artist, p1: p1, p2: p2,
        collection: collection, uncategorized: uncategorized_collection,
        cat1: cat1, cat2: cat2}
    end

    test "returns only the given artist's products", %{artist: artist, p1: p1, p2: p2} do
      results = Products.filter_artist_products(artist.id, %{})
      ids = Enum.map(results, & &1.id)
      assert p1.id in ids
      assert p2.id in ids
      assert length(results) == 2
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
      results = Products.filter_artist_products(artist.id, %{"collection_id" => to_string(collection.id)})
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
        Products.create_product_image(%{position: 1, path: "/uploads/a.jpg", product_id: product.id})
      assert Products.get_product_image!(img.id).path == "/uploads/a.jpg"
    end

    test "list_images_for_product returns images ordered by position" do
      product = product_fixture()
      {:ok, img3} = Products.create_product_image(%{position: 3, path: "/c.jpg", product_id: product.id})
      {:ok, img1} = Products.create_product_image(%{position: 1, path: "/a.jpg", product_id: product.id})
      {:ok, img2} = Products.create_product_image(%{position: 2, path: "/b.jpg", product_id: product.id})

      results = Products.list_images_for_product(product.id)
      assert Enum.map(results, & &1.id) == [img1.id, img2.id, img3.id]
    end

    test "list_images_for_product is scoped to the given product" do
      product1 = product_fixture()
      product2 = product_fixture()
      {:ok, img1} = Products.create_product_image(%{position: 1, path: "/a.jpg", product_id: product1.id})
      {:ok, _img2} = Products.create_product_image(%{position: 1, path: "/b.jpg", product_id: product2.id})

      results = Products.list_images_for_product(product1.id)
      assert length(results) == 1
      assert hd(results).id == img1.id
    end

    test "swap_image_positions exchanges position values" do
      product = product_fixture()
      {:ok, img_a} = Products.create_product_image(%{position: 1, path: "/a.jpg", product_id: product.id})
      {:ok, img_b} = Products.create_product_image(%{position: 2, path: "/b.jpg", product_id: product.id})

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
        Products.create_collection(%{name: "Summer Works", position: 2, artist_id: artist.id})
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
      {:ok, _col2} = Products.create_collection(%{name: "Series B", position: 3, artist_id: artist.id})
      {:ok, _col3} = Products.create_collection(%{name: "Series C", position: 2, artist_id: artist.id})

      results = Products.list_collections_for_artist(artist.id)
      positions = Enum.map(results, & &1.position)
      assert positions == Enum.sort(positions)

      names = Enum.map(results, & &1.name)
      assert "Series C" in names
      assert "Series B" in names
      assert Enum.find_index(names, & &1 == "Series C") <
             Enum.find_index(names, & &1 == "Series B")
    end

    test "list_collections_for_artist is scoped to the given artist" do
      artist1 = artist_fixture()
      artist2 = artist_fixture()
      {:ok, _} = Products.create_collection(%{name: "Artist1 Collection", position: 2, artist_id: artist1.id})

      results = Products.list_collections_for_artist(artist2.id)
      names = Enum.map(results, & &1.name)
      refute "Artist1 Collection" in names
    end

    test "delete_collection reassigns its products to the Uncategorized collection" do
      artist = artist_fixture()
      {:ok, target} = Products.create_collection(%{name: "Temporary", position: 2, artist_id: artist.id})
      fallback = Products.list_collections_for_artist(artist.id) |> Enum.find(&(&1.name == ArtsyNeighbor.Artists.default_collection_name()))
      category = category_fixture()

      product = product_fixture(%{artist_id: artist.id, category_id: category.id, collection_id: target.id})

      assert {:ok, _} = Products.delete_collection(target)

      updated = Products.get_product!(product.id)
      assert updated.collection_id == fallback.id
    end

    test "delete_collection sets collection_id to nil when Uncategorized collection is the one being deleted" do
      artist = artist_fixture()
      uncategorized = Products.list_collections_for_artist(artist.id) |> Enum.find(&(&1.name == ArtsyNeighbor.Artists.default_collection_name()))
      category = category_fixture()

      product = product_fixture(%{artist_id: artist.id, category_id: category.id, collection_id: uncategorized.id})

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
      {:ok, collection} = Products.create_collection(%{name: "Old Name", position: 2, artist_id: artist.id})
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
end
