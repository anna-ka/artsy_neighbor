defmodule ArtsyNeighbor.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :title, :string
    field :descr, :string
    field :details, :string
    field :price, :decimal

    field :width,     :decimal
    field :length,    :decimal
    field :height,    :decimal
    field :units,     :string, default: "cm"
    field :materials, :string

    field :position, :integer

    belongs_to :category,   ArtsyNeighbor.Categories.Category
    belongs_to :artist,     ArtsyNeighbor.Artists.Artist
    belongs_to :collection, ArtsyNeighbor.Products.ProductCollection
    has_many :product_images,  ArtsyNeighbor.Products.ProductImage
    has_many :product_options, ArtsyNeighbor.Products.ProductOption

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:title, :descr, :details, :price, :artist_id, :category_id, :collection_id, :position, :width, :length, :height, :units, :materials])
    |> validate_required([:title, :descr, :details, :price, :artist_id, :category_id])
    |> validate_length(:title, min: 3, max: 100,
        min_message: "Title must be at least 3 characters long.",
        max_message: "Title must be at most 100 characters long.")
    |> validate_length(:descr, min: 10, max: 2000,
        min_message: "Description must be at least 10 characters long.",
        max_message: "Description must be at most 2000 characters long.")
    |> validate_number(:price, greater_than: 0, message: "Price must be greater than zero.")
    |> validate_inclusion(:units, ["cm", "in"])
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:length, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
  end
end
