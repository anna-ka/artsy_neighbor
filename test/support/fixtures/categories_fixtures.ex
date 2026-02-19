defmodule ArtsyNeighbor.CategoriesFixtures do
  @moduledoc """
  Test helpers for creating category entities.
  """

  def unique_category_name, do: "Category #{System.unique_integer([:positive])}"
  def unique_category_slug, do: "category-#{System.unique_integer([:positive])}"

  def category_fixture(attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{
        name: unique_category_name(),
        description: "A valid category description for testing.",
        main_img: "/images/test-category.jpg",
        slug: unique_category_slug()
      })
      |> ArtsyNeighbor.Admin.AdminCategories.create_category()

    category
  end
end
