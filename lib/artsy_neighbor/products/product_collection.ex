defmodule ArtsyNeighbor.Products.ProductCollection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_collections" do
    field :name, :string
    field :position, :integer
    # The artist's default collection: works with no other collection go
    # here. Every artist has exactly one, made with the profile
    # (Artists.create_artist/1); it can be renamed but not deleted
    # (Products.delete_collection/2). Set only on the struct, never from
    # params (audit S-4).
    field :is_default, :boolean, default: false

    belongs_to :artist, ArtsyNeighbor.Artists.Artist
    has_many :products, ArtsyNeighbor.Products.Product, foreign_key: :collection_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  The collection's name: the only thing the vendor's forms may change.
  The owner (`artist_id`), the position and `is_default` are set on the
  struct by the server (`Products.create_collection/2`), so a hand-made
  request can't move a collection to another artist (audit S-4). The
  position changes only through `position_changeset/2`.
  """
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name])
    |> validate_required([:name, :position, :artist_id])
    |> validate_length(:name, min: 1, max: 100)
    |> assoc_constraint(:artist)
    |> unique_constraint(:artist_id,
      name: :product_collections_one_default_per_artist,
      message: "already has a default collection"
    )
  end

  @doc """
  Changes only the position, for reordering collections on the vendor
  dashboard (`Products.swap_collection_positions/3`).
  """
  def position_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:position])
    |> validate_required([:position])
  end
end
