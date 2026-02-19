defmodule ArtsyNeighbor.Admin.AdminCategoriesTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Admin.AdminCategories
  alias ArtsyNeighbor.Categories.Category

  import ArtsyNeighbor.CategoriesFixtures

  @valid_attrs %{
    name: "Paintings",
    description: "Beautiful paintings by local artists.",
    main_img: "/images/paintings.jpg",
    slug: "paintings"
  }

  @update_attrs %{
    name: "Updated Paintings",
    description: "Updated description for the paintings category.",
    slug: "updated-paintings"
  }

  @invalid_attrs %{name: nil, description: nil, slug: nil}

  describe "list_categories/0" do
    test "returns all categories" do
      category = category_fixture()
      assert AdminCategories.list_categories() == [category]
    end

    test "returns empty list when no categories exist" do
      assert AdminCategories.list_categories() == []
    end
  end

  describe "get_category!/1" do
    test "returns the category with given id" do
      category = category_fixture()
      assert AdminCategories.get_category!(category.id) == category
    end

    test "raises when category does not exist" do
      assert_raise Ecto.NoResultsError, fn -> AdminCategories.get_category!(0) end
    end
  end

  describe "create_category/1" do
    test "with valid data creates a category" do
      assert {:ok, %Category{} = category} = AdminCategories.create_category(@valid_attrs)
      assert category.name == "Paintings"
      assert category.slug == "paintings"
      assert category.description == "Beautiful paintings by local artists."
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = AdminCategories.create_category(@invalid_attrs)
    end

    test "rejects duplicate slug" do
      {:ok, _} = AdminCategories.create_category(@valid_attrs)
      assert {:error, changeset} = AdminCategories.create_category(@valid_attrs)
      assert errors_on(changeset).slug != []
    end

    test "rejects duplicate name" do
      {:ok, _} = AdminCategories.create_category(@valid_attrs)
      attrs_with_different_slug = Map.put(@valid_attrs, :slug, "paintings-2")
      assert {:error, changeset} = AdminCategories.create_category(attrs_with_different_slug)
      assert errors_on(changeset).name != []
    end
  end

  describe "update_category/2" do
    test "with valid data updates the category" do
      category = category_fixture()
      assert {:ok, %Category{} = updated} = AdminCategories.update_category(category, @update_attrs)
      assert updated.name == "Updated Paintings"
      assert updated.slug == "updated-paintings"
    end

    test "with invalid data returns error changeset" do
      category = category_fixture()
      assert {:error, %Ecto.Changeset{}} = AdminCategories.update_category(category, @invalid_attrs)
      assert category == AdminCategories.get_category!(category.id)
    end
  end

  describe "delete_category/1" do
    test "deletes the category" do
      category = category_fixture()
      assert {:ok, %Category{}} = AdminCategories.delete_category(category)
      assert_raise Ecto.NoResultsError, fn -> AdminCategories.get_category!(category.id) end
    end
  end

  describe "change_category/1" do
    test "returns a valid changeset for an existing category" do
      category = category_fixture()
      assert %Ecto.Changeset{valid?: true} = AdminCategories.change_category(category)
    end

    test "returns a changeset with errors for invalid attrs" do
      category = category_fixture()
      changeset = AdminCategories.change_category(category, @invalid_attrs)
      refute changeset.valid?
    end
  end
end
