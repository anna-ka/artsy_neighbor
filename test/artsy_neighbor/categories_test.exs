defmodule ArtsyNeighbor.CategoriesTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Categories
  alias ArtsyNeighbor.Categories.Category

  import ArtsyNeighbor.CategoriesFixtures

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

    test "get_category!/1 returns the category with given id" do
      category = category_fixture()
      assert Categories.get_category!(category.id) == category
    end

    test "get_category!/1 raises when category does not exist" do
      assert_raise Ecto.NoResultsError, fn -> Categories.get_category!(0) end
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
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :description, "1234567890"))
      assert changeset.valid?
    end

    test "rejects name longer than 100 characters" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :name, String.duplicate("a", 101)))
      assert errors_on(changeset).name != []
    end

    test "accepts name of exactly 100 characters" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :name, String.duplicate("a", 100)))
      assert changeset.valid?
    end

    test "rejects slug longer than 50 characters" do
      changeset = Category.changeset(%Category{}, Map.put(@valid_attrs, :slug, String.duplicate("a", 51)))
      assert errors_on(changeset).slug != []
    end
  end
end
