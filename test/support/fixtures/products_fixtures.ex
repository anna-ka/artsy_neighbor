defmodule ArtsyNeighbor.ProductsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ArtsyNeighbor.Products` context.
  """

  @doc """
  A product, `:available` unless `attrs` says otherwise.

  Inserted directly (like the seeds), not through
  `Products.create_product/2`: that always makes a draft, and
  publishing needs a photo, but most tests just need an existing
  product for sale. Tests of the photo rule itself use
  `create_product/2`, `publish_product/1` etc.
  """
  def product_fixture(attrs \\ %{}) do
    artist = ArtsyNeighbor.ArtistsFixtures.artist_fixture()
    category = ArtsyNeighbor.CategoriesFixtures.category_fixture()

    attrs = Map.new(attrs)
    # Product.changeset/2 takes neither the status, the owner nor the
    # position, so they are set on the struct instead.
    status = Map.get(attrs, :status, :available)
    artist_id = Map.get(attrs, :artist_id, artist.id)
    position = Map.get(attrs, :position)

    full_attrs =
      Enum.into(Map.drop(attrs, [:status, :artist_id, :position]), %{
        descr: "some descr",
        details: "some details",
        price: "120.5",
        title: "some title",
        category_id: category.id
      })

    %ArtsyNeighbor.Products.Product{status: status, artist_id: artist_id, position: position}
    |> ArtsyNeighbor.Products.Product.changeset(full_attrs)
    |> ArtsyNeighbor.Repo.insert!()
  end

  @doc """
  A photo row of a new product (or of `attrs.product_id`'s). Inserted
  directly, like product_fixture/1; tests of who may add photos use
  `Products.create_product_image/3`.
  """
  def product_image_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    product_id =
      Map.get_lazy(attrs, :product_id, fn ->
        product_fixture().id
      end)

    full_attrs =
      Enum.into(Map.delete(attrs, :product_id), %{
        # An old-style path (starts with "/"), so deleting the row doesn't
        # try to delete files (see Images.delete_files/1).
        path: "/images/some-photo.jpg",
        position: 42
      })

    # The changeset doesn't take the product: it goes on the struct.
    %ArtsyNeighbor.Products.ProductImage{product_id: product_id}
    |> ArtsyNeighbor.Products.ProductImage.changeset(full_attrs)
    |> ArtsyNeighbor.Repo.insert!()
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
