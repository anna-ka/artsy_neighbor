defmodule ArtsyNeighborWeb.ConversationLive.IndexTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Conversations.Conversation
  alias ArtsyNeighbor.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates a buyer user and an artist (with its own linked user).
  defp setup_buyer_and_artist do
    buyer = user_fixture()
    artist = artist_fixture()
    {buyer, artist}
  end

  # Directly inserts a conversation row so tests can fine-tune timestamps without
  # triggering the PubSub broadcast from find_or_create_conversation.
  defp insert_conversation(buyer_id, artist_id, attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(%{buyer_id: buyer_id, artist_id: artist_id})
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
    |> Repo.preload([:buyer, artist: :artist_images])
  end

  # ---------------------------------------------------------------------------
  # Authorization
  # ---------------------------------------------------------------------------

  describe "authorization" do
    test "unauthenticated user is redirected to log-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               live(conn, ~p"/messages")

      assert path == ~p"/users/log-in"
      assert %{"error" => _} = flash
    end

    test "authenticated user can access the messages index", %{conn: conn} do
      buyer = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      assert html =~ "Your Messages"
    end
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  describe "rendering - buyer view" do
    test "buyer sees their conversations in the 'Buying' section", %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      _conv = insert_conversation(buyer.id, artist.id, %{last_event_at: ~U[2026-04-10 12:00:00Z]})

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      # The artist's nickname should appear in the Buying section row.
      assert html =~ artist.nickname
    end

    test "non-vendor user does not see a 'Selling' section", %{conn: conn} do
      # A plain buyer has no artist profile, so the Selling section should be absent.
      buyer = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      refute html =~ "Selling"
    end
  end

  describe "rendering - vendor view" do
    test "artist/vendor user sees their conversations in the 'Selling' section", %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      _conv = insert_conversation(buyer.id, artist.id, %{last_event_at: ~U[2026-04-10 12:00:00Z]})

      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      {:ok, _lv, html} =
        conn
        |> log_in_user(vendor_user)
        |> live(~p"/messages")

      assert html =~ "Selling"
      # The buyer's username (or email initial) should appear in the Selling section.
      assert html =~ (buyer.username || String.first(buyer.email))
    end
  end

  describe "rendering - unread dot badge" do
    test "unread conversations show the red dot (badge-error span)", %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      # last_event_at set but buyer_last_read_at nil → unread for buyer.
      _conv = insert_conversation(buyer.id, artist.id, %{last_event_at: ~U[2026-04-10 12:00:00Z]})

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      assert html =~ "badge-error"
    end

    test "read conversations do not show the red dot", %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      # buyer_last_read_at is after last_event_at → fully read.
      _conv = insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 10:00:00Z],
        buyer_last_read_at: ~U[2026-04-10 11:00:00Z]
      })

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      refute html =~ "badge-error"
    end

    test "conversation with no messages (null last_event_at) does not show the red dot", %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      _conv = insert_conversation(buyer.id, artist.id, %{})

      {:ok, _lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      refute html =~ "badge-error"
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time: new conversation (vendor inbox)
  # ---------------------------------------------------------------------------

  describe "real-time: new conversation" do
    test "{:new_conversation, conversation} appears in the vendor list", %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      {:ok, lv, html} =
        conn
        |> log_in_user(vendor_user)
        |> live(~p"/messages")

      # No conversations yet — neither the username nor email initial should appear
      # in the Selling section.
      buyer_identifier = buyer.username || String.first(buyer.email)
      refute html =~ buyer_identifier

      # Simulate a new buyer initiating a conversation (would be triggered via PubSub
      # when find_or_create_conversation is called by another user's session).
      {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      conv = Conversations.preload_participants(conv)

      send(lv.pid, {:new_conversation, conv})

      updated_html = render(lv)
      # The buyer's identifier should now appear in the Selling section.
      assert updated_html =~ buyer_identifier
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time: conversation updated (new message → dot appears)
  # ---------------------------------------------------------------------------

  describe "real-time: conversation updated" do
    test "{:conversation_updated, event} makes the unread dot appear for that conversation",
         %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      vendor_user = Repo.get!(ArtsyNeighbor.Accounts.User, artist.user_id)

      # Insert a read conversation for the vendor so the dot is initially absent.
      conv = insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 10:00:00Z],
        vendor_last_read_at: ~U[2026-04-10 11:00:00Z]
      })

      {:ok, lv, html} =
        conn
        |> log_in_user(vendor_user)
        |> live(~p"/messages")

      # Confirm the badge is absent before the real-time event.
      refute html =~ "badge-error"

      # Fabricate a ConversationEvent struct that looks like a new message arriving.
      fake_event = %ArtsyNeighbor.Conversations.ConversationEvent{
        id: 8_888_888,
        conversation_id: conv.id,
        actor_type: :buyer,
        actor_id: buyer.id,
        event_type: "message",
        body: "Hey vendor!",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      send(lv.pid, {:conversation_updated, fake_event})

      updated_html = render(lv)
      assert updated_html =~ "badge-error"
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time: marked read (dot disappears)
  # ---------------------------------------------------------------------------

  describe "real-time: marked read" do
    test "{:marked_read, conversation_id} removes the unread dot for that conversation",
         %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()

      # An unread conversation for the buyer.
      conv = insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z]
        # buyer_last_read_at nil → unread
      })

      {:ok, lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      # Confirm the red dot is present before the read event.
      assert html =~ "badge-error"

      # Simulate the user opening the conversation in another tab / the Show LiveView
      # broadcasting that this conversation was read.
      send(lv.pid, {:marked_read, conv.id})

      updated_html = render(lv)
      refute updated_html =~ "badge-error"
    end

    test "{:marked_read} for one conversation does not remove dots for other unread conversations",
         %{conn: conn} do
      {buyer, artist} = setup_buyer_and_artist()
      other_artist = artist_fixture()

      # Two unread conversations.
      conv1 = insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z]
      })
      _conv2 = insert_conversation(buyer.id, other_artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z]
      })

      {:ok, lv, html} =
        conn
        |> log_in_user(buyer)
        |> live(~p"/messages")

      assert html =~ "badge-error"

      # Mark only the first conversation as read.
      send(lv.pid, {:marked_read, conv1.id})

      updated_html = render(lv)
      # The second conversation's dot should still be present.
      assert updated_html =~ "badge-error"
    end
  end
end
