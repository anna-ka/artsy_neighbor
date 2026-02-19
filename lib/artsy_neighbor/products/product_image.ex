defmodule ArtsyNeighbor.Products.ProductImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_images" do
    field :path, :string
    field :position, :integer

    belongs_to :product, ArtsyNeighbor.Products.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product_image, attrs) do
    product_image
    |> cast(attrs, [:path, :position, :product_id])
    |> validate_required([:path, :position, :product_id])
  end
end
