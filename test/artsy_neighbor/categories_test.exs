defmodule ArtsyNeighbor.CategoriesTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Categories
  alias ArtsyNeighbor.Categories.Category

  import ArtsyNeighbor.CategoriesFixtures
  import ArtsyNeighbor.ProductsFixtures

  @valid_attrs %{
    name: "Paintings",
    description: "Beautiful paintings by local artists.",
    main_img: "/images/paintings.jpg",
    slug: "paintings"
  }

  describe "read operations" do
    test "list_categories/0 returns all categories" do
      category = category_fixture()
      assert Categories.list_categories() == [category]
    end

    test "list_categories/0 excludes archived categories" do
      active = category_fixture()
      {:ok, archived} = category_fixture() |> Categories.soft_delete_category()

      result = Categories.list_categories()
      assert active in result
      refute archived in result
    end

    test "list_categories_ordered_by_time/0 excludes archived categories" do
      active = category_fixture()
      {:ok, archived} = category_fixture() |> Categories.soft_delete_category()

      result = Categories.list_categories_ordered_by_time()
      assert active in result
      refute archived in result
    end

    test "list_categories_all_status/0 returns categories regardless of status" do
      active = category_fixture()
      {:ok, archived} = category_fixture() |> Categories.soft_delete_category()

      result = Categories.list_categories_all_status()
      assert active in result
      assert archived in result
    end

    test "get_category!/1 returns the category with given id" do
      category = category_fixture()
      assert Categories.get_category!(category.id) == category
    end

    test "get_category!/1 raises when category does not exist" do
      assert_raise Ecto.NoResultsError, fn -> Categories.get_category!(0) end
    end

    test "get_category!/1 returns an archived category too (unscoped)" do
      {:ok, archived} = category_fixture() |> Categories.soft_delete_category()
      assert Categories.get_category!(archived.id) == archived
    end

    test "get_category/1 returns an active category" do
      category = category_fixture()
      assert Categories.get_category(category.id).id == category.id
    end

    test "get_category/1 returns nil for an archived category" do
      {:ok, archived} = category_fixture() |> Categories.soft_delete_category()
      assert Categories.get_category(archived.id) == nil
    end

    test "get_category/1 returns nil for a nonexistent id" do
      assert Categories.get_category(0) == nil
    end
  end

  describe "has_active_products?/1" do
    test "false when the category has no products" do
      category = category_fixture()
      refute Categories.has_active_products?(category)
    end

    test "true when the category has an :available product" do
      category = category_fixture()
      product_fixture(%{category_id: category.id})
      assert Categories.has_active_products?(category)
    end

    test "false when the category's only products are :unavailable/:archived" do
      category = category_fixture()
      product = product_fixture(%{category_id: category.id})
      {:ok, _} = ArtsyNeighbor.Products.soft_delete_product(product)

      refute Categories.has_active_products?(category)
    end
  end

  describe "soft_delete_category/1" do
    test "marks the category as :archived and stamps status_changed_at" do
      category = category_fixture()
      assert category.status == :active
      assert {:ok, updated} = Categories.soft_delete_category(category)
      assert updated.status == :archived
      assert updated.status_changed_at != nil
    end

    test "refuses when the category still has an :available product" do
      category = category_fixture()
      product_fixture(%{category_id: category.id})

      assert Categories.soft_delete_category(category) == {:error, :has_active_products}
      assert Categories.get_category!(category.id).status == :active
    end

    test "succeeds once the category's products are no longer :available" do
      category = category_fixture()
      product = product_fixture(%{category_id: category.id})
      {:ok, _} = ArtsyNeighbor.Products.soft_delete_product(product)

      assert {:ok, updated} = Categories.soft_delete_category(category)
      assert updated.status == :archived
    end
  end

  describe "restore_category/1" do
    test "reverses soft_delete_category/1, marking the category :active again" do
      {:ok, archived} = category_fixture() |> Categories.soft_delete_category()
      assert {:ok, restored} = Categories.restore_category(archived)
      assert restored.status == :active
    end

    test "refuses to restore an already-active category" do
      category = category_fixture()
      assert Categories.restore_category(category) == {:error, :already_active}
    end
  end

  describe "Category changeset - required fields" do
    test "valid changeset with all fields" do
      changeset = Category.changeset(%Category{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires name" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :name, nil))
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires description" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :description, nil))
      assert "can't be blank" in errors_on(changeset).description
    end

    test "requires slug" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, nil))
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "allows main_img to be nil" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :main_img, nil))
      assert changeset.valid?
    end
  end

  describe "Category changeset - slug format" do
    test "accepts lowercase letters and numbers" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "fiber-art2"))
      assert changeset.valid?
    end

    test "accepts hyphens between words" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "fiber-art"))
      assert changeset.valid?
    end

    test "rejects slug with spaces" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "some slug"))
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with uppercase letters" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "Paintings"))
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with leading hyphen" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "-paintings"))
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with trailing hyphen" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "paintings-"))
      assert errors_on(changeset).slug != []
    end

    test "rejects slug with special characters" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, "paint!ngs"))
      assert errors_on(changeset).slug != []
    end
  end

  describe "Category changeset - length validations" do
    test "rejects description shorter than 10 characters" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :description, "Short"))
      assert errors_on(changeset).description != []
    end

    test "accepts description of exactly 10 characters" do
      changeset =
        Category.changeset(%Category{}, Map.put(@valid_attrs, :description, "1234567890"))

      assert changeset.valid?
    end

    test "rejects name longer than 100 characters" do
      changeset =
        Category.changeset(%Category{}, Map.put(@valid_attrs, :name, String.duplicate("a", 101)))

      assert errors_on(changeset).name != []
    end

    test "accepts name of exactly 100 characters" do
      changeset =
        Category.changeset(%Category{}, Map.put(@valid_attrs, :name, String.duplicate("a", 100)))

      assert changeset.valid?
    end

    test "rejects slug longer than 50 characters" do
      changeset =
        Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, String.duplicate("a", 51)))

      assert errors_on(changeset).slug != []
    end
  end
end
