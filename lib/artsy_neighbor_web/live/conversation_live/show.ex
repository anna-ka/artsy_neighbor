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
    {:ok, assign(socket, :message_key, 0)}
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
        artist = socket.assigns.current_scope.artist

        if conversation.buyer_id == current_user.id
          or (artist && artist.id == conversation.artist_id)
        do

          if connected?(socket) do
            Conversations.subscribe_to_conversation(conversation.id)
          end

          conversation = Conversations.get_conversation_with_participants(conversation.id)
          current_role = if current_user.id == conversation.buyer_id, do: :buyer, else: :vendor

          {other_name, other_thumbnail} =
            if current_role == :buyer do
              name = conversation.artist.nickname
              thumb = List.first(conversation.artist.artist_images, %{path: nil}).path
              {name, thumb}
            else
              buyer = conversation.buyer
              {buyer.username || buyer.email, nil}
            end

          msg_changeset = ConversationEvent.changeset(%ConversationEvent{}, %{})

          socket =
            socket
            |> stream(:messages, Conversations.list_events_for_conversation(conversation.id))
            |> assign(:conversation, conversation)
            |> assign(:current_role, current_role)
            |> assign(:other_name, other_name)
            |> assign(:other_thumbnail, other_thumbnail)
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
      <h1>Conversation with {@other_name}</h1>
      <!-- Conversation details and messages would go here -->
      </div>
      <div class="div" id="old_messages">
      <ul id='msg-list' phx-update="stream">
        <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
          <%= if message.actor_type == @current_role do %>
            <b>You ({@current_role}):</b>
          <% else %>
            <div class="flex items-center gap-2">
              <%= if @other_thumbnail do %>
                <img src={@other_thumbnail} class="w-6 h-6 rounded-full object-cover" />
              <% else %>
                <div class="w-6 h-6 rounded-full bg-base-300 flex items-center justify-center text-xs font-bold">
                  {String.first(@other_name)}
                </div>
              <% end %>
              <b>{@other_name} ({message.actor_type}):</b>
            </div>
          <% end %>
          {message.body}
        </li>
      </ul>

        <.form for={@form} id={"new_msg-#{@message_key}"} phx-change="validate_msg" phx-submit="post_msg">
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

    actor_type = socket.assigns.current_role

    case Conversations.create_message_event(
        conversation,
        sender.id,
        actor_type,
        body
      ) do

      {:ok, _event} ->
        msg_changeset = ConversationEvent.changeset(%ConversationEvent{}, %{})
        {:noreply,
          socket
          |> assign(:form, to_form(msg_changeset))
          |> assign(:message_key, System.unique_integer())}
      {:error, changeset} ->
           {:noreply, assign(socket, :form, to_form(changeset))}
    end

  end

  def handle_info({:new_message, conv_event}, socket) do
     {:noreply, stream_insert(socket, :messages, conv_event)}
  end

end
