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
    ConversationEvent.changeset(conversation_event, attrs)
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
    |> ConversationEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
    Creates a new conversation event of type "message" with the given attributes.
    Attributes should include: conversation_id, actor_id, actor_type, body.
  """
  def create_message_event(conversation, actor_id, actor_type, body) do
    %ConversationEvent{
      conversation_id: conversation.id,
      actor_id: actor_id,
      actor_type: actor_type,
      event_type: "message",
      body: body
    }
    |> ConversationEvent.changeset(%{})
    |> Repo.insert()
    |> case do
      {:ok, conv_event} ->
        broadcast_to_conversation(conversation.id, {:new_message, conv_event})
        # artist = Repo.get!(ArtsyNeighbor.Artists.Artist, ...)

        # recipient_user_id =
        #   if actor_type == :buyer, do: artist.user_id, else: buyer_id
        # broadcast_to_user(recipient_user_id, {:conversation_updated, conv_event})

        case actor_type do
          :buyer ->
            artist_user_id = conversation.artist.user_id
            IO.inspect(artist_user_id, label: "broadcasting to artist user_id")
            broadcast_to_user(artist_user_id, {:conversation_updated, conv_event})
          :vendor ->
            conversation = Repo.preload(conversation, :buyer)
            buyer_id = conversation.buyer_id
            broadcast_to_user(buyer_id, {:conversation_updated, conv_event})
          :system ->
            conversation = Repo.preload(conversation, :buyer, :artist)
            buyer_id = conversation.buyer_id
            artist_user_id = conversation.artist.user_id

            broadcast_to_user(buyer_id, {:conversation_updated, conv_event})
            broadcast_to_user(artist_user_id, {:conversation_updated, conv_event})

        end

        {:ok, conv_event}
      {:error, changeset} ->
        {:error, changeset}

    end
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
