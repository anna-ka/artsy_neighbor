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

          conversation = Conversations.get_conversation_with_participants(conversation.id)
          current_role = if current_user.id == conversation.buyer_id, do: :buyer, else: :vendor

          if connected?(socket) do
            # Subscribe to new messages in this thread.
            Conversations.subscribe_to_conversation(conversation.id)
            # Mark this conversation as read — stamps the DB and broadcasts
            # {:marked_read, id} to our inbox so the dot disappears there too.
            Conversations.mark_conversation_read(conversation, current_role, current_user.id)
          end

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
    <Layouts.artsy_main flash={@flash} nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread_messages}>
      <div class="max-w-3xl mx-auto px-4 py-6">

        <%!-- Conversation header --%>
        <div class="flex items-center gap-3 mb-6 pb-4 border-b border-base-200">
          <div class="avatar">
            <div class="w-11 h-11 rounded-full overflow-hidden bg-base-300 flex items-center justify-center">
              <%= if @other_thumbnail do %>
                <img src={@other_thumbnail} class="w-full h-full object-cover" />
              <% else %>
                <span class="text-lg font-bold text-base-content">{String.first(@other_name)}</span>
              <% end %>
            </div>
          </div>
          <div>
            <h1 class="text-lg font-bold text-base-content">{@other_name}</h1>
            <p class="text-xs text-base-content/50">
              {if @current_role == :buyer, do: "Artist", else: "Buyer"}
            </p>
          </div>
        </div>

        <%!-- Message thread --%>
        <ul id="msg-list" phx-update="stream" class="flex flex-col gap-1 mb-6">
          <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
            <div class={["chat", if(message.actor_type == @current_role, do: "chat-end", else: "chat-start")]}>
              <%= if message.actor_type != @current_role do %>
                <div class="chat-image avatar">
                  <div class="w-8 rounded-full overflow-hidden bg-base-300 flex items-center justify-center">
                    <%= if @other_thumbnail do %>
                      <img src={@other_thumbnail} class="w-full h-full object-cover" />
                    <% else %>
                      <span class="text-xs font-bold text-base-content">{String.first(@other_name)}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <div class={["chat-bubble", if(message.actor_type == @current_role, do: "chat-bubble-info", else: "chat-bubble-neutral")]}>
                {message.body}
              </div>
              <div class="chat-footer opacity-50 text-xs mt-0.5">
                {format_message_time(message.inserted_at)}
              </div>
            </div>
          </li>
        </ul>

        <%!-- Compose area --%>
        <div class="border-t border-base-200 pt-4">
          <.form for={@form} id={"new_msg-#{@message_key}"} phx-change="validate_msg" phx-submit="post_msg">
            <div class="flex gap-2 items-end">
              <div class="flex-1">
                <.input field={@form[:body]} type="text" placeholder="Type your message..." phx-debounce="2000" label={false} />
              </div>
              <button type="submit" class="btn btn-primary mb-2">Send</button>
            </div>
          </.form>
        </div>

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

  # Formats a message timestamp for display next to each bubble.
  # Shows time only (e.g. "2:34 PM") for messages sent today,
  # and date + time for older messages (e.g. "Apr 12, 2:34 PM").
  defp format_message_time(nil), do: ""
  defp format_message_time(dt) do
    timezone = Application.fetch_env!(:artsy_neighbor, :timezone)
    # Convert from UTC to local time before formatting.
    local = DateTime.shift_zone!(dt, timezone)
    today = DateTime.now!(timezone) |> DateTime.to_date()
    date  = DateTime.to_date(local)

    if date == today do
      Calendar.strftime(local, "%I:%M %p")
    else
      Calendar.strftime(local, "%b %-d, %I:%M %p")
    end
  end

end
