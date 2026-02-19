defmodule ArtsyNeighbor.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :title, :string
    field :descr, :string
    field :details, :string
    field :price, :decimal

    belongs_to :category, ArtsyNeighbor.Categories.Category
    belongs_to :artist, ArtsyNeighbor.Artists.Artist
    has_many :product_images, ArtsyNeighbor.Products.ProductImage
    has_many :product_options, ArtsyNeighbor.Products.ProductOption

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:title, :descr, :details, :price, :artist_id, :category_id])
    |> validate_required([:title, :descr, :details, :price])
  end
end
