defmodule ArtsyNeighbor.Products.ProductOption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product_options" do
    field :name, :string
    field :descr, :string
    field :values, {:array, :string}

    belongs_to :product, ArtsyNeighbor.Products.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product_option, attrs) do
    product_option
    |> cast(attrs, [:name, :descr, :values, :product_id])
    |> validate_required([:name, :descr, :values, :product_id])
  end
end
