defmodule ArtsyNeighborWeb.ConversationLive.Show do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Conversations.Conversation
  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Accounts.Scope
  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Conversations.ConversationEvent

  import ArtsyNeighborWeb.CustomComponents, only: [ button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do
    # socket = assign(socket, :key, value)
    {:ok, socket}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    case Conversations.get_conversation(id) do
      nil ->
        {:noreply,
        socket
        |> put_flash(:error, "Conversation not found.")
        |> push_navigate(to: ~p"/")}

      conversation ->
        current_user = socket.assigns.current_scope.user
        if conversation.buyer_id == current_user.id or conversation.artist_id == current_user.id do

          msg_changeset = ConversationEvent.changeset(%ConversationEvent{}, %{})

          socket  =
            socket
            |> stream(:messages, Conversations.list_events_for_conversation(conversation.id))
            |> assign(:conversation, conversation)
            |> assign(:form, to_form(msg_changeset))
          {:noreply, socket}
        else
          {:noreply,
          socket
          |> put_flash(:error, "You are not authorized to view this conversation.")
          |> push_navigate(to: ~p"/")}
        end
    end

  end

  def render(assigns) do
    ~H"""
     <Layouts.artsy_main flash={@flash} nav_categories={@nav_categories}>
    <div>
      <h1>Conversation {@conversation.id}</h1>
      <!-- Conversation details and messages would go here -->
      </div>
      <div class="div" id="old_messages">
      <ul id='msg-list' phx-update="stream">
          <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
            <b><%= message.actor_type %>:</b>
            <%= message.body %>
        </li>
    </ul>

        <.form for={@form} id="new_msg" phx-change="validate_msg" phx-submit="post_msg">
          <.input field={@form[:body]} type="text" placeholder="Type your message..." phx-debounce="2000"/>
          <.button_artsy variant="primary" size="block" type="submit">Send</.button_artsy>
        </.form>
      </div>
       </Layouts.artsy_main>
    """
  end

  # def get_username(user_id) do
  #   case ArtsyNeighbor.Accounts.get_user(user_id) do
  #     nil -> "Unknown User"
  #     user ->
  #       username = if user.username != nil and user.username != "", do: user.username, else: user.email
  #   end
  # end

  def handle_event("validate_msg", %{"conversation_event" => params}, socket) do
    changeset =
      %ConversationEvent{}
      |> ConversationEvent.changeset(params)
      |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("post_msg", %{"conversation_event" => %{"body" => body}} = params, socket) do
    conversation = socket.assigns.conversation
    sender = socket.assigns.current_scope.user

    actor_type = if sender.id == conversation.artist_id, do: :vendor, else: :buyer

    case Conversations.create_conversation_event(%{
      conversation_id: conversation.id,
      actor_id: sender.id,
      actor_type: actor_type,
      event_type: "message",
      body: body
    }) do
      {:ok, event} ->
          {:noreply, stream_insert(socket, :messages, event)}
      {:error, changeset} ->
           {:noreply, assign(socket, :form, to_form(changeset))}
    end

  end

end
