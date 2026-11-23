defmodule ArtsyNeighborWeb.OrderLive.CompleteTest do
  @moduledoc """
  The buyer's "complete purchase" page, `/orders/:id/complete-purchase/:token`.

  Its two buttons (Complete, Cancel) must act on the order as it is when
  the button is pressed, not as it was when the page opened: the vendor
  may have cancelled the order meanwhile, or the buyer completed it in
  another tab (code review of 2026-11-23).
  """

  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures

  alias ArtsyNeighbor.Accounts.Scope
  alias ArtsyNeighbor.Accounts.User
  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Repo

  # A confirmed order, ready to be completed, and the scopes of its
  # buyer and vendor.
  defp confirmed_order do
    buyer = user_fixture()
    artist = artist_fixture()
    product = product_fixture(artist_id: artist.id)
    {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)
    buyer_scope = Scope.for_user(buyer)
    vendor_scope = Scope.for_user(Repo.get!(User, artist.user_id))

    {:ok, order} =
      Orders.create_order(buyer_scope, conversation, [%{product: product, quantity: 1}])

    {:ok, confirmed} = Orders.confirm_order(vendor_scope, order)

    %{order: confirmed, buyer: buyer, buyer_scope: buyer_scope, vendor_scope: vendor_scope}
  end

  defp open_page(buyer, order) do
    {:ok, view, _html} =
      build_conn()
      |> log_in_user(buyer)
      |> live(~p"/orders/#{order.id}/complete-purchase/#{order.complete_token}")

    view
  end

  test "Complete completes the order" do
    %{order: order, buyer: buyer} = confirmed_order()
    view = open_page(buyer, order)

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("[phx-click='complete_pickup']") |> render_click()

    assert to == ~p"/messages/#{order.conversation_id}"
    assert Orders.get_order!(order.id).status == :completed
  end

  test "Complete does nothing if the vendor cancelled the order after the page opened" do
    %{order: order, buyer: buyer, vendor_scope: vendor_scope} = confirmed_order()
    view = open_page(buyer, order)

    {:ok, _} = Orders.cancel_order(vendor_scope, order)

    view |> element("[phx-click='complete_pickup']") |> render_click()
    {_path, flash} = assert_redirect(view)

    assert flash["error"] =~ "This order has changed (status: cancelled)"
    assert Orders.get_order!(order.id).status == :cancelled
  end

  test "Cancel does nothing if the order was completed (e.g. in another tab) after the page opened" do
    %{order: order, buyer: buyer, buyer_scope: buyer_scope} = confirmed_order()
    view = open_page(buyer, order)

    # complete_pickup/3 needs the order with its artist, as get_order!/1
    # loads it.
    fresh = Orders.get_order!(order.id)
    {:ok, _} = Orders.complete_pickup(buyer_scope, fresh, fresh.complete_token)

    view |> element("[phx-click='cancel_order']") |> render_click()
    {_path, flash} = assert_redirect(view)

    assert flash["error"] =~ "This order has changed (status: completed)"
    assert Orders.get_order!(order.id).status == :completed
  end
end
