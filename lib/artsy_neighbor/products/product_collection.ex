defmodule ArtsyNeighbor.Products.ProductCollection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_collections" do
    field :name,     :string
    field :position, :integer

    belongs_to :artist, ArtsyNeighbor.Artists.Artist
    has_many :products, ArtsyNeighbor.Products.Product, foreign_key: :collection_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name, :position, :artist_id])
    |> validate_required([:name, :position, :artist_id])
    |> validate_length(:name, min: 1, max: 100)
    |> assoc_constraint(:artist)
  end
end
