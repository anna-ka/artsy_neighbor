defmodule ArtsyNeighbor.ConversationsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Conversations.Conversation
  alias ArtsyNeighbor.Conversations.ConversationEvent
  alias ArtsyNeighbor.Repo

  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Creates a buyer user and an artist (with its own user), then returns both.
  defp setup_buyer_and_artist do
    buyer = user_fixture()
    artist = artist_fixture()
    {buyer, artist}
  end

  # Creates a conversation directly in the DB, bypassing find_or_create, so we
  # can control timestamps precisely in read-state tests.
  defp insert_conversation(buyer_id, artist_id, attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(%{buyer_id: buyer_id, artist_id: artist_id})
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end

  # ---------------------------------------------------------------------------
  # find_or_create_conversation/2
  # ---------------------------------------------------------------------------

  describe "find_or_create_conversation/2" do
    test "creates a new conversation when none exists" do
      {buyer, artist} = setup_buyer_and_artist()

      assert {:ok, %Conversation{} = conv} =
               Conversations.find_or_create_conversation(buyer.id, artist.id)

      assert conv.buyer_id == buyer.id
      assert conv.artist_id == artist.id
    end

    test "returns the existing conversation when called again with the same buyer and artist" do
      {buyer, artist} = setup_buyer_and_artist()

      {:ok, first} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      {:ok, second} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      # Same database row — not a duplicate.
      assert first.id == second.id
      assert Repo.aggregate(Conversation, :count) == 1
    end

    test "broadcasts {:new_conversation, conversation} to artist's user PubSub topic when created" do
      {buyer, artist} = setup_buyer_and_artist()

      # Subscribe on behalf of the artist's user so we can assert the message arrives.
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{artist.user_id}")

      {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      assert_receive {:new_conversation, ^conv}
    end

    test "does NOT broadcast {:new_conversation} when an existing conversation is returned" do
      {buyer, artist} = setup_buyer_and_artist()

      # First call — creates the conversation (and fires the broadcast).
      {:ok, _} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      # Now subscribe and call again — this time it should be a no-op.
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{artist.user_id}")

      {:ok, _} = Conversations.find_or_create_conversation(buyer.id, artist.id)

      refute_receive {:new_conversation, _}
    end
  end

  # ---------------------------------------------------------------------------
  # create_message_event/4
  # ---------------------------------------------------------------------------

  describe "create_message_event/4" do
    setup do
      {buyer, artist} = setup_buyer_and_artist()
      {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      # Preload artist so the function can access artist.user_id for broadcasts.
      conv = Repo.preload(conv, :artist)
      %{buyer: buyer, artist: artist, conv: conv}
    end

    test "creates a ConversationEvent with correct fields", %{buyer: buyer, conv: conv} do
      assert {:ok, %ConversationEvent{} = event} =
               Conversations.create_message_event(conv, buyer.id, :buyer, "Hello!")

      assert event.body == "Hello!"
      assert event.actor_type == :buyer
      assert event.actor_id == buyer.id
      assert event.event_type == :message
      assert event.conversation_id == conv.id
    end

    test "stamps last_event_at on the conversation after creation", %{buyer: buyer, conv: conv} do
      assert is_nil(conv.last_event_at)

      {:ok, _event} = Conversations.create_message_event(conv, buyer.id, :buyer, "Hi")

      updated = Repo.get!(Conversation, conv.id)
      refute is_nil(updated.last_event_at)
    end

    test "returns {:error, changeset} when body is blank", %{buyer: buyer, conv: conv} do
      assert {:error, %Ecto.Changeset{} = cs} =
               Conversations.create_message_event(conv, buyer.id, :buyer, "")

      assert "can't be blank" in errors_on(cs).body
    end

    test "broadcasts {:new_message, event} to the conversation topic", %{buyer: buyer, conv: conv} do
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "conversation:#{conv.id}")

      {:ok, event} = Conversations.create_message_event(conv, buyer.id, :buyer, "Hey!")

      assert_receive {:new_message, ^event}
    end

    test "when actor_type is :buyer — broadcasts {:conversation_updated} to artist's user topic",
         %{buyer: buyer, artist: artist, conv: conv} do
      # Artist's user inbox should light up.
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{artist.user_id}")
      # Buyer's own inbox should NOT receive this notification.
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{buyer.id}")

      {:ok, event} =
        Conversations.create_message_event(conv, buyer.id, :buyer, "Message from buyer")

      assert_receive {:conversation_updated, ^event}

      # The buyer's own inbox should not be notified — they sent the message.
      refute_receive {:conversation_updated, _}
    end

    test "when actor_type is :vendor — broadcasts {:conversation_updated} to buyer's user topic",
         %{buyer: buyer, artist: artist, conv: conv} do
      vendor_user = artist.user_id

      # Buyer's inbox should light up.
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{buyer.id}")
      # Vendor/artist's inbox should NOT receive this notification.
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{vendor_user}")

      {:ok, event} =
        Conversations.create_message_event(conv, vendor_user, :vendor, "Reply from vendor")

      assert_receive {:conversation_updated, ^event}

      # The vendor's own inbox should not be notified — they sent the message.
      refute_receive {:conversation_updated, _}
    end
  end

  # ---------------------------------------------------------------------------
  # mark_conversation_read/3
  # ---------------------------------------------------------------------------

  describe "mark_conversation_read/3" do
    setup do
      {buyer, artist} = setup_buyer_and_artist()
      conv = insert_conversation(buyer.id, artist.id, %{last_event_at: ~U[2026-04-10 12:00:00Z]})
      %{buyer: buyer, artist: artist, conv: conv}
    end

    test "when role is :buyer — sets buyer_last_read_at, does not touch vendor_last_read_at",
         %{buyer: buyer, conv: conv} do
      assert is_nil(conv.buyer_last_read_at)
      assert is_nil(conv.vendor_last_read_at)

      Conversations.mark_conversation_read(conv, :buyer, buyer.id)

      updated = Repo.get!(Conversation, conv.id)
      refute is_nil(updated.buyer_last_read_at)
      assert is_nil(updated.vendor_last_read_at)
    end

    test "when role is :vendor — sets vendor_last_read_at, does not touch buyer_last_read_at",
         %{artist: artist, conv: conv} do
      vendor_user_id = artist.user_id
      assert is_nil(conv.vendor_last_read_at)
      assert is_nil(conv.buyer_last_read_at)

      Conversations.mark_conversation_read(conv, :vendor, vendor_user_id)

      updated = Repo.get!(Conversation, conv.id)
      refute is_nil(updated.vendor_last_read_at)
      assert is_nil(updated.buyer_last_read_at)
    end

    test "broadcasts {:marked_read, conversation_id} to the given user's PubSub topic",
         %{buyer: buyer, conv: conv} do
      Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{buyer.id}")

      Conversations.mark_conversation_read(conv, :buyer, buyer.id)

      assert_receive {:marked_read, conv_id}
      assert conv_id == conv.id
    end
  end

  # ---------------------------------------------------------------------------
  # has_unread_conversations?/2
  # ---------------------------------------------------------------------------

  describe "has_unread_conversations?/2" do
    test "returns false when user has no conversations" do
      user = user_fixture()
      refute Conversations.has_unread_conversations?(user.id, nil)
    end

    test "returns false when all buyer conversations are read (last_event_at <= buyer_last_read_at)" do
      {buyer, artist} = setup_buyer_and_artist()
      # last_event_at is older than buyer_last_read_at — already read.
      insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 10:00:00Z],
        buyer_last_read_at: ~U[2026-04-10 11:00:00Z]
      })

      refute Conversations.has_unread_conversations?(buyer.id, nil)
    end

    test "returns true when buyer has an unread conversation (last_event_at > buyer_last_read_at)" do
      {buyer, artist} = setup_buyer_and_artist()

      insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z],
        buyer_last_read_at: ~U[2026-04-10 11:00:00Z]
      })

      assert Conversations.has_unread_conversations?(buyer.id, nil)
    end

    test "returns true when buyer_last_read_at is nil (conversation never opened)" do
      {buyer, artist} = setup_buyer_and_artist()

      insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z]
        # buyer_last_read_at left as nil
      })

      assert Conversations.has_unread_conversations?(buyer.id, nil)
    end

    test "returns true when vendor has an unread conversation (last_event_at > vendor_last_read_at)" do
      {buyer, artist} = setup_buyer_and_artist()

      insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z],
        vendor_last_read_at: ~U[2026-04-10 11:00:00Z]
      })

      # artist_id must be provided for vendor-side unread check.
      assert Conversations.has_unread_conversations?(artist.user_id, artist.id)
    end

    test "returns false when artist_id is nil even if vendor_last_read_at would indicate unread" do
      {buyer, artist} = setup_buyer_and_artist()

      insert_conversation(buyer.id, artist.id, %{
        last_event_at: ~U[2026-04-10 12:00:00Z],
        vendor_last_read_at: ~U[2026-04-10 11:00:00Z],
        # buyer side is already read
        buyer_last_read_at: ~U[2026-04-10 13:00:00Z]
      })

      # No artist_id passed — buyer side is read, vendor side is skipped.
      refute Conversations.has_unread_conversations?(buyer.id, nil)
    end

    test "returns false when last_event_at is nil (no messages yet)" do
      {buyer, artist} = setup_buyer_and_artist()
      # Conversation exists but has never had any events.
      insert_conversation(buyer.id, artist.id, %{})

      refute Conversations.has_unread_conversations?(buyer.id, nil)
    end
  end

  # ---------------------------------------------------------------------------
  # list_unread_conversation_ids_for_buyer/1
  # ---------------------------------------------------------------------------

  describe "list_unread_conversation_ids_for_buyer/1" do
    test "returns IDs of conversations with unread messages for the buyer" do
      {buyer, artist} = setup_buyer_and_artist()

      unread =
        insert_conversation(buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 12:00:00Z]
          # buyer_last_read_at nil — never opened
        })

      ids = Conversations.list_unread_conversation_ids_for_buyer(buyer.id)
      assert unread.id in ids
    end

    test "does not return IDs of read conversations" do
      {buyer, artist} = setup_buyer_and_artist()

      read =
        insert_conversation(buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 10:00:00Z],
          buyer_last_read_at: ~U[2026-04-10 11:00:00Z]
        })

      ids = Conversations.list_unread_conversation_ids_for_buyer(buyer.id)
      refute read.id in ids
    end

    test "does not return IDs of conversations with no messages (null last_event_at)" do
      {buyer, artist} = setup_buyer_and_artist()
      no_messages = insert_conversation(buyer.id, artist.id, %{})

      ids = Conversations.list_unread_conversation_ids_for_buyer(buyer.id)
      refute no_messages.id in ids
    end

    test "returns only the buyer's own unread conversations, not another user's" do
      {buyer, artist} = setup_buyer_and_artist()
      other_buyer = user_fixture()

      _mine =
        insert_conversation(buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 12:00:00Z]
        })

      _theirs =
        insert_conversation(other_buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 12:00:00Z]
        })

      ids = Conversations.list_unread_conversation_ids_for_buyer(buyer.id)
      # Should contain only the buyer's conversation.
      assert length(ids) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # list_unread_conversation_ids_for_artist/1
  # ---------------------------------------------------------------------------

  describe "list_unread_conversation_ids_for_artist/1" do
    test "returns IDs of conversations with unread messages for the artist" do
      {buyer, artist} = setup_buyer_and_artist()

      unread =
        insert_conversation(buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 12:00:00Z]
          # vendor_last_read_at nil — never opened
        })

      ids = Conversations.list_unread_conversation_ids_for_artist(artist.id)
      assert unread.id in ids
    end

    test "does not return IDs of read conversations" do
      {buyer, artist} = setup_buyer_and_artist()

      read =
        insert_conversation(buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 10:00:00Z],
          vendor_last_read_at: ~U[2026-04-10 11:00:00Z]
        })

      ids = Conversations.list_unread_conversation_ids_for_artist(artist.id)
      refute read.id in ids
    end

    test "does not return IDs of conversations with no messages (null last_event_at)" do
      {buyer, artist} = setup_buyer_and_artist()
      no_messages = insert_conversation(buyer.id, artist.id, %{})

      ids = Conversations.list_unread_conversation_ids_for_artist(artist.id)
      refute no_messages.id in ids
    end

    test "does not return conversations belonging to a different artist" do
      {buyer, artist} = setup_buyer_and_artist()
      other_artist = artist_fixture()

      _mine =
        insert_conversation(buyer.id, artist.id, %{
          last_event_at: ~U[2026-04-10 12:00:00Z]
        })

      _theirs =
        insert_conversation(buyer.id, other_artist.id, %{
          last_event_at: ~U[2026-04-10 12:00:00Z]
        })

      ids = Conversations.list_unread_conversation_ids_for_artist(artist.id)
      assert length(ids) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # soft_delete_conversation/1, restore_conversation/1
  # ---------------------------------------------------------------------------

  describe "soft_delete_conversation/1" do
    test "sets status to :archived and stamps status_changed_at" do
      {buyer, artist} = setup_buyer_and_artist()
      conv = insert_conversation(buyer.id, artist.id)
      assert is_nil(conv.status_changed_at)

      assert {:ok, updated} = Conversations.soft_delete_conversation(conv)

      assert updated.status == :archived
      refute is_nil(updated.status_changed_at)
    end
  end

  describe "restore_conversation/1" do
    test "sets status back to :active" do
      {buyer, artist} = setup_buyer_and_artist()
      conv = insert_conversation(buyer.id, artist.id, %{status: :archived})

      assert {:ok, updated} = Conversations.restore_conversation(conv)
      assert updated.status == :active
    end

    test "refuses with {:error, :already_active} when the conversation is already :active" do
      {buyer, artist} = setup_buyer_and_artist()
      conv = insert_conversation(buyer.id, artist.id)

      assert {:error, :already_active} = Conversations.restore_conversation(conv)
    end
  end

  # ---------------------------------------------------------------------------
  # Status scoping — archived conversations are hidden from every
  # participant-facing read path.
  # ---------------------------------------------------------------------------

  describe "status scoping for archived conversations" do
    test "get_conversation/1 returns nil for an archived conversation" do
      {buyer, artist} = setup_buyer_and_artist()
      conv = insert_conversation(buyer.id, artist.id, %{status: :archived})

      assert is_nil(Conversations.get_conversation(conv.id))
    end

    test "get_conversation/1 returns the conversation when :active" do
      {buyer, artist} = setup_buyer_and_artist()
      conv = insert_conversation(buyer.id, artist.id)

      assert %Conversation{} = Conversations.get_conversation(conv.id)
    end

    test "list_conversations_for_buyer/1 excludes archived conversations" do
      {buyer, artist} = setup_buyer_and_artist()
      archived = insert_conversation(buyer.id, artist.id, %{status: :archived})

      ids = Enum.map(Conversations.list_conversations_for_buyer(buyer.id), fn c -> c.id end)
      refute archived.id in ids
    end

    test "list_conversations_for_artist/1 excludes archived conversations" do
      {buyer, artist} = setup_buyer_and_artist()
      archived = insert_conversation(buyer.id, artist.id, %{status: :archived})

      ids = Enum.map(Conversations.list_conversations_for_artist(artist.id), fn c -> c.id end)
      refute archived.id in ids
    end

    test "list_conversations_for_user/1 excludes archived conversations" do
      {buyer, artist} = setup_buyer_and_artist()
      archived = insert_conversation(buyer.id, artist.id, %{status: :archived})

      ids = Enum.map(Conversations.list_conversations_for_user(buyer.id), fn c -> c.id end)
      refute archived.id in ids
    end

    test "list_unread_conversation_ids_for_buyer/1 excludes an archived-but-unread conversation" do
      {buyer, artist} = setup_buyer_and_artist()

      archived =
        insert_conversation(buyer.id, artist.id, %{
          status: :archived,
          last_event_at: ~U[2026-04-10 12:00:00Z]
        })

      refute archived.id in Conversations.list_unread_conversation_ids_for_buyer(buyer.id)
    end

    test "list_unread_conversation_ids_for_artist/1 excludes an archived-but-unread conversation" do
      {buyer, artist} = setup_buyer_and_artist()

      archived =
        insert_conversation(buyer.id, artist.id, %{
          status: :archived,
          last_event_at: ~U[2026-04-10 12:00:00Z]
        })

      refute archived.id in Conversations.list_unread_conversation_ids_for_artist(artist.id)
    end

    test "has_unread_conversations?/2 ignores an archived-but-unread conversation" do
      {buyer, artist} = setup_buyer_and_artist()

      insert_conversation(buyer.id, artist.id, %{
        status: :archived,
        last_event_at: ~U[2026-04-10 12:00:00Z]
      })

      refute Conversations.has_unread_conversations?(buyer.id, nil)
    end

    test "list_system_conversations_for_user/1 excludes an archived system conversation" do
      user = user_fixture()
      {:ok, system_conv} = Conversations.get_or_create_system_conversation(user.id)
      {:ok, _archived} = Conversations.soft_delete_conversation(system_conv)

      assert Conversations.list_system_conversations_for_user(user.id) == []
    end

    test "list_unread_system_conversation_ids_for_user/1 excludes an archived system conversation" do
      user = user_fixture()
      {:ok, system_conv} = Conversations.get_or_create_system_conversation(user.id)
      {:ok, _event} = Conversations.post_system_message(system_conv, "Welcome!")
      system_conv = Repo.get!(Conversation, system_conv.id)
      {:ok, _archived} = Conversations.soft_delete_conversation(system_conv)

      assert Conversations.list_unread_system_conversation_ids_for_user(user.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # get_conv_event/1, soft_delete_event/2
  # ---------------------------------------------------------------------------

  describe "get_conv_event/1" do
    test "returns the event when it exists" do
      {buyer, artist} = setup_buyer_and_artist()
      {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      conv = Repo.preload(conv, :artist)
      {:ok, event} = Conversations.create_message_event(conv, buyer.id, :buyer, "Hi")

      assert %ConversationEvent{id: id} = Conversations.get_conv_event(event.id)
      assert id == event.id
    end

    test "returns nil when the event doesn't exist" do
      assert is_nil(Conversations.get_conv_event(999_999))
    end
  end

  describe "soft_delete_event/2" do
    setup do
      {buyer, artist} = setup_buyer_and_artist()
      {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      conv = Repo.preload(conv, :artist)
      {:ok, event} = Conversations.create_message_event(conv, buyer.id, :buyer, "Delete me")
      %{buyer: buyer, artist: artist, conv: conv, event: event}
    end

    test "the sender can delete their own message — status becomes :deleted", %{
      buyer: buyer,
      event: event
    } do
      assert {:ok, updated} = Conversations.soft_delete_event(event, buyer.id)
      assert updated.status == :deleted
    end

    test "a different user cannot delete someone else's message", %{artist: artist, event: event} do
      assert {:error, :not_owner} = Conversations.soft_delete_event(event, artist.user_id)

      # Confirm nothing changed in the DB.
      assert Repo.get!(ConversationEvent, event.id).status == :active
    end

    test "a :status_change event can never be deleted, even by its own actor", %{
      buyer: buyer,
      conv: conv
    } do
      {:ok, status_event} =
        %ConversationEvent{event_type: :status_change}
        |> ConversationEvent.status_change_changeset(%{
          actor_type: :buyer,
          actor_id: buyer.id,
          to_status: "confirmed",
          conversation_id: conv.id
        })
        |> Repo.insert()

      assert {:error, :not_a_message} = Conversations.soft_delete_event(status_event, buyer.id)
    end
  end

  # ---------------------------------------------------------------------------
  # hard_delete_conversation_dev/1
  # ---------------------------------------------------------------------------

  describe "hard_delete_conversation_dev/1" do
    test "deletes the conversation and all its events" do
      {buyer, artist} = setup_buyer_and_artist()
      {:ok, conv} = Conversations.find_or_create_conversation(buyer.id, artist.id)
      conv = Repo.preload(conv, :artist)
      {:ok, _event} = Conversations.create_message_event(conv, buyer.id, :buyer, "Bye")

      assert {:ok, _} = Conversations.hard_delete_conversation_dev(conv)

      assert is_nil(Repo.get(Conversation, conv.id))

      remaining_events = from(e in ConversationEvent, where: e.conversation_id == ^conv.id)
      assert Repo.aggregate(remaining_events, :count) == 0
    end
  end
end
