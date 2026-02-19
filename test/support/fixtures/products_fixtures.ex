defmodule ArtsyNeighbor.ProductsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ArtsyNeighbor.Products` context.
  """

  @doc """
  Generate a product.
  """
  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      attrs
      |> Enum.into(%{
        descr: "some descr",
        details: "some details",
        price: "120.5",
        title: "some title"
      })
      |> ArtsyNeighbor.Products.create_product()

    product
  end

  @doc """
  Generate a product_image.
  """
  def product_image_fixture(attrs \\ %{}) do
    {:ok, product_image} =
      attrs
      |> Enum.into(%{
        path: "some path",
        position: 42
      })
      |> ArtsyNeighbor.Products.create_product_image()

    product_image
  end

  @doc """
  Generate a product_option.
  """
  def product_option_fixture(attrs \\ %{}) do
    {:ok, product_option} =
      attrs
      |> Enum.into(%{
        descr: "some descr",
        name: "some name",
        values: ["option1", "option2"]
      })
      |> ArtsyNeighbor.Products.create_product_option()

    product_option
  end
end
