defmodule ArtsyNeighbor.ConversationsTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Conversations

  describe "conversations" do
    alias ArtsyNeighbor.Conversations.Conversation

    import ArtsyNeighbor.AccountsFixtures, only: [user_scope_fixture: 0]
    import ArtsyNeighbor.ConversationsFixtures

    @invalid_attrs %{last_event_at: nil}

    test "list_conversations/1 returns all scoped conversations" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      other_conversation = conversation_fixture(other_scope)
      assert Conversations.list_conversations(scope) == [conversation]
      assert Conversations.list_conversations(other_scope) == [other_conversation]
    end

    test "get_conversation!/2 returns the conversation with given id" do
      scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      other_scope = user_scope_fixture()
      assert Conversations.get_conversation!(scope, conversation.id) == conversation
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation!(other_scope, conversation.id) end
    end

    test "create_conversation/2 with valid data creates a conversation" do
      valid_attrs = %{last_event_at: ~U[2026-04-06 19:35:00Z]}
      scope = user_scope_fixture()

      assert {:ok, %Conversation{} = conversation} = Conversations.create_conversation(scope, valid_attrs)
      assert conversation.last_event_at == ~U[2026-04-06 19:35:00Z]
      assert conversation.user_id == scope.user.id
    end

    test "create_conversation/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Conversations.create_conversation(scope, @invalid_attrs)
    end

    test "update_conversation/3 with valid data updates the conversation" do
      scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      update_attrs = %{last_event_at: ~U[2026-04-07 19:35:00Z]}

      assert {:ok, %Conversation{} = conversation} = Conversations.update_conversation(scope, conversation, update_attrs)
      assert conversation.last_event_at == ~U[2026-04-07 19:35:00Z]
    end

    test "update_conversation/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      conversation = conversation_fixture(scope)

      assert_raise MatchError, fn ->
        Conversations.update_conversation(other_scope, conversation, %{})
      end
    end

    test "update_conversation/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Conversations.update_conversation(scope, conversation, @invalid_attrs)
      assert conversation == Conversations.get_conversation!(scope, conversation.id)
    end

    test "delete_conversation/2 deletes the conversation" do
      scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      assert {:ok, %Conversation{}} = Conversations.delete_conversation(scope, conversation)
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation!(scope, conversation.id) end
    end

    test "delete_conversation/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      assert_raise MatchError, fn -> Conversations.delete_conversation(other_scope, conversation) end
    end

    test "change_conversation/2 returns a conversation changeset" do
      scope = user_scope_fixture()
      conversation = conversation_fixture(scope)
      assert %Ecto.Changeset{} = Conversations.change_conversation(scope, conversation)
    end
  end

  describe "conversation_events" do
    alias ArtsyNeighbor.Conversations.ConversationEvent

    import ArtsyNeighbor.AccountsFixtures, only: [user_scope_fixture: 0]
    import ArtsyNeighbor.ConversationsFixtures

    @invalid_attrs %{body: nil, actor_type: nil, event_type: nil, from_status: nil, to_status: nil}

    test "list_conversation_events/1 returns all scoped conversation_events" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      other_conversation_event = conversation_event_fixture(other_scope)
      assert Conversations.list_conversation_events(scope) == [conversation_event]
      assert Conversations.list_conversation_events(other_scope) == [other_conversation_event]
    end

    test "get_conversation_event!/2 returns the conversation_event with given id" do
      scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      other_scope = user_scope_fixture()
      assert Conversations.get_conversation_event!(scope, conversation_event.id) == conversation_event
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation_event!(other_scope, conversation_event.id) end
    end

    test "create_conversation_event/2 with valid data creates a conversation_event" do
      valid_attrs = %{body: "some body", actor_type: "some actor_type", event_type: "some event_type", from_status: "some from_status", to_status: "some to_status"}
      scope = user_scope_fixture()

      assert {:ok, %ConversationEvent{} = conversation_event} = Conversations.create_conversation_event(scope, valid_attrs)
      assert conversation_event.body == "some body"
      assert conversation_event.actor_type == "some actor_type"
      assert conversation_event.event_type == "some event_type"
      assert conversation_event.from_status == "some from_status"
      assert conversation_event.to_status == "some to_status"
      assert conversation_event.user_id == scope.user.id
    end

    test "create_conversation_event/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Conversations.create_conversation_event(scope, @invalid_attrs)
    end

    test "update_conversation_event/3 with valid data updates the conversation_event" do
      scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      update_attrs = %{body: "some updated body", actor_type: "some updated actor_type", event_type: "some updated event_type", from_status: "some updated from_status", to_status: "some updated to_status"}

      assert {:ok, %ConversationEvent{} = conversation_event} = Conversations.update_conversation_event(scope, conversation_event, update_attrs)
      assert conversation_event.body == "some updated body"
      assert conversation_event.actor_type == "some updated actor_type"
      assert conversation_event.event_type == "some updated event_type"
      assert conversation_event.from_status == "some updated from_status"
      assert conversation_event.to_status == "some updated to_status"
    end

    test "update_conversation_event/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)

      assert_raise MatchError, fn ->
        Conversations.update_conversation_event(other_scope, conversation_event, %{})
      end
    end

    test "update_conversation_event/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Conversations.update_conversation_event(scope, conversation_event, @invalid_attrs)
      assert conversation_event == Conversations.get_conversation_event!(scope, conversation_event.id)
    end

    test "delete_conversation_event/2 deletes the conversation_event" do
      scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      assert {:ok, %ConversationEvent{}} = Conversations.delete_conversation_event(scope, conversation_event)
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation_event!(scope, conversation_event.id) end
    end

    test "delete_conversation_event/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      assert_raise MatchError, fn -> Conversations.delete_conversation_event(other_scope, conversation_event) end
    end

    test "change_conversation_event/2 returns a conversation_event changeset" do
      scope = user_scope_fixture()
      conversation_event = conversation_event_fixture(scope)
      assert %Ecto.Changeset{} = Conversations.change_conversation_event(scope, conversation_event)
    end
  end
end
