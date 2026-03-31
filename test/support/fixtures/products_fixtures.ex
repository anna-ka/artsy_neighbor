defmodule ArtsyNeighbor.ProductsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ArtsyNeighbor.Products` context.
  """

  def product_fixture(attrs \\ %{}) do
    artist = ArtsyNeighbor.ArtistsFixtures.artist_fixture()
    category = ArtsyNeighbor.CategoriesFixtures.category_fixture()

    {:ok, product} =
      attrs
      |> Enum.into(%{
        descr: "some descr",
        details: "some details",
        price: "120.5",
        title: "some title",
        artist_id: artist.id,
        category_id: category.id
      })
      |> ArtsyNeighbor.Products.create_product()

    product
  end

  def product_image_fixture(attrs \\ %{}) do
    product = product_fixture()

    {:ok, product_image} =
      attrs
      |> Enum.into(%{
        path: "some path",
        position: 42,
        product_id: product.id
      })
      |> ArtsyNeighbor.Products.create_product_image()

    product_image
  end

  def product_option_fixture(attrs \\ %{}) do
    product = product_fixture()

    {:ok, product_option} =
      attrs
      |> Enum.into(%{
        descr: "some descr",
        name: "some name",
        values: ["option1", "option2"],
        product_id: product.id
      })
      |> ArtsyNeighbor.Products.create_product_option()

    product_option
  end
end
