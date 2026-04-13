defmodule ArtsyNeighborWeb.ConversationLive.Index do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Accounts.Scope

  import ArtsyNeighborWeb.CustomComponents, only: [ button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do
     if connected?(socket) do
       Conversations.subscribe_to_user_conversations(socket.assigns.current_scope.user.id)
    end
    {:ok, assign(socket, :has_new, MapSet.new())}
  end

  def handle_params(_params, _uri, socket) do
    current_user = socket.assigns.current_scope.user
    conversations_as_buyer = Conversations.list_conversations_for_buyer(current_user.id)
    conversations_as_vendor =
      if socket.assigns.current_scope.artist do
        Conversations.list_conversations_for_artist(socket.assigns.current_scope.artist.id)
      else
        []
      end

    {:noreply,
      socket
      |> assign(:conversations_as_buyer, conversations_as_buyer)
      |> assign(:conversations_as_vendor, conversations_as_vendor)
    }
  end

  def handle_info({:new_conversation, conversation}, socket) do
    conversation = Conversations.preload_participants(conversation)
    {:noreply, update(socket, :conversations_as_vendor, &[conversation | &1])}
  end

  def handle_info({:conversation_updated, event}, socket) do
    {:noreply, update(socket, :has_new, &MapSet.put(&1, event.conversation_id))}
  end

  if Mix.env() == :dev do
    def handle_event("delete_conversation_dev", %{"id" => id}, socket) do
      conversation = Conversations.get_conversation!(id)
      Conversations.delete_conversation_dev(conversation)
      {:noreply, update(socket, :conversations_as_vendor, &Enum.reject(&1, fn c -> c.id == conversation.id end))}
    end
  end


  def render(assigns) do
    ~H"""
     <Layouts.artsy_main flash={@flash} nav_categories={@nav_categories}>
    <div>
      <h1>Your Conversations</h1>
      <h2>Buying</h2>
      <ul id="conversations-buyer">
        <li :for={conversation <- @conversations_as_buyer} id={"conv-buyer-#{conversation.id}"} class="flex items-center gap-2">
          <.link navigate={~p"/messages/#{conversation.id}"} class="flex items-center gap-3">
            <img
              src={List.first(conversation.artist.artist_images, %{path: "/images/placeholder.jpg"}).path}
              class="w-10 h-10 rounded-full object-cover"
            />
            {conversation.artist.nickname}
            <span :if={MapSet.member?(@has_new, conversation.id)} class="badge badge-error badge-xs"></span>
          </.link>
        </li>
      </ul>

      <h2 :if={@current_scope.artist}>Selling</h2>
      <ul id="conversations-vendor">
        <li :for={conversation <- @conversations_as_vendor} id={"conv-vendor-#{conversation.id}"} class="flex items-center gap-2">
          <.link navigate={~p"/messages/#{conversation.id}"} class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-full bg-base-300 flex items-center justify-center text-base-content font-bold">
              {String.first(conversation.buyer.username || conversation.buyer.email)}
            </div>
            {conversation.buyer.username || conversation.buyer.email}
            <span :if={MapSet.member?(@has_new, conversation.id)} class="badge badge-error badge-xs"></span>
          </.link>
          <%= if Mix.env() == :dev do %>
            <button phx-click="delete_conversation_dev" phx-value-id={conversation.id} class="btn btn-xs btn-error">✕</button>
          <% end %>
        </li>
      </ul>

      </div>
      </Layouts.artsy_main>
    """
  end

end
