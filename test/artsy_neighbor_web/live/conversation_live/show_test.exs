defmodule ArtsyNeighborWeb.ConversationLive.ShowTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Conversations
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

      # The input should gain the error class and the error message should be visible.
      assert html =~ "input-error"
      assert html =~ "blank"
    end

    test "blank message submit does not create a ConversationEvent", %{conn: conn, conv: conv} do
      {:ok, lv, _html} = live(conn, ~p"/messages/#{conv.id}")

      lv
      |> form("form[phx-submit='post_msg']", %{
        "conversation_event" => %{"body" => ""}
      })
      |> render_submit()

      assert ArtsyNeighbor.Repo.aggregate(ArtsyNeighbor.Conversations.ConversationEvent, :count) == 0
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
      {:ok, _event} = Conversations.create_message_event(conv, artist.user_id, :vendor, "Real-time hello!")

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
end
