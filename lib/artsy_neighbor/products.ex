defmodule ArtsyNeighbor.Product do

  defstruct [
    :id,
    :title,
    :category,
    :subcategory,
    :artist_name,
    :price,
    :image
  ]

end


defmodule ArtsyNeighbor.Products do


  def list_products do
    [
      # Paintings
      %ArtsyNeighbor.Product{
        id: 1,
        title: "Abstract Sunset",
        category: "Paintings",
        subcategory: "Abstract",
        artist_name: "Emma Rodriguez",
        price: 299.99,
        image: "/images/painting.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 2,
        title: "Mountain Serenity",
        category: "Paintings",
        subcategory: "Landscape",
        artist_name: "James Chen",
        price: 349.99,
        image: "/images/ocean-painting.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 3,
        title: "Urban Dreams",
        category: "Paintings",
        subcategory: "Modern",
        artist_name: "Sofia Martinez",
        price: 275.00,
        image: "/images/urban-painting.jpg"
      },

      # Jewelry
      %ArtsyNeighbor.Product{
        id: 4,
        title: "Handcrafted Silver Necklace",
        category: "Jewelry",
        subcategory: "Necklaces",
        artist_name: "Aria Goldstein",
        price: 125.50,
        image: "/images/necklace.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 5,
        title: "Turquoise Statement Piece",
        category: "Jewelry",
        subcategory: "Necklaces",
        artist_name: "Luna Patel",
        price: 189.99,
        image: "/images/necklace.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 6,
        title: "Artisan Beaded Necklace",
        category: "Jewelry",
        subcategory: "Necklaces",
        artist_name: "Maya Johnson",
        price: 95.00,
        image: "/images/necklace.jpg"
      },

      # Pottery/Ceramics
      %ArtsyNeighbor.Product{
        id: 7,
        title: "Handmade Ceramic Mug",
        category: "Pottery",
        subcategory: "Drinkware",
        artist_name: "Oliver Kim",
        price: 35.00,
        image: "/images/mug.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 8,
        title: "Rustic Coffee Mug",
        category: "Pottery",
        subcategory: "Drinkware",
        artist_name: "Ella Thompson",
        price: 42.50,
        image: "/images/mug.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 9,
        title: "Ceramic Cat Sculpture",
        category: "Sculpture",
        subcategory: "Figurines",
        artist_name: "Marcus Williams",
        price: 125.00,
        image: "/images/pottery-cat.jpg"
      },

      # Fiber Art/Clothing
      %ArtsyNeighbor.Product{
        id: 10,
        title: "Hand-Knit Wool Sweater",
        category: "Clothing",
        subcategory: "Sweaters",
        artist_name: "Isabella Garcia",
        price: 145.00,
        image: "/images/sweater.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 11,
        title: "Cozy Cable Knit",
        category: "Clothing",
        subcategory: "Sweaters",
        artist_name: "Noah Anderson",
        price: 165.00,
        image: "/images/sweater.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 12,
        title: "Artisan Cardigan",
        category: "Fiber art",
        subcategory: "Wearables",
        artist_name: "Ava Brown",
        price: 178.50,
        image: "/images/sweater.jpg"
      },

      # More variety
      %ArtsyNeighbor.Product{
        id: 13,
        title: "Sunset Reflection",
        category: "Paintings",
        subcategory: "Impressionist",
        artist_name: "Liam Murphy",
        price: 425.00,
        image: "/images/painting.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 14,
        title: "Silver Moon Necklace",
        category: "Jewelry",
        subcategory: "Necklaces",
        artist_name: "Zoe Roberts",
        price: 215.00,
        image: "/images/necklace.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 15,
        title: "Morning Brew Mug Set",
        category: "Pottery",
        subcategory: "Drinkware",
        artist_name: "Ethan Davis",
        price: 85.00,
        image: "/images/mug.jpg"
      },
      %ArtsyNeighbor.Product{
        id: 16,
        title: "Handwoven Pullover",
        category: "Clothing",
        subcategory: "Sweaters",
        artist_name: "Mia Wilson",
        price: 195.00,
        image: "/images/sweater.jpg"
      }
    ]
  end


  def get_product(id) when is_integer(id) do
    list_products()
    |> Enum.find(fn product -> product.id == id end)
  end

  def get_product(id) when is_binary(id) do
    id |> String.to_integer() |> get_product()
  end

  def get_featured_products(current_product) do
    list_products()
      |> List.delete(current_product)
      |> Enum.take(4)
  end



end
