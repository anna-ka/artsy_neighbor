defmodule ArtsyNeighbor.ProductCategory do

  @moduledoc """
  Struct representing a product category in ArtsyNeighbor.
  """

  defstruct [
    :id,
    :title,
    :descr,
    :image
  ]

end


defmodule ArtsyNeighbor.ProductCategories do

  @moduledoc """
  Module for managing product categories in ArtsyNeighbor.
  """

  def list_categories() do
    [
      %ArtsyNeighbor.ProductCategory{
        id: 1,
        title: "Paintings",
        descr: "Beautiful paintings by local artists",
        image: "/images/cat-painting.jpg"
      },
      %ArtsyNeighbor.ProductCategory{
        id: 2,
        title: "Sculptures",
        descr: "Unique sculptures from talented artisans",
        image: "/images/cat-sculpture.jpg"
      },
      %ArtsyNeighbor.ProductCategory{
        id: 4,
        title: "Pottery",
        descr: "Artistic pottery creations",
        image: "/images/pottery-cat.jpg"
      },
      %ArtsyNeighbor.ProductCategory{
        id: 3,
        title: "Jewelry",
        descr: "Handcrafted jewelry pieces",
        image: "/images/cat-jewelry.jpg"
      },
      %ArtsyNeighbor.ProductCategory{
        id: 5,
        title: "Fiber Art",
        descr: "Beautiful textile art and crafts",
        image: "/images/cat-sewing.jpg"
      },
      %ArtsyNeighbor.ProductCategory{
        id: 6,
        title: "Clothing",
        descr: "Unique clothing designs by local designers",
        image: "/images/cat-sewing.jpg"
      },
      %ArtsyNeighbor.ProductCategory{
        id: 7,
        title: "Other Art",
        descr: "Other unique art forms",
        image: "/images/wall_art.jpg"
      }
    ]
  end

end
