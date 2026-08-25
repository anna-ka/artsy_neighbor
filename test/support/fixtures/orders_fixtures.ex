defmodule ArtsyNeighbor.OrdersFixtures do
  @moduledoc """
  Test helpers for creating orders directly (bypassing the cart/checkout
  flow in `ArtsyNeighbor.Orders.create_order/5`, which requires real
  order items). Reviews tests only care about status, completed_at,
  buyer_id, and artist_id.
  """

  alias ArtsyNeighbor.Repo
  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Conversations

  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  def order_fixture(attrs \\ %{}) do
    buyer_id = attrs[:buyer_id] || user_fixture().id
    artist_id = attrs[:artist_id] || artist_fixture().id

    {:ok, conversation} = Conversations.find_or_create_conversation(buyer_id, artist_id)

    {:ok, order} =
      attrs
      |> Enum.into(%{
        status: :requested,
        delivery_method: :pickup,
        subtotal: "100.0",
        platform_fee: "10.0",
        total: "110.0",
        buyer_id: buyer_id,
        artist_id: artist_id,
        conversation_id: conversation.id
      })
      |> then(&Order.changeset(%Order{}, &1))
      |> Repo.insert()

    order
  end

  @doc """
  Marks an order completed at a given number of days in the past.
  `days_ago: 0` means completed just now (inside every window).
  """
  def complete_order(order, days_ago \\ 0) do
    completed_at =
      DateTime.utc_now()
      |> DateTime.add(-days_ago, :day)
      |> DateTime.truncate(:second)

    order
    |> Order.changeset(%{status: :completed, completed_at: completed_at})
    |> Repo.update!()
  end
end
