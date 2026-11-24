defmodule ArtsyNeighbor.Products.ProductImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_images" do
    field :path, :string
    field :position, :integer

    belongs_to :product, ArtsyNeighbor.Products.Product

    timestamps(type: :utc_datetime)
  end

  @doc """
  The photo's storage key (`path`) and position. Not `product_id`: the
  work a photo belongs to is set on the struct by the server
  (`Products.create_product_image/3`), so it can't be moved to another
  work.
  """
  def changeset(product_image, attrs) do
    product_image
    |> cast(attrs, [:path, :position])
    |> validate_required([:path, :position, :product_id])
  end

  @doc """
  Changes only the position, for reordering a work's photos
  (`Products.swap_image_positions/3`).
  """
  def position_changeset(product_image, attrs) do
    product_image
    |> cast(attrs, [:position])
    |> validate_required([:position])
  end
end
