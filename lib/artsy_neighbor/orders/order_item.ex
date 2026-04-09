defmodule ArtsyNeighbor.Orders.OrderItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_items" do
    field :quantity, :integer
    field :unit_price, :decimal
    field :product_title, :string
    field :return_policy_snapshot, :string
    field :selected_options, :map, default: %{}

    belongs_to :order, ArtsyNeighbor.Orders.Order

    belongs_to :product, ArtsyNeighbor.Products.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [:order_id, :product_id, :quantity, :unit_price, :product_title, :return_policy_snapshot, :selected_options])
    |> validate_required([:order_id, :product_id, :quantity, :unit_price, :product_title])
  end
end
