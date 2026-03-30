defmodule ArtsyNeighbor.Artists.ArtistImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "artist_images" do
    field :path, :string
    field :position, :integer

    belongs_to :artist, ArtsyNeighbor.Artists.Artist

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(artist_image, attrs) do
    artist_image
    |> cast(attrs, [:path, :position, :artist_id])
    |> validate_required([:path, :position, :artist_id])
  end
end
