defmodule ArtsyNeighbor.ProductsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ArtsyNeighbor.Products` context.
  """

  @doc """
  A product, `:available` unless `attrs` says otherwise.

  Inserted directly (like the seeds), not through
  `Products.create_product/1`: that always makes a draft, and
  publishing needs a photo, but most tests just need an existing
  product for sale. Tests of the photo rule itself use
  `create_product/1`, `publish_product/1` etc.
  """
  def product_fixture(attrs \\ %{}) do
    artist = ArtsyNeighbor.ArtistsFixtures.artist_fixture()
    category = ArtsyNeighbor.CategoriesFixtures.category_fixture()

    attrs = Map.new(attrs)
    # Product.changeset/2 doesn't take a status, so it's set on the
    # struct instead.
    status = Map.get(attrs, :status, :available)

    full_attrs =
      Enum.into(Map.delete(attrs, :status), %{
        descr: "some descr",
        details: "some details",
        price: "120.5",
        title: "some title",
        artist_id: artist.id,
        category_id: category.id
      })

    %ArtsyNeighbor.Products.Product{status: status}
    |> ArtsyNeighbor.Products.Product.changeset(full_attrs)
    |> ArtsyNeighbor.Repo.insert!()
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
