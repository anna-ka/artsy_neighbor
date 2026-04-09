defmodule ArtsyNeighbor.OrdersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ArtsyNeighbor.Orders` context.
  """

  @doc """
  Generate a order.
  """
  def order_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        complete_token: "some complete_token",
        complete_token_at: ~U[2026-04-06 19:49:00Z],
        delivery_address: "some delivery_address",
        delivery_method: "some delivery_method",
        platform_fee: "120.5",
        status: "some status",
        subtotal: "120.5",
        total: "120.5"
      })

    {:ok, order} = ArtsyNeighbor.Orders.create_order(scope, attrs)
    order
  end

  @doc """
  Generate a order_item.
  """
  def order_item_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        product_title: "some product_title",
        quantity: 42,
        return_policy_snapshot: "some return_policy_snapshot",
        selected_options: %{},
        unit_price: "120.5"
      })

    {:ok, order_item} = ArtsyNeighbor.Orders.create_order_item(scope, attrs)
    order_item
  end
end
