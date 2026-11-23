defmodule ArtsyNeighborWeb.ConversationLive.ShowTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.OrdersFixtures

  alias ArtsyNeighbor.Accounts.Scope
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates a buyer user, an artist (backed by its own user), and a conversation
  # between them. Returns all three so tests can log in as either party.
  defp setup_conversation do
    buyer = user_fixture()
    artist = artist_fixture()
    {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)
    conv = Repo.preload(conv, :artist)
    %{buyer: buyer, artist: artist, conv: conv}
  end

  # Posts a message directly via the context so we can seed the thread without
  # going through the LiveView. The conversation must already have :artist preloaded.
  defp seed_message(conv, user_id, actor_type, body) do
    {:ok, event} = Conversations.create_message_event(conv, user_id, actor_type, body)
    event
  end

  # ---------------------------------------------------------------------------
  # Authorization
  # ---------------------------------------------------------------------------

  describe "authorization" do
    test "unauthenticated user is redirected to log-in", %{conn: conn} do
      # We need any valid conversation ID; generate one in the DB first.
      %{conv: conv} = setup_conversation()

      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/messages/#{conv.id}")

      assert path == ~p"/users/log-in"
      assert %{"error" => _} = flash
    end

    test "authenticated buyer who owns the conversation can view it", %{conn: conn} do
      %{buyer: buyer, conv: conv} = setup_conversation()

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages/#{conv.id}")

      # The page should render without redirecting.
      assert html =~ "Send"
    end

    test "authenticated artist who owns the conversation can view it", %{conn: conn} do
      %{artist: artist, conv: conv} = setup_conversation()
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      {:ok, _lv, html} =
        conn
        |> log_in_user(vendor_user)
        |> live(~p"/messages/#{conv.id}")

      assert html =~ "Send"
    end

    test "authenticated user who is neither buyer nor artist is redirected with error flash",
         %{conn: conn} do
      %{conv: conv} = setup_conversation()
      outsider = user_fixture()

      # The LiveView performs a push_navigate after setting the flash, so we see
      # a live_redirect (not a plain redirect) here.
      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               conn
               |> log_in_user(outsider)
               |> live(~p"/messages/#{conv.id}")

      assert %{"error" => msg} = flash
      assert msg =~ "not authorized"
    end

    test "non-existent conversation ID redirects with error flash", %{conn: conn} do
      buyer = user_fixture()
      fake_id = 999_999

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               conn
               |> log_in_user(buyer)
               |> live(~p"/messages/#{fake_id}")

      assert %{"error" => msg} = flash
      assert msg =~ "not found"
    end

    # Regression test: an archived (admin-muted) conversation must 404 for a direct URL hit,
    # not just be hidden from list views, even for one of its own participants.
    test "an archived conversation redirects with error flash, even for its own buyer",
         %{conn: conn} do
      %{buyer: buyer, conv: conv} = setup_conversation()
      {:ok, _} = Conversations.soft_delete_conversation(conv)

      assert {:error, {:live_redirect, %{to: "/", flash: flash}}} =
               conn
               |> log_in_user(buyer)
               |> live(~p"/messages/#{conv.id}")

      assert %{"error" => msg} = flash
      assert msg =~ "not found"
    end
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  describe "rendering" do
    setup %{conn: conn} do
      %{buyer: buyer, artist: artist, conv: conv} = setup_conversation()
      %{conn: log_in_user(conn, buyer), buyer: buyer, artist: artist, conv: conv}
    end

    test "shows the other party's name in the header (buyer sees artist nickname)",
         %{conn: conn, artist: artist, conv: conv} do
      {:ok, _lv, html} = live(conn, ~p"/messages/#{conv.id}")
      assert html =~ artist.nickname
    end

    test "shows existing messages in the thread", %{conn: conn, buyer: buyer, conv: conv} do
      # Seed a message before mounting.
      seed_message(conv, buyer.id, :buyer, "Hello from buyer")

      {:ok, _lv, html} = live(conn, ~p"/messages/#{conv.id}")
      assert html =~ "Hello from buyer"
    end

    test "shows the message compose form", %{conn: conn, conv: conv} do
      {:ok, _lv, html} = live(conn, ~p"/messages/#{conv.id}")
      assert html =~ "Type your message"
      assert html =~ "Send"
    end
  end

  # ---------------------------------------------------------------------------
  # Posting a message
  # ---------------------------------------------------------------------------

  describe "posting a message" do
    setup %{conn: conn} do
      %{buyer: buyer, artist: artist, conv: conv} = setup_conversation()
      # Subscribe to the conversation topic so we can also verify broadcasts
      # indirectly — the LiveView itself handles them via handle_info.
      %{
        conn: log_in_user(conn, buyer),
        buyer: buyer,
        artist: artist,
        conv: conv
      }
    end

    test "buyer can post a message and it appears in the stream", %{conn: conn, conv: conv} do
      {:ok, lv, _html} = live(conn, ~p"/messages/#{conv.id}")

      lv
      |> form("form[phx-submit='post_msg']", %{
        "conversation_event" => %{"body" => "Hello, artist!"}
      })
      |> render_submit()

      # Streams are inserted into the DOM; render(lv) fetches the full current render.
      assert render(lv) =~ "Hello, artist!"
    end

    test "vendor can post a message and it appears in the stream", %{artist: artist, conv: conv} do
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      {:ok, lv, _html} =
        build_conn()
        |> log_in_user(vendor_user)
        |> live(~p"/messages/#{conv.id}")

      lv
      |> form("form[phx-submit='post_msg']", %{
        "conversation_event" => %{"body" => "Hello, buyer!"}
      })
      |> render_submit()

      # The message is inserted into the stream; render(lv) fetches the full current DOM.
      assert render(lv) =~ "Hello, buyer!"
    end

    test "blank message shows inline validation error on phx-change", %{conn: conn, conv: conv} do
      {:ok, lv, _html} = live(conn, ~p"/messages/#{conv.id}")

      # The phx-change (validate_msg) event sets action: :validate so Phoenix renders
      # inline errors immediately when the user touches the field. We simulate that here.
      html =
        lv
        |> form("form[phx-submit='post_msg']", %{
          "conversation_event" => %{"body" => ""}
        })
        |> render_change()

      # The field should gain the error class and the error message should be visible.
      assert html =~ "field-has-error"
      assert html =~ "blank"
    end

    test "blank message submit does not create a ConversationEvent", %{conn: conn, conv: conv} do
      {:ok, lv, _html} = live(conn, ~p"/messages/#{conv.id}")

      lv
      |> form("form[phx-submit='post_msg']", %{
        "conversation_event" => %{"body" => ""}
      })
      |> render_submit()

      assert ArtsyNeighbor.Repo.aggregate(ArtsyNeighbor.Conversations.ConversationEvent, :count) ==
               0
    end
  end

  # ---------------------------------------------------------------------------
  # Deleting a message
  # ---------------------------------------------------------------------------

  describe "deleting a message" do
    test "the sender can delete their own message — it renders as a placeholder", %{conn: conn} do
      %{buyer: buyer, conv: conv} = setup_conversation()
      event = seed_message(conv, buyer.id, :buyer, "Oops, wrong thread")

      {:ok, lv, _html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages/#{conv.id}")

      html =
        lv
        |> element("[phx-click='delete_message'][phx-value-id='#{event.id}']")
        |> render_click()

      refute html =~ "Oops, wrong thread"
      assert html =~ "Message deleted"
    end

    test "a non-sender has no delete button on someone else's message", %{conn: conn} do
      %{buyer: buyer, artist: artist, conv: conv} = setup_conversation()
      seed_message(conv, buyer.id, :buyer, "Message from buyer")
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      {:ok, _lv, html} =
        conn
        |> log_in_user(vendor_user)
        |> live(~p"/messages/#{conv.id}")

      assert html =~ "Message from buyer"
      refute html =~ "delete_message"
    end

    test "deleting someone else's message via a forged event id fails silently and leaves it intact",
         %{conn: _conn} do
      %{buyer: buyer, artist: artist, conv: conv} = setup_conversation()
      event = seed_message(conv, buyer.id, :buyer, "Message from buyer")
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      {:ok, lv, _html} =
        build_conn()
        |> log_in_user(vendor_user)
        |> live(~p"/messages/#{conv.id}")

      # Forge the event directly rather than through the (correctly hidden) button.
      render_click(lv, "delete_message", %{"id" => to_string(event.id)})

      assert Repo.get!(ArtsyNeighbor.Conversations.ConversationEvent, event.id).status == :active
    end

    test "a non-numeric forged event id fails silently instead of crashing", %{conn: conn} do
      %{buyer: buyer, conv: conv} = setup_conversation()
      event = seed_message(conv, buyer.id, :buyer, "Message from buyer")

      {:ok, lv, _html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages/#{conv.id}")

      html = render_click(lv, "delete_message", %{"id" => "not-a-number"})

      assert html =~ "Couldn&#39;t delete that message."
      assert Repo.get!(ArtsyNeighbor.Conversations.ConversationEvent, event.id).status == :active
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time updates via PubSub
  # ---------------------------------------------------------------------------

  describe "real-time: new message via PubSub" do
    test "incoming {:new_message, event} is inserted into the stream", %{conn: conn} do
      %{buyer: buyer, artist: artist, conv: conv} = setup_conversation()
      conv = Repo.preload(conv, :artist)

      {:ok, lv, _html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages/#{conv.id}")

      # Simulate the artist sending a message via PubSub (as the context would do).
      # We craft the event struct directly to avoid re-triggering real broadcasts.
      {:ok, _event} =
        Conversations.create_message_event(conv, artist.user_id, :vendor, "Real-time hello!")

      # The LiveView subscribes to "conversation:<id>" and handles {:new_message, event}.
      # Since create_message_event already broadcasts, the view should already have it.
      html = render(lv)
      assert html =~ "Real-time hello!"
    end

    test "sending {:new_message, event} directly to the LiveView process updates the stream",
         %{conn: conn} do
      %{buyer: buyer, artist: artist, conv: conv} = setup_conversation()
      conv = Repo.preload(conv, :artist)

      {:ok, lv, _html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages/#{conv.id}")

      # Build a minimal ConversationEvent without going through PubSub/context.
      fake_event = %ArtsyNeighbor.Conversations.ConversationEvent{
        id: 9_999_999,
        conversation_id: conv.id,
        actor_type: :vendor,
        actor_id: artist.user_id,
        event_type: "message",
        body: "Direct PubSub message",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      # Send the message directly to the LiveView process, mimicking what PubSub delivers.
      send(lv.pid, {:new_message, fake_event})

      html = render(lv)
      assert html =~ "Direct PubSub message"
    end
  end

  # ---------------------------------------------------------------------------
  # Vendor adding an item to an already-open order
  # ---------------------------------------------------------------------------

  # Only works that are for sale can go in an order (decided 2026-11-23;
  # until then the list showed all the vendor's works, whatever their
  # status, so that a paused vendor could still add their own).
  describe "vendor add item to order" do
    test "lists only the vendor's works that are for sale" do
      artist = artist_fixture(%{status: :active})
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)
      order = order_fixture(%{artist_id: artist.id})
      for_sale = product_fixture(%{artist_id: artist.id, title: "For Sale Work"})
      draft = product_fixture(%{artist_id: artist.id, title: "Draft Work", status: :draft})

      archived =
        product_fixture(%{artist_id: artist.id, title: "Archived Work", status: :archived})

      lv = live_as(vendor_user, order.conversation_id)
      html = lv |> element("[phx-click='open_add_item_form']") |> render_click()

      assert html =~ for_sale.title
      refute html =~ draft.title
      refute html =~ archived.title
    end

    test "a paused vendor has no works to add" do
      artist = artist_fixture(%{status: :active})
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)
      order = order_fixture(%{artist_id: artist.id})
      product = product_fixture(%{artist_id: artist.id})

      # Pausing the profile also pauses the work (:unavailable), see
      # Artists.deactivate_artist/1.
      {:ok, _} = Artists.deactivate_artist(Artists.get_artist!(artist.id))

      lv = live_as(vendor_user, order.conversation_id)
      html = lv |> element("[phx-click='open_add_item_form']") |> render_click()

      refute html =~ product.title
      assert html =~ "You have no works for sale to add."
    end

    test "a forged event can't add a work that isn't for sale" do
      %{order: order, artist: artist, vendor_user: vendor_user} = open_order()
      draft = product_fixture(%{artist_id: artist.id, status: :draft})
      lv = live_as(vendor_user, order.conversation_id)

      html =
        render_click(lv, "vendor_add_item", %{
          "order-id" => to_string(order.id),
          "product-id" => to_string(draft.id)
        })

      assert html =~ "That work isn&#39;t for sale, so it can&#39;t be added."
      assert item_quantities(order) == [1]
    end
  end

  # ---------------------------------------------------------------------------
  # Forged order events (audit finding S-1, 2026-11-15)
  # ---------------------------------------------------------------------------

  # Every order button sends an order id (and sometimes an item or product
  # id) from the browser, and anyone can send those events by hand with
  # any ids. These tests send them directly with render_click(lv, event,
  # params), the way an attacker would, instead of clicking the buttons
  # the page shows. Before the fix, every one of these changed the order.

  # A real :requested order for one unit of a $50 product, made through
  # Orders.create_order/4 so it has an item row to remove or increment.
  defp open_order do
    buyer = user_fixture()
    artist = artist_fixture()
    product = product_fixture(artist_id: artist.id, price: "50.00")
    {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)

    {:ok, order} =
      Orders.create_order(Scope.for_user(buyer), conv, [%{product: product, quantity: 1}])

    vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

    %{
      order: Orders.get_order!(order.id),
      buyer: buyer,
      artist: artist,
      vendor_user: vendor_user,
      product: product
    }
  end

  # The order as it is in the database now, with its items.
  defp reload_order(order), do: Orders.get_order!(order.id)

  # The quantity of each item in the order, e.g. [1].
  defp item_quantities(order) do
    Enum.map(reload_order(order).items, fn item -> item.quantity end)
  end

  defp live_as(user, conversation_id) do
    {:ok, lv, _html} =
      build_conn()
      |> log_in_user(user)
      |> live(~p"/messages/#{conversation_id}")

    lv
  end

  describe "forged order events from someone else's conversation" do
    # The attacker is a vendor with a conversation of their own, so the
    # vendor-only checks pass for them; only the check that the order
    # belongs to the conversation on screen stops them.
    setup do
      victim = open_order()

      attacker_artist = artist_fixture()
      attacker_product = product_fixture(artist_id: attacker_artist.id)
      attacker_user = Repo.get!(ArtsyNeighbor.Accounts.User, attacker_artist.user_id)

      {:ok, attacker_conv} =
        Conversations.find_or_create_conversation(user_fixture().id, attacker_artist.id)

      lv = live_as(attacker_user, attacker_conv.id)

      %{victim: victim, lv: lv, attacker_product: attacker_product}
    end

    test "can't confirm, cancel or change the items of another conversation's order",
         %{victim: %{order: order}, lv: lv, attacker_product: attacker_product} do
      order_id = to_string(order.id)
      [item] = order.items
      item_id = to_string(item.id)

      html = render_click(lv, "confirm_order", %{"id" => order_id})
      assert html =~ "Could not confirm order."
      assert reload_order(order).status == :requested

      html =
        render_click(lv, "increment_order_item", %{"order-id" => order_id, "item-id" => item_id})

      assert html =~ "Could not update quantity."
      assert item_quantities(order) == [1]

      html =
        render_click(lv, "remove_order_item", %{"order-id" => order_id, "item-id" => item_id})

      assert html =~ "Could not remove item."
      assert item_quantities(order) == [1]

      html =
        render_click(lv, "vendor_add_item", %{
          "order-id" => order_id,
          "product-id" => to_string(attacker_product.id)
        })

      assert html =~ "Could not add item."
      assert item_quantities(order) == [1]

      html = render_click(lv, "cancel_order", %{"id" => order_id})
      assert html =~ "Could not cancel order."
      assert reload_order(order).status == :requested
    end

    test "can't cancel or reschedule another conversation's pick-up", %{
      victim: %{order: order, vendor_user: vendor_user},
      lv: lv
    } do
      vendor_scope = Scope.for_user(vendor_user)
      {:ok, confirmed} = Orders.confirm_order(vendor_scope, order)

      {:ok, _event} =
        Orders.schedule_pickup(vendor_scope, confirmed, %{
          date: "June 5, 2027",
          time: "2:00 PM",
          address: "123 Main St",
          instructions: "",
          completion_url: "http://localhost/complete"
        })

      html = render_click(lv, "cancel_pickup", %{"id" => to_string(order.id)})

      assert html =~ "Could not cancel pick-up."
      assert reload_order(order).pickup_scheduled_at != nil

      html =
        render_click(lv, "submit_schedule", %{
          "schedule" => %{"order_id" => to_string(order.id), "address" => "Somewhere else"}
        })

      assert html =~ "Could not send schedule."
      assert reload_order(order).pickup_address == "123 Main St"
    end

    test "an id that can't be real gets an error message instead of crashing the page",
         %{victim: %{order: order}, lv: lv} do
      # "99999999999999999999" is too big for the database's id column:
      # before parse_id/1 refused it, the query itself crashed the page.
      for bad_id <- ["not-a-number", "12abc", "0", "-5", "99999999999999999999"] do
        html = render_click(lv, "cancel_order", %{"id" => bad_id})
        assert html =~ "Could not cancel order."

        html = render_click(lv, "delete_message", %{"id" => bad_id})
        assert html =~ "Couldn&#39;t delete that message."
      end

      html =
        render_click(lv, "remove_order_item", %{
          "order-id" => to_string(order.id),
          "item-id" => "not-a-number"
        })

      assert html =~ "Could not remove item."
    end

    # Caught by the catch-all handle_event clause at the end of the
    # handlers; without it each of these raised FunctionClauseError.
    # capture_log keeps its expected warnings out of the test output.
    @tag :capture_log
    test "an event with its fields missing, or an unknown event, gets an error message",
         %{lv: lv} do
      for {event, params} <- [
            {"confirm_order", %{}},
            {"submit_schedule", %{}},
            {"vendor_add_item", %{"order-id" => "1"}},
            {"no_such_event", %{}}
          ] do
        html = render_click(lv, event, params)
        assert html =~ "Something went wrong. Please reload the page."
      end
    end
  end

  describe "forged vendor-only events from the buyer" do
    test "the buyer can't confirm their own order or add works to it" do
      %{order: order, buyer: buyer, artist: artist} = open_order()
      other_work = product_fixture(artist_id: artist.id)
      lv = live_as(buyer, order.conversation_id)
      order_id = to_string(order.id)

      html = render_click(lv, "confirm_order", %{"id" => order_id})
      assert html =~ "Could not confirm order."
      assert reload_order(order).status == :requested
      assert reload_order(order).complete_token == nil

      html = render_click(lv, "open_add_item_form", %{"id" => order_id})
      assert html =~ "Could not open the list of works."

      html =
        render_click(lv, "vendor_add_item", %{
          "order-id" => order_id,
          "product-id" => to_string(other_work.id)
        })

      assert html =~ "Could not add item."
      assert item_quantities(order) == [1]
    end

    test "the buyer can't schedule the pick-up as if they were the vendor" do
      %{order: order, buyer: buyer, vendor_user: vendor_user} = open_order()
      {:ok, _confirmed} = Orders.confirm_order(Scope.for_user(vendor_user), order)
      lv = live_as(buyer, order.conversation_id)

      html = render_click(lv, "open_schedule_form", %{"id" => to_string(order.id)})
      assert html =~ "Could not open the pick-up form."

      # Sent straight to submit_schedule with the order's id, as the
      # vendor's form would: only submit_schedule's own role check stops it.
      html =
        render_click(lv, "submit_schedule", %{
          "schedule" => %{"order_id" => to_string(order.id), "address" => "Somewhere else"}
        })

      assert html =~ "Could not send schedule."
      assert reload_order(order).pickup_scheduled_at == nil
    end
  end

  describe "forged product id from the vendor" do
    test "a vendor can't add another artist's work to their own order" do
      %{order: order, vendor_user: vendor_user} = open_order()
      someone_elses_work = product_fixture(artist_id: artist_fixture().id)
      lv = live_as(vendor_user, order.conversation_id)

      html =
        render_click(lv, "vendor_add_item", %{
          "order-id" => to_string(order.id),
          "product-id" => to_string(someone_elses_work.id)
        })

      assert html =~ "Could not add item."
      assert item_quantities(order) == [1]
    end
  end

  # The same handlers, used the honest way through the page's own
  # buttons: the checks above mustn't get in the way of the real thing.
  describe "order buttons still work for the right person" do
    test "the vendor can confirm, add one of their own works and schedule the pick-up" do
      %{order: order, artist: artist, vendor_user: vendor_user} = open_order()
      second_work = product_fixture(artist_id: artist.id, title: "Second Work")
      lv = live_as(vendor_user, order.conversation_id)

      lv |> element("[phx-click='confirm_order']") |> render_click()
      assert reload_order(order).status == :confirmed

      lv |> element("[phx-click='open_add_item_form']") |> render_click()

      lv
      |> element("[phx-click='vendor_add_item'][phx-value-product-id='#{second_work.id}']")
      |> render_click()

      assert Enum.sort(item_quantities(order)) == [1, 1]

      lv |> element("[phx-click='open_schedule_form']") |> render_click()

      lv
      |> form("form[phx-submit='submit_schedule']", schedule: %{address: "1 Fort St"})
      |> render_submit()

      assert reload_order(order).pickup_address == "1 Fort St"
    end

    test "the buyer can add a unit and cancel the order" do
      %{order: order, buyer: buyer} = open_order()
      lv = live_as(buyer, order.conversation_id)

      lv |> element("[phx-click='increment_order_item']") |> render_click()
      assert item_quantities(order) == [2]

      lv |> element("[phx-click='cancel_order']") |> render_click()
      assert reload_order(order).status == :cancelled
    end
  end
end
