defmodule ArtsyNeighbor.ConversationsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ArtsyNeighbor.Conversations` context.
  """

  @doc """
  Generate a conversation.
  """
  def conversation_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        last_event_at: ~U[2026-04-06 19:35:00Z]
      })

    {:ok, conversation} = ArtsyNeighbor.Conversations.create_conversation(scope, attrs)
    conversation
  end

  @doc """
  Generate a conversation_event.
  """
  def conversation_event_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        actor_type: "some actor_type",
        body: "some body",
        event_type: "some event_type",
        from_status: "some from_status",
        to_status: "some to_status"
      })

    {:ok, conversation_event} = ArtsyNeighbor.Conversations.create_conversation_event(scope, attrs)
    conversation_event
  end
end
