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
  alias ArtsyNeighbor.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any conversation changes.

  The broadcasted messages match the pattern:

    * {:created, %Conversation{}}
    * {:updated, %Conversation{}}
    * {:deleted, %Conversation{}}

  """
  def subscribe_conversations(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{key}:conversations")
  end

  defp broadcast_conversation(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ArtsyNeighbor.PubSub, "user:#{key}:conversations", message)
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
        %Conversation{}
        |> Conversation.changeset(%{buyer_id: buyer_id, artist_id: artist_id})
        |> Repo.insert()
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
      where: c.buyer_id == ^user_id
      )
  end

  @doc """
    Lists all conversations for a given artist.
  """
  def list_conversations_for_artist(artist_id) do
    Repo.all(
      from c in Conversation,
      where: c.artist_id == ^artist_id
      )
  end

  @doc """
    Lists all conversations for a given user, whether they are the buyer or artist.
  """
  def list_conversations_for_user(user_id) do
    Repo.all(
      from c in Conversation,
      where: c.buyer_id == ^user_id or c.artist_id == ^user_id
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
  def create_message_event(conversation_id, actor_id, actor_type, body) do
    %ConversationEvent{
      conversation_id: conversation_id,
      actor_id: actor_id,
      actor_type: actor_type,
      event_type: "message",
      body: body
    }
    |> ConversationEvent.changeset(%{})
    |> Repo.insert()
  end

end
