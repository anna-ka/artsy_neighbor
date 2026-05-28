defmodule ArtsyNeighbor.Conversations do
  @moduledoc """
  The Conversations context.
  """

  #module attribute to set how many messages to load by default when loading a conversation.
  #also acts as a buffer size for loading more
  @conversation_events_limit 50

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Conversations.Conversation
  alias ArtsyNeighbor.Conversations.ConversationEvent



  @doc """
  Subscribes to scoped notifications about any conversation changes.

  The broadcasted messages match the pattern:

    * {:created, %Conversation{}}
    * {:updated, %Conversation{}}
    * {:deleted, %Conversation{}}

  """
  def subscribe_to_conversation(conversation_id) do
    Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "conversation:#{conversation_id}")
  end

  defp broadcast_to_conversation(conversation_id, message) do
    Phoenix.PubSub.broadcast(ArtsyNeighbor.PubSub, "conversation:#{conversation_id}", message)
  end

  # Subscribe to inbox updates for a user
  def subscribe_to_user_conversations(user_id) do
    Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{user_id}")
  end

  # Private broadcast helper
  defp broadcast_to_user(user_id, message) do
    Phoenix.PubSub.broadcast(ArtsyNeighbor.PubSub, "user:#{user_id}", message)
  end

  @doc"""
  Returns a changeset for a conversation."""
  def change_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    Conversation.changeset(conversation, attrs)
  end

  @doc """  Returns a changeset for a conversation event.
  """
  def change_conversation_event(%ConversationEvent{} = conversation_event, attrs \\ %{}) do
    ConversationEvent.message_changeset(conversation_event, attrs)
  end


  #functions written by Anna

  @doc """
    Finds an existing conversation between a buyer and artist, or creates one if it doesn't exist.
  """
  def find_or_create_conversation(buyer_id, artist_id) do
    case Repo.get_by(Conversation, buyer_id: buyer_id, artist_id: artist_id) do
      nil ->
        case %Conversation{}
             |> Conversation.changeset(%{buyer_id: buyer_id, artist_id: artist_id})
             |> Repo.insert() do
          {:ok, conversation} ->
            artist = Repo.get!(ArtsyNeighbor.Artists.Artist, conversation.artist_id)
            broadcast_to_user(artist.user_id, {:new_conversation, conversation})
            {:ok, conversation}
          error -> error
        end
      conversation ->
        {:ok, conversation}
    end

  end

  @doc """
    Lists all conversations for a given buyer.
  """
  def list_conversations_for_buyer(user_id) do
    Repo.all(
      from c in Conversation,
      where: c.buyer_id == ^user_id,
      # Most recently active conversations first; nil last_event_at (no messages yet) sinks to bottom.
      order_by: [desc_nulls_last: c.last_event_at],
      preload: [artist: :artist_images]
    )
  end

  @doc """
    Lists all conversations for a given artist.
  """
  def list_conversations_for_artist(artist_id) do
    Repo.all(
      from c in Conversation,
      where: c.artist_id == ^artist_id,
      # Most recently active conversations first; nil last_event_at sinks to bottom.
      order_by: [desc_nulls_last: c.last_event_at],
      preload: [:buyer]
    )
  end

  @doc """
    Lists all conversations for a given user, whether they are the buyer or artist.
  """
  def list_conversations_for_user(user_id) do
    Repo.all(
      from c in Conversation,
      where: c.buyer_id == ^user_id or c.artist_id == ^user_id,
      preload: [:buyer, artist: :artist_images]
      )
  end

  @doc """
    Gets a conversation by its ID. Raise exception if not found.
  """
  def get_conversation!(id)do
    Repo.get!(Conversation, id)
  end

  @doc """
  Gets a conversation by its ID. Returns nil if not found.
  """
  def get_conversation(id) do
    Repo.get(Conversation, id)
  end

  @doc """
  Gets a conversation by its ID with buyer and artist (+ artist images) preloaded.
  Returns nil if not found.
  """
  def get_conversation_with_participants(id) do
    case Repo.get(Conversation, id) do
      nil -> nil
      conversation -> Repo.preload(conversation, [:buyer, artist: :artist_images])
    end
  end

  @doc """
    Lists the most recent conversation events for a given conversation,
    up to the limit defined by @conversation_events_limit.
    Sorted by most recent first.
  """
  def list_events_for_conversation(conversation_id, limit \\ @conversation_events_limit) do
    Repo.all(from e in ConversationEvent,
      where: e.conversation_id == ^conversation_id,
      order_by: [desc: e.inserted_at],
      limit: ^limit)
    |> Enum.reverse()
  end

  @doc """
    Lists conversation events for a given conversation that were created before a certain datetime,
    up to the limit defined by @conversation_events_limit.
    Sorted by most recent first.
  """
  def list_events_before(conversation_id, before_dt, limit \\ @conversation_events_limit) do
    Repo.all(from e in ConversationEvent,
      where: e.conversation_id == ^conversation_id and e.inserted_at < ^before_dt,
      order_by: [desc: e.inserted_at],
      limit: ^limit)
    |> Enum.reverse()
  end

  @doc """
    Checks if there are any conversation events for a given conversation that were created before a certain datetime.
  """
  def has_events_before?(conversation_id, before_dt) do
    Repo.exists?(from e in ConversationEvent,
      where: e.conversation_id == ^conversation_id and e.inserted_at < ^before_dt)
  end

  @doc """
    Creates a new conversation event with the given attributes.
  """
  def create_conversation_event(attrs) do
    %ConversationEvent{}
    |> ConversationEvent.message_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
    Creates a new conversation event of type "message" with the given attributes.
    Attributes should include: conversation_id, actor_id, actor_type, body.
  """
  def create_message_event(conversation, actor_id, actor_type, body) do
    %ConversationEvent{event_type: :message}
    |> ConversationEvent.message_changeset(%{
      conversation_id: conversation.id,
      actor_id: actor_id,
      actor_type: actor_type,
      body: body
    })
    |> Repo.insert()
    |> case do
      {:ok, conv_event} ->
        # Stamp last_event_at on the conversation so unread queries work.
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        Repo.update_all(
          from(c in Conversation, where: c.id == ^conversation.id),
          set: [last_event_at: now]
        )

        # Notify the conversation thread (for the live chat view).
        broadcast_to_conversation(conversation.id, {:new_message, conv_event})

        # Notify the recipient(s) inbox so the unread dot appears.
        case actor_type do
          :buyer ->
            # Buyer sent the message — notify the artist's user inbox.
            artist_user_id = conversation.artist.user_id
              broadcast_to_user(artist_user_id, {:conversation_updated, conv_event})

          :vendor ->
            # Vendor sent the message — notify the buyer's inbox.
            conversation = Repo.preload(conversation, [:buyer])
            broadcast_to_user(conversation.buyer_id, {:conversation_updated, conv_event})

          :system ->
            # System event — notify both parties.
            conversation = Repo.preload(conversation, [:buyer, :artist])
            broadcast_to_user(conversation.buyer_id, {:conversation_updated, conv_event})
            broadcast_to_user(conversation.artist.user_id, {:conversation_updated, conv_event})
        end

        {:ok, conv_event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Marks a conversation as read for the given role (:buyer or :vendor),
  then broadcasts {:marked_read, conversation_id} to the user's inbox topic
  so the unread dot disappears in real time.
  """
  def mark_conversation_read(conversation, role, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Choose the right column based on who is reading.
    field = case role do
      :buyer  -> :buyer_last_read_at
      :vendor -> :vendor_last_read_at
    end

    conversation
    |> Ecto.Changeset.change([{field, now}])
    |> Repo.update()

    # Tell the inbox LiveView to remove this conversation from the unread set.
    broadcast_to_user(user_id, {:marked_read, conversation.id})

    :ok
  end

  @doc """
  Returns a list of conversation IDs that have unread messages for the given buyer.
  Unread = last_event_at is newer than buyer_last_read_at, or buyer never opened it (nil).
  """
  def list_unread_conversation_ids_for_buyer(user_id) do
    Repo.all(
      from c in Conversation,
      where: c.buyer_id == ^user_id,
      where: not is_nil(c.last_event_at) and
             (is_nil(c.buyer_last_read_at) or c.last_event_at > c.buyer_last_read_at),
      select: c.id
    )
  end

  @doc """
  Returns a list of conversation IDs that have unread messages for the given artist (vendor).
  Unread = last_event_at is newer than vendor_last_read_at, or vendor never opened it (nil).
  """
  def list_unread_conversation_ids_for_artist(artist_id) do
    Repo.all(
      from c in Conversation,
      where: c.artist_id == ^artist_id,
      where: not is_nil(c.last_event_at) and
             (is_nil(c.vendor_last_read_at) or c.last_event_at > c.vendor_last_read_at),
      select: c.id
    )
  end

  @doc """
  Returns true if the user has any unread conversations, false otherwise.
  Checks both their buyer conversations and (if they are a vendor) their artist conversations.
  artist_id should be nil if the user has no artist profile.
  """
  def has_unread_conversations?(user_id, artist_id) do
    buyer_has_unread = Repo.exists?(
      from c in Conversation,
      where: c.buyer_id == ^user_id,
      where: not is_nil(c.last_event_at) and
             (is_nil(c.buyer_last_read_at) or c.last_event_at > c.buyer_last_read_at)
    )

    vendor_has_unread =
      if artist_id do
        Repo.exists?(
          from c in Conversation,
          where: c.artist_id == ^artist_id,
          where: not is_nil(c.last_event_at) and
                 (is_nil(c.vendor_last_read_at) or c.last_event_at > c.vendor_last_read_at)
        )
      else
        false
      end

    buyer_has_unread or vendor_has_unread
  end

  def preload_participants(conversation) do
    Repo.preload(conversation, [:buyer, artist: :artist_images])
  end

  @doc """
  DEV ONLY: Deletes a conversation and all its events.
  """
  def delete_conversation_dev(conversation) do
    Repo.delete_all(from e in ConversationEvent, where: e.conversation_id == ^conversation.id)
    Repo.delete(conversation)
  end

end
