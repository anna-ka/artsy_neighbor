defmodule ArtsyNeighbor.OrdersTest do
  @moduledoc """
  Tests for the `ArtsyNeighbor.Orders` context — the order state machine and
  its supporting queries.

  ## The state machine

  An order moves through statuses roughly like this:

      :requested --confirm_order--> :confirmed --complete_pickup--> :completed
           |                             |
           +---------cancel_order--------+
                          |
                          v
                      :cancelled

  `:confirmed` has an optional sub-state driven by `pickup_scheduled_at`:
  once a vendor calls `schedule_pickup/2`, the order carries pickup
  date/time/address/instructions and a `complete_token` the buyer needs to
  complete the purchase. `cancel_pickup/2` clears that sub-state without
  changing `status` — the order is still `:confirmed`, just unscheduled again.

  Every mutating function follows the same pattern: one clause with a status
  guard that does the real work, and a catch-all clause returning
  `{:error, :wrong_state}`. These tests exercise both sides of that guard for
  every function, across all four statuses (:requested, :confirmed — with and
  without a scheduled pickup —, :cancelled, :completed) wherever a given
  transition could plausibly be attempted from that status.

  ## The item-amendment rule (session of 2026-08-20)

  `add_item_to_order/3`, `remove_order_item/3`, `increment_order_item/3`, and
  `amend_order/2` all route through the private `do_amend/4`. Until this
  session, amending an order reset its status back to `:requested` and wiped
  `complete_token` — meaning a buyer standing at the vendor's door who wanted
  "just one more piece" would silently invalidate the pickup link the vendor
  had already sent, with no clear signal that anything had broken. `do_amend`
  now leaves `status`, `complete_token`, and all `pickup_*` fields untouched;
  only `subtotal`/`platform_fee`/`total` and the item rows themselves change.
  Several tests below exist specifically to pin this down as a regression
  guard — look for "stays confirmed" / "token preserved" in the test names.
  """

  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Products

  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures

  # ---------------------------------------------------------------------------
  # Test helpers
  #
  # Rather than inserting Order structs directly, these helpers drive orders
  # through the real Orders context functions (create_order, confirm_order,
  # schedule_pickup) — the same functions under test. This means a bug in
  # create_order can't hide behind a hand-built fixture; every test starts
  # from a genuinely-created order.
  # ---------------------------------------------------------------------------

  # Sets up a buyer, artist (with its own user), and a $50 product, then
  # creates a :requested order for one unit of it. Returns a map with
  # everything a test might need so call sites can pattern-match just the
  # keys they care about, e.g. `%{order: order, buyer: buyer} = new_order()`.
  defp new_order(attrs \\ %{}) do
    buyer = attrs[:buyer] || user_fixture()
    artist = attrs[:artist] || artist_fixture()

    product =
      attrs[:product] || product_fixture(artist_id: artist.id, price: attrs[:price] || "50.00")

    quantity = attrs[:quantity] || 1

    {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

    {:ok, order} =
      Orders.create_order(conversation, buyer, artist, [%{product: product, quantity: quantity}])

    %{order: order, buyer: buyer, artist: artist, product: product, conversation: conversation}
  end

  # Advances a :requested order to :confirmed.
  defp confirm!(order) do
    {:ok, confirmed} = Orders.confirm_order(order)
    confirmed
  end

  # Schedules a pick-up on a :confirmed order and returns the *order*
  # (schedule_pickup itself returns {:ok, event}, not {:ok, order} — see the
  # dedicated test on that oddity below — so tests that need the resulting
  # order re-fetch it).
  defp schedule!(order, attrs \\ %{}) do
    details =
      Enum.into(attrs, %{
        date: "June 5, 2026",
        time: "2:00 PM",
        address: "123 Main St",
        instructions: "",
        completion_url: "http://localhost/complete"
      })

    {:ok, _event} = Orders.schedule_pickup(order, details)
    Orders.get_order!(order.id)
  end

  # A single order_item row for a given order, for asserting on quantity/price.
  defp sole_item(order) do
    order = Repo.preload(order, :items, force: true)
    [item] = order.items
    item
  end

  # ---------------------------------------------------------------------------
  # create_order/5
  # ---------------------------------------------------------------------------
  describe "create_order/5" do
    test "creates a :requested order with correct totals and item snapshot" do
      buyer = user_fixture()
      artist = artist_fixture()
      product = product_fixture(artist_id: artist.id, price: "50.00")
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      assert {:ok, order} =
               Orders.create_order(conversation, buyer, artist, [%{product: product, quantity: 2}])

      assert order.status == :requested
      assert order.conversation_id == conversation.id
      assert order.buyer_id == buyer.id
      assert order.artist_id == artist.id
      # $50 x 2 = $100 subtotal, 5% platform fee = $5, total = $105.
      assert Decimal.equal?(order.subtotal, Decimal.new("100.00"))
      assert Decimal.equal?(order.platform_fee, Decimal.new("5.00"))
      assert Decimal.equal?(order.total, Decimal.new("105.00"))

      item = sole_item(order)
      assert item.quantity == 2
      assert item.product_id == product.id
      # unit_price and product_title are snapshotted onto the item so later
      # price/title edits on the Product don't retroactively change history.
      assert Decimal.equal?(item.unit_price, product.price)
      assert item.product_title == product.title
    end

    test "rounds the 5% platform fee half-up to the nearest cent" do
      # 33.33 * 0.05 = 1.6665 — the interesting case is whether this rounds
      # to 1.66 or 1.67. Confirmed against Decimal.round/2's default mode.
      %{order: order} = new_order(price: "33.33")

      assert Decimal.equal?(order.subtotal, Decimal.new("33.33"))
      assert Decimal.equal?(order.platform_fee, Decimal.new("1.67"))
      assert Decimal.equal?(order.total, Decimal.new("35.00"))
    end

    test "snapshots buyer/vendor email and artist name onto the order" do
      buyer = user_fixture()
      artist = artist_fixture()
      %{order: order} = new_order(buyer: buyer, artist: artist)

      assert order.buyer_email == buyer.email
      assert order.artist_name == artist.nickname
    end

    test "posts a status_change event describing the request" do
      %{order: order, conversation: conversation} = new_order(quantity: 3)

      [event] = Conversations.list_events_for_conversation(conversation.id)
      assert event.event_type == :status_change
      assert event.actor_type == :buyer
      assert event.to_status == "requested"
      assert event.order_id == order.id
      assert event.body =~ "×3"
    end

    test "stamps the conversation's last_event_at" do
      buyer = user_fixture()
      artist = artist_fixture()
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      assert conversation.last_event_at == nil

      %{conversation: same_conversation} = new_order(buyer: buyer, artist: artist)
      reloaded = Conversations.get_conversation_all_status!(same_conversation.id)
      refute is_nil(reloaded.last_event_at)
    end

    test "rejects a non-positive-integer quantity before touching the database" do
      # Totals are computed with Decimal math before any changeset runs, so
      # this guard exists specifically to turn a bad quantity into a clean
      # error instead of a Decimal.new/1 crash (nil, 0, negative, or a float
      # would all otherwise blow up calculate_totals_from_specs/1).
      buyer = user_fixture()
      artist = artist_fixture()
      product = product_fixture(artist_id: artist.id)
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      for bad_quantity <- [nil, 0, -1] do
        assert Orders.create_order(conversation, buyer, artist, [
                 %{product: product, quantity: 1},
                 %{product: product, quantity: bad_quantity}
               ]) == {:error, :invalid_quantity}
      end

      assert Orders.list_orders_for_buyer(buyer.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # confirm_order/1 — :requested -> :confirmed
  # ---------------------------------------------------------------------------
  describe "confirm_order/1" do
    test "moves a :requested order to :confirmed and issues a completion token" do
      %{order: order} = new_order()
      assert order.complete_token == nil

      assert {:ok, confirmed} = Orders.confirm_order(order)
      assert confirmed.status == :confirmed
      refute is_nil(confirmed.complete_token)
      refute is_nil(confirmed.complete_token_at)
    end

    test "posts a status_change event from the vendor" do
      %{order: order, conversation: conversation} = new_order()
      confirm!(order)

      events = Conversations.list_events_for_conversation(conversation.id)
      assert Enum.any?(events, &(&1.actor_type == :vendor and &1.to_status == "confirmed"))
    end

    test "refuses to confirm an already-:confirmed order" do
      %{order: order} = new_order()
      confirmed = confirm!(order)

      assert Orders.confirm_order(confirmed) == {:error, :wrong_state}
    end

    test "refuses to confirm a :cancelled order" do
      %{order: order} = new_order()
      {:ok, cancelled} = Orders.cancel_order(order, :buyer)

      assert Orders.confirm_order(cancelled) == {:error, :wrong_state}
    end

    test "refuses to confirm a :completed order" do
      %{order: order} = new_order()
      confirmed = confirm!(order)
      completed = complete!(confirmed)

      assert Orders.confirm_order(completed) == {:error, :wrong_state}
    end
  end

  # ---------------------------------------------------------------------------
  # complete_pickup/2 — :confirmed -> :completed
  # ---------------------------------------------------------------------------
  describe "complete_pickup/2" do
    test "completes a :confirmed pickup order given the correct token" do
      %{order: order} = new_order()
      confirmed = confirm!(order) |> then(&Orders.get_order!(&1.id))

      assert {:ok, completed} = Orders.complete_pickup(confirmed, confirmed.complete_token)
      assert completed.status == :completed
      refute is_nil(completed.completed_at)
    end

    test "uses constant-time comparison — a wrong token is rejected" do
      %{order: order} = new_order()
      confirmed = confirm!(order) |> then(&Orders.get_order!(&1.id))

      assert Orders.complete_pickup(confirmed, "not-the-right-token") == {:error, :invalid_token}
    end

    test "an order that was never confirmed (no token yet) is rejected regardless of status" do
      %{order: order} = new_order()
      order = Orders.get_order!(order.id)

      assert Orders.complete_pickup(order, "anything") == {:error, :invalid_token}
    end

    test "a token that belonged to a now-:cancelled order no longer works" do
      # cancel_order does not clear complete_token, so this specifically
      # exercises the status guard rather than the token-nil guard above.
      %{order: order} = new_order()
      confirmed = confirm!(order) |> then(&Orders.get_order!(&1.id))
      {:ok, cancelled} = Orders.cancel_order(confirmed, :buyer)

      assert Orders.complete_pickup(cancelled, confirmed.complete_token) == {:error, :wrong_state}
    end

    test "a :delivery order can never be completed (no delivery flow exists yet)" do
      buyer = user_fixture()
      artist = artist_fixture()
      product = product_fixture(artist_id: artist.id)
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      {:ok, order} =
        Orders.create_order(
          conversation,
          buyer,
          artist,
          [%{product: product, quantity: 1}],
          :delivery
        )

      confirmed = confirm!(order) |> then(&Orders.get_order!(&1.id))

      assert Orders.complete_pickup(confirmed, confirmed.complete_token) == {:error, :wrong_state}
    end
  end

  # Small local helper (defined after the describe blocks that use it is
  # fine in Elixir — private functions are resolved at compile time).
  defp complete!(order) do
    order = Orders.get_order!(order.id)
    {:ok, completed} = Orders.complete_pickup(order, order.complete_token)
    completed
  end

  # ---------------------------------------------------------------------------
  # add_item_to_order/3
  # ---------------------------------------------------------------------------
  describe "add_item_to_order/3" do
    test "adds a new product as a new line item with quantity 1" do
      %{order: order, artist: artist} = new_order()
      other_product = product_fixture(artist_id: artist.id, price: "20.00")

      assert {:ok, updated} = Orders.add_item_to_order(order, other_product, :buyer)
      # force: true — do_amend deletes/reinserts item rows out from under the
      # returned struct's association, so a plain preload here would silently
      # return the pre-amendment items rather than re-querying. See the note
      # on the same force: true in Orders.add_item_to_order/3 itself.
      items = Repo.preload(updated, :items, force: true).items
      assert length(items) == 2
      assert Enum.find(items, &(&1.product_id == other_product.id)).quantity == 1
      # $50 + $20 = $70 subtotal, 5% = $3.50, total $73.50.
      assert Decimal.equal?(updated.total, Decimal.new("73.50"))
    end

    test "adding a product already on the order increments its quantity instead of duplicating" do
      %{order: order, product: product} = new_order()

      {:ok, updated} = Orders.add_item_to_order(order, product, :buyer)
      items = Repo.preload(updated, :items, force: true).items
      assert length(items) == 1
      assert hd(items).quantity == 2
    end

    test "labels the event by actor_type — buyer vs vendor" do
      %{order: order, artist: artist, conversation: conversation} = new_order()
      other_product = product_fixture(artist_id: artist.id)

      {:ok, order} = Orders.add_item_to_order(order, other_product, :vendor)
      [_original, event] = Conversations.list_events_for_conversation(conversation.id)
      assert event.body =~ "Vendor added"

      {:ok, _} = Orders.add_item_to_order(order, other_product, :buyer)
      [_, _, event2] = Conversations.list_events_for_conversation(conversation.id)
      assert event2.body =~ "Buyer added"
    end

    # --- Regression coverage: amending a :confirmed order keeps it :confirmed ---
    test "adding an item to a :confirmed order leaves it :confirmed and keeps the same completion token" do
      %{order: order, artist: artist} = new_order()
      confirmed = confirm!(order)
      other_product = product_fixture(artist_id: artist.id)

      {:ok, updated} = Orders.add_item_to_order(confirmed, other_product, :buyer)
      assert updated.status == :confirmed
      assert updated.complete_token == confirmed.complete_token
    end

    test "adding an item to a :confirmed order with a scheduled pickup preserves the pickup details" do
      %{order: order, artist: artist} = new_order()
      confirmed = confirm!(order)
      scheduled = schedule!(confirmed)
      other_product = product_fixture(artist_id: artist.id)

      {:ok, updated} = Orders.add_item_to_order(scheduled, other_product, :buyer)
      assert updated.status == :confirmed
      assert updated.complete_token == scheduled.complete_token
      assert updated.pickup_date == scheduled.pickup_date
      assert updated.pickup_time == scheduled.pickup_time
      assert updated.pickup_address == scheduled.pickup_address
      assert updated.pickup_scheduled_at == scheduled.pickup_scheduled_at
    end

    test "cannot add an item to a :cancelled order" do
      %{order: order, artist: artist} = new_order()
      {:ok, cancelled} = Orders.cancel_order(order, :buyer)
      other_product = product_fixture(artist_id: artist.id)

      assert Orders.add_item_to_order(cancelled, other_product, :buyer) == {:error, :wrong_state}
    end

    test "cannot add an item to a :completed order" do
      %{order: order, artist: artist} = new_order()
      completed = confirm!(order) |> complete!()
      other_product = product_fixture(artist_id: artist.id)

      assert Orders.add_item_to_order(completed, other_product, :buyer) == {:error, :wrong_state}
    end
  end

  # ---------------------------------------------------------------------------
  # remove_order_item/3
  #
  # Covers both directions the prompt asked for explicitly: decrementing a
  # multi-quantity line down (but staying above zero), and the "below zero"
  # boundary — removing the last unit of a line, and removing the very last
  # item on an order, which cancels the whole order rather than leaving it
  # open with nothing in it.
  # ---------------------------------------------------------------------------
  describe "remove_order_item/3" do
    test "decrementing a line above quantity 1 just reduces the quantity" do
      %{order: order} = new_order(quantity: 3)
      item = sole_item(order)

      assert {:ok, updated} = Orders.remove_order_item(order, item.id, :buyer)
      assert updated.status == :requested
      assert sole_item(updated).quantity == 2
    end

    test "decrementing a line at quantity 1, with other items remaining, removes just that line" do
      %{order: order, artist: artist, buyer: buyer} = new_order(quantity: 1)
      second_product = product_fixture(artist_id: artist.id)
      {:ok, order} = Orders.add_item_to_order(order, second_product, :buyer)

      first_item =
        Enum.find(
          Repo.preload(order, :items, force: true).items,
          &(&1.product_id != second_product.id)
        )

      assert {:ok, updated} = Orders.remove_order_item(order, first_item.id, :buyer)
      remaining = Repo.preload(updated, :items, force: true).items
      assert length(remaining) == 1
      assert hd(remaining).product_id == second_product.id
      assert updated.status == :requested
      assert updated.buyer_id == buyer.id
    end

    test "removing the only remaining item cancels the whole order (the below-zero boundary)" do
      %{order: order} = new_order(quantity: 1)
      item = sole_item(order)

      assert {:ok, cancelled} = Orders.remove_order_item(order, item.id, :buyer)
      assert cancelled.status == :cancelled
    end

    test "removing the last unit of the last line item on a :confirmed order also cancels it" do
      %{order: order} = new_order(quantity: 1)
      confirmed = confirm!(order)
      item = sole_item(confirmed)

      assert {:ok, cancelled} = Orders.remove_order_item(confirmed, item.id, :vendor)
      assert cancelled.status == :cancelled
    end

    test "a cancelled order cannot be decremented further — no going below the cancelled floor" do
      %{order: order} = new_order(quantity: 1)
      item = sole_item(order)
      {:ok, cancelled} = Orders.remove_order_item(order, item.id, :buyer)

      # There is no item left to reference, but even attempting the call
      # (e.g. with a stale item id from the client) hits the status guard
      # first and is refused.
      assert Orders.remove_order_item(cancelled, item.id, :buyer) == {:error, :wrong_state}
    end

    test "labels the event by actor_type — buyer, vendor, and system" do
      for actor <- [:buyer, :vendor, :system] do
        %{order: order, conversation: conversation} = new_order(quantity: 2)
        item = sole_item(order)

        {:ok, _} = Orders.remove_order_item(order, item.id, actor)
        [_original, event] = Conversations.list_events_for_conversation(conversation.id)
        expected_label = actor |> to_string() |> String.capitalize()
        assert event.body =~ expected_label
      end
    end

    test "returns :not_found for an item id that doesn't belong to the order" do
      %{order: order} = new_order()
      assert Orders.remove_order_item(order, -1, :buyer) == {:error, :not_found}
    end

    test "refuses to touch a :completed order" do
      %{order: order} = new_order(quantity: 2)
      completed = confirm!(order) |> complete!()
      item = sole_item(completed)

      assert Orders.remove_order_item(completed, item.id, :buyer) == {:error, :wrong_state}
    end

    # --- Regression coverage: amending a :confirmed order keeps it :confirmed ---
    test "decrementing (without emptying) a :confirmed order with a scheduled pickup stays :confirmed" do
      %{order: order} = new_order(quantity: 2)
      confirmed = confirm!(order)
      scheduled = schedule!(confirmed)
      item = sole_item(scheduled)

      {:ok, updated} = Orders.remove_order_item(scheduled, item.id, :buyer)
      assert updated.status == :confirmed
      assert updated.complete_token == scheduled.complete_token
      assert updated.pickup_scheduled_at == scheduled.pickup_scheduled_at
    end
  end

  # ---------------------------------------------------------------------------
  # increment_order_item/3
  # ---------------------------------------------------------------------------
  describe "increment_order_item/3" do
    test "increments the quantity by 1" do
      %{order: order} = new_order(quantity: 1)
      item = sole_item(order)

      assert {:ok, updated} = Orders.increment_order_item(order, item.id, :buyer)
      assert sole_item(updated).quantity == 2
    end

    test "keeps the original snapshot unit_price even if the product's price has since changed" do
      %{order: order, product: product} = new_order(price: "50.00")
      item = sole_item(order)

      {:ok, _same_product} = Products.update_product(product, %{price: "999.00"})

      {:ok, updated} = Orders.increment_order_item(order, item.id, :buyer)
      new_item = sole_item(updated)
      assert new_item.quantity == 2
      assert Decimal.equal?(new_item.unit_price, Decimal.new("50.00"))
      # Total reflects 2 x the *snapshotted* price, not the new product price.
      assert Decimal.equal?(updated.total, Decimal.new("105.00"))
    end

    test "labels the event by actor_type — buyer vs vendor" do
      %{order: order, conversation: conversation} = new_order()
      item = sole_item(order)

      {:ok, order} = Orders.increment_order_item(order, item.id, :vendor)
      [_original, event] = Conversations.list_events_for_conversation(conversation.id)
      assert event.body =~ "Vendor incremented"

      item2 = sole_item(order)
      {:ok, _} = Orders.increment_order_item(order, item2.id, :buyer)
      [_, _, event2] = Conversations.list_events_for_conversation(conversation.id)
      assert event2.body =~ "Buyer incremented"
    end

    test "returns :not_found for an item id that doesn't belong to the order" do
      %{order: order} = new_order()
      assert Orders.increment_order_item(order, -1, :buyer) == {:error, :not_found}
    end

    test "refuses to touch a :cancelled order" do
      %{order: order} = new_order()
      item = sole_item(order)
      {:ok, cancelled} = Orders.cancel_order(order, :buyer)

      assert Orders.increment_order_item(cancelled, item.id, :buyer) == {:error, :wrong_state}
    end

    # --- Regression coverage: amending a :confirmed order keeps it :confirmed ---
    test "incrementing on a :confirmed order with a scheduled pickup stays :confirmed with the same token" do
      %{order: order} = new_order()
      confirmed = confirm!(order)
      scheduled = schedule!(confirmed)
      item = sole_item(scheduled)

      {:ok, updated} = Orders.increment_order_item(scheduled, item.id, :vendor)
      assert updated.status == :confirmed
      assert updated.complete_token == scheduled.complete_token
      assert updated.pickup_address == scheduled.pickup_address
    end
  end

  # ---------------------------------------------------------------------------
  # amend_order/2
  # ---------------------------------------------------------------------------
  describe "amend_order/2" do
    test "replaces the order's items wholesale, recalculating totals from current product prices" do
      %{order: order, artist: artist} = new_order(price: "50.00")
      p2 = product_fixture(artist_id: artist.id, price: "10.00")
      p3 = product_fixture(artist_id: artist.id, price: "5.00")

      assert {:ok, updated} =
               Orders.amend_order(order, [
                 %{product: p2, quantity: 2},
                 %{product: p3, quantity: 4}
               ])

      items = Repo.preload(updated, :items, force: true).items
      assert length(items) == 2
      # (10*2) + (5*4) = 40 subtotal, 5% = 2.00, total 42.00.
      assert Decimal.equal?(updated.total, Decimal.new("42.00"))
    end

    test "refuses to amend a :completed order" do
      %{order: order, artist: artist} = new_order()
      completed = confirm!(order) |> complete!()
      p2 = product_fixture(artist_id: artist.id)

      assert Orders.amend_order(completed, [%{product: p2, quantity: 1}]) ==
               {:error, :wrong_state}
    end
  end

  # ---------------------------------------------------------------------------
  # cancel_order/2
  #
  # Only :requested/:confirmed orders can be cancelled. Includes a
  # regression test: a :completed order used to be cancellable after the
  # fact (after review-request messages had already gone out).
  # ---------------------------------------------------------------------------
  describe "cancel_order/2" do
    test "cancels a :requested order" do
      %{order: order} = new_order()
      assert {:ok, cancelled} = Orders.cancel_order(order, :buyer)
      assert cancelled.status == :cancelled
    end

    test "cancels a :confirmed order" do
      %{order: order} = new_order()
      confirmed = confirm!(order)
      assert {:ok, cancelled} = Orders.cancel_order(confirmed, :vendor)
      assert cancelled.status == :cancelled
    end

    test "cancels a :confirmed order that has a scheduled pickup" do
      %{order: order} = new_order()
      confirmed = confirm!(order)
      scheduled = schedule!(confirmed)
      assert {:ok, cancelled} = Orders.cancel_order(scheduled, :buyer)
      assert cancelled.status == :cancelled
    end

    # --- Regression coverage: cancel_order/2's status guard ---
    test "refuses to cancel a :completed order" do
      %{order: order} = new_order()
      completed = confirm!(order) |> complete!()

      assert Orders.cancel_order(completed, :buyer) == {:error, :wrong_state}
    end

    test "refuses to cancel an already-:cancelled order" do
      %{order: order} = new_order()
      {:ok, cancelled} = Orders.cancel_order(order, :buyer)

      assert Orders.cancel_order(cancelled, :buyer) == {:error, :wrong_state}
    end

    test "records who cancelled and an item summary in the event body" do
      %{order: order, conversation: conversation} = new_order(quantity: 5)
      {:ok, _} = Orders.cancel_order(order, :vendor)

      [_original, event] = Conversations.list_events_for_conversation(conversation.id)
      assert event.actor_type == :vendor
      assert event.to_status == "cancelled"
      assert event.body =~ "Vendor cancelled"
      assert event.body =~ "×5"
    end

    test "summarizes multiple distinct items as \"N items\" rather than listing titles" do
      %{order: order, artist: artist, conversation: conversation} = new_order(quantity: 1)
      p2 = product_fixture(artist_id: artist.id)
      {:ok, order} = Orders.add_item_to_order(order, p2, :buyer)
      {:ok, _} = Orders.cancel_order(order, :buyer)

      events = Conversations.list_events_for_conversation(conversation.id)
      cancel_event = Enum.find(events, &(&1.to_status == "cancelled"))
      assert cancel_event.body =~ "2 items"
    end
  end

  # ---------------------------------------------------------------------------
  # schedule_pickup/2 — sub-state of :confirmed
  # ---------------------------------------------------------------------------
  describe "schedule_pickup/2" do
    test "stores the pickup details and stamps pickup_scheduled_at" do
      %{order: order} = new_order()
      confirmed = confirm!(order)

      assert {:ok, event} =
               Orders.schedule_pickup(confirmed, %{
                 date: "June 5, 2026",
                 time: "2:00 PM",
                 address: "123 Main St",
                 instructions: "Ring the bell",
                 completion_url: "http://localhost/complete"
               })

      # Notably returns {:ok, event}, not {:ok, order} — unlike every other
      # mutator in this module. Callers that need the order re-fetch it
      # (see the `schedule!/2` test helper above). Documented here so this
      # inconsistency reads as "known", not "surprising", if it's ever hit.
      assert %ArtsyNeighbor.Conversations.ConversationEvent{} = event
      assert event.body =~ "Pick-up scheduled!"
      assert event.body =~ "Ring the bell"

      updated = Orders.get_order!(confirmed.id)
      assert updated.pickup_date == "June 5, 2026"
      assert updated.pickup_time == "2:00 PM"
      assert updated.pickup_address == "123 Main St"
      assert updated.pickup_instructions == "Ring the bell"
      refute is_nil(updated.pickup_scheduled_at)
    end

    test "date and time are optional — a blank date/time still shares the address and link" do
      %{order: order} = new_order()
      confirmed = confirm!(order)

      {:ok, event} =
        Orders.schedule_pickup(confirmed, %{
          date: "",
          time: "",
          address: "123 Main St",
          instructions: "",
          completion_url: "http://localhost/complete"
        })

      # Different heading when there's no date/time to report, so the
      # message doesn't misleadingly claim something was "scheduled".
      assert event.body =~ "Pick-up info shared"
      refute event.body =~ "Pick-up scheduled!"
      refute event.body =~ "Date:"
      refute event.body =~ "Time:"
      assert event.body =~ "Address: 123 Main St"

      updated = Orders.get_order!(confirmed.id)
      assert updated.pickup_date == nil
      assert updated.pickup_time == nil
      # Still fully usable — the order is scheduled/confirmed, just without
      # a stated date/time (e.g. it was agreed informally in chat).
      refute is_nil(updated.pickup_scheduled_at)
    end

    test "blank instructions are stored as nil, not an empty string" do
      %{order: order} = new_order()
      confirmed = confirm!(order)
      updated = schedule!(confirmed, instructions: "")

      assert updated.pickup_instructions == nil
    end

    test "refuses to schedule a pickup for a :requested (not yet confirmed) order" do
      %{order: order} = new_order()

      assert Orders.schedule_pickup(order, %{
               date: "",
               time: "",
               address: "x",
               instructions: "",
               completion_url: "x"
             }) ==
               {:error, :wrong_state}
    end

    test "refuses to schedule a pickup for a :cancelled order" do
      %{order: order} = new_order()
      {:ok, cancelled} = Orders.cancel_order(order, :buyer)

      assert Orders.schedule_pickup(cancelled, %{
               date: "",
               time: "",
               address: "x",
               instructions: "",
               completion_url: "x"
             }) ==
               {:error, :wrong_state}
    end
  end

  # ---------------------------------------------------------------------------
  # cancel_pickup/2 — clears the scheduled sub-state, status stays :confirmed
  # ---------------------------------------------------------------------------
  describe "cancel_pickup/2" do
    test "clears all pickup fields but leaves status :confirmed" do
      %{order: order} = new_order()
      confirmed = confirm!(order)
      scheduled = schedule!(confirmed)

      assert {:ok, updated} = Orders.cancel_pickup(scheduled, :buyer)
      assert updated.status == :confirmed
      assert updated.pickup_date == nil
      assert updated.pickup_time == nil
      assert updated.pickup_address == nil
      assert updated.pickup_instructions == nil
      assert updated.pickup_scheduled_at == nil
      # The completion token itself is untouched — cancelling the pickup
      # slot doesn't undo the vendor's original confirmation.
      assert updated.complete_token == scheduled.complete_token
    end

    test "the message differs depending on who cancelled" do
      %{order: order, conversation: conversation} = new_order()
      confirmed = confirm!(order)
      scheduled = schedule!(confirmed)
      {:ok, _} = Orders.cancel_pickup(scheduled, :buyer)

      events = Conversations.list_events_for_conversation(conversation.id)
      cancel_event = List.last(events)
      assert cancel_event.body =~ "Buyer requested a new pick-up time"
    end

    test "refuses when there is no pickup currently scheduled" do
      %{order: order} = new_order()
      confirmed = confirm!(order)

      assert Orders.cancel_pickup(confirmed, :buyer) == {:error, :wrong_state}
    end

    test "refuses on a :requested order (can't have a scheduled pickup at all)" do
      %{order: order} = new_order()
      assert Orders.cancel_pickup(order, :buyer) == {:error, :wrong_state}
    end
  end

  # ---------------------------------------------------------------------------
  # Read/query functions
  # ---------------------------------------------------------------------------
  describe "has_open_order_for_product?/2" do
    test "true when an open order contains the product" do
      %{order: order, product: product, conversation: conversation} = new_order()
      assert Orders.has_open_order_for_product?(conversation.id, product.id)
      assert order.status == :requested
    end

    test "false once the order is cancelled" do
      %{order: order, product: product, conversation: conversation} = new_order()
      {:ok, _} = Orders.cancel_order(order, :buyer)

      refute Orders.has_open_order_for_product?(conversation.id, product.id)
    end

    test "false for a product that isn't on any open order in that conversation" do
      %{conversation: conversation, artist: artist} = new_order()
      other_product = product_fixture(artist_id: artist.id)

      refute Orders.has_open_order_for_product?(conversation.id, other_product.id)
    end
  end

  describe "get_open_order_for_conversation/1" do
    # Regression guard: this function used to not preload :items, which
    # crashed ProductLive.Show whenever it checked `order.items` on the
    # result (Ecto.Association.NotLoaded is not Enumerable). Fixed to match
    # list_open_orders_for_conversation/1, which always preloaded items.
    test "preloads :items so callers can safely inspect them" do
      %{order: order, conversation: conversation} = new_order()
      found = Orders.get_open_order_for_conversation(conversation.id)

      assert found.id == order.id
      assert %Ecto.Association.NotLoaded{} != found.items
      assert Enum.count(found.items) == 1
    end

    test "returns nil when there is no open order" do
      buyer = user_fixture()
      artist = artist_fixture()
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      assert Orders.get_open_order_for_conversation(conversation.id) == nil
    end

    test "returns nil once the only order has been cancelled" do
      %{order: order, conversation: conversation} = new_order()
      {:ok, _} = Orders.cancel_order(order, :buyer)

      assert Orders.get_open_order_for_conversation(conversation.id) == nil
    end

    test "returns the most recently inserted open order when there are several" do
      buyer = user_fixture()
      artist = artist_fixture()
      p1 = product_fixture(artist_id: artist.id)
      p2 = product_fixture(artist_id: artist.id)
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      {:ok, _first} =
        Orders.create_order(conversation, buyer, artist, [%{product: p1, quantity: 1}])

      {:ok, second} =
        Orders.create_order(conversation, buyer, artist, [%{product: p2, quantity: 1}])

      assert Orders.get_open_order_for_conversation(conversation.id).id == second.id
    end
  end

  describe "list_open_orders_for_conversation/1" do
    test "only returns :requested and :confirmed orders, newest first" do
      buyer = user_fixture()
      artist = artist_fixture()
      p1 = product_fixture(artist_id: artist.id)
      p2 = product_fixture(artist_id: artist.id)
      p3 = product_fixture(artist_id: artist.id)
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      {:ok, requested} =
        Orders.create_order(conversation, buyer, artist, [%{product: p1, quantity: 1}])

      {:ok, to_confirm} =
        Orders.create_order(conversation, buyer, artist, [%{product: p2, quantity: 1}])

      confirmed = confirm!(to_confirm)

      {:ok, to_cancel} =
        Orders.create_order(conversation, buyer, artist, [%{product: p3, quantity: 1}])

      {:ok, _cancelled} = Orders.cancel_order(to_cancel, :buyer)

      open = Orders.list_open_orders_for_conversation(conversation.id)
      assert Enum.map(open, & &1.id) == [confirmed.id, requested.id]
    end
  end

  describe "get_order!/1" do
    test "preloads buyer, artist, and items with product/product_images" do
      %{order: order, buyer: buyer, artist: artist} = new_order()
      found = Orders.get_order!(order.id)

      assert found.buyer.id == buyer.id
      assert found.artist.id == artist.id
      [item] = found.items
      refute match?(%Ecto.Association.NotLoaded{}, item.product)
    end

    test "raises for a nonexistent id" do
      assert_raise Ecto.NoResultsError, fn -> Orders.get_order!(-1) end
    end
  end

  describe "list_orders_for_buyer/1 and list_orders_for_artist/1" do
    test "list_orders_for_buyer/1 returns only that buyer's orders, newest first" do
      buyer = user_fixture()
      other_buyer = user_fixture()
      artist = artist_fixture()
      p = product_fixture(artist_id: artist.id)
      {:ok, conversation} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      {:ok, other_conversation} =
        Conversations.find_or_create_conversation(other_buyer.id, artist.id)

      {:ok, first} =
        Orders.create_order(conversation, buyer, artist, [%{product: p, quantity: 1}])

      {:ok, second} =
        Orders.create_order(conversation, buyer, artist, [%{product: p, quantity: 1}])

      {:ok, _other} =
        Orders.create_order(other_conversation, other_buyer, artist, [%{product: p, quantity: 1}])

      result = Orders.list_orders_for_buyer(buyer.id)
      assert Enum.map(result, & &1.id) == [second.id, first.id]
    end

    test "list_orders_for_artist/1 returns only that artist's orders, regardless of status" do
      %{order: order, artist: artist} = new_order()
      {:ok, cancelled} = Orders.cancel_order(order, :buyer)
      other_artist = artist_fixture()
      %{} = new_order(artist: other_artist)

      result = Orders.list_orders_for_artist(artist.id)
      assert Enum.map(result, & &1.id) == [cancelled.id]
    end
  end
end
