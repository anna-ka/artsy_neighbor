defmodule ArtsyNeighborWeb.ConversationLive.Index do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Accounts.Scope

  import ArtsyNeighborWeb.CustomComponents, only: [ button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do
    user   = socket.assigns.current_scope.user
    artist = socket.assigns.current_scope.artist

    if connected?(socket) do
      Conversations.subscribe_to_user_conversations(user.id)
    end

    # Load unread conversation IDs from the DB so the dots survive page navigation.
    buyer_unread  = Conversations.list_unread_conversation_ids_for_buyer(user.id)
    vendor_unread = if artist do
      Conversations.list_unread_conversation_ids_for_artist(artist.id)
    else
      []
    end

    # Merge both lists into a MapSet (no duplicates, fast membership checks).
    all_unread = MapSet.new(buyer_unread ++ vendor_unread)

    socket =
      socket
      # convs_with_new drives the per-conversation dots in the list.
      |> assign(:convs_with_new, all_unread)
      # has_unread_messages drives the nav badge in the layout.
      |> assign(:has_unread_messages, not Enum.empty?(all_unread))

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    current_user   = socket.assigns.current_scope.user
    convs_with_new = socket.assigns.convs_with_new

    conversations_as_buyer =
      Conversations.list_conversations_for_buyer(current_user.id)
      |> sort_unread_first(convs_with_new)

    conversations_as_vendor =
      if socket.assigns.current_scope.artist do
        Conversations.list_conversations_for_artist(socket.assigns.current_scope.artist.id)
        |> sort_unread_first(convs_with_new)
      else
        []
      end

    {:noreply,
      socket
      |> assign(:conversations_as_buyer, conversations_as_buyer)
      |> assign(:conversations_as_vendor, conversations_as_vendor)
    }
  end

  # Splits the list into two groups — unread first, then read — while preserving
  # the last_event_at ordering within each group.
  defp sort_unread_first(conversations, convs_with_new) do
    {unread, read} = Enum.split_with(conversations, fn c -> MapSet.member?(convs_with_new, c.id) end)
    unread ++ read
  end

  def handle_info({:new_conversation, conversation}, socket) do
    conversation = Conversations.preload_participants(conversation)
    {:noreply, update(socket, :conversations_as_vendor, fn current_list -> [conversation | current_list] end)}
  end

  def handle_info({:conversation_updated, event}, socket) do
    # A new message arrived — add this conversation to the unread set.
    updated_set = MapSet.put(socket.assigns.convs_with_new, event.conversation_id)
    {:noreply,
      socket
      |> assign(:convs_with_new, updated_set)
      |> assign(:has_unread_messages, true)}
  end

  def handle_info({:marked_read, conversation_id}, socket) do
    # The user opened this conversation — remove it from the unread set.
    updated_set = MapSet.delete(socket.assigns.convs_with_new, conversation_id)
    {:noreply,
      socket
      |> assign(:convs_with_new, updated_set)
      |> assign(:has_unread_messages, not Enum.empty?(updated_set))}
  end

  if Mix.env() == :dev do
    def handle_event("delete_conversation_dev", %{"id" => id}, socket) do
      conversation = Conversations.get_conversation!(id)
      Conversations.delete_conversation_dev(conversation)
      {:noreply, update(socket, :conversations_as_vendor, &Enum.reject(&1, fn c -> c.id == conversation.id end))}
    end
  end


  # Formats last_event_at for display in the inbox list:
  # - nil            → "No messages yet"
  # - today          → "2:34 PM"
  # - this year      → "Apr 12"
  # - older          → "Apr 12, 2025"
  defp format_last_event_at(nil), do: "No messages yet"
  defp format_last_event_at(dt) do
    timezone = Application.fetch_env!(:artsy_neighbor, :timezone)
    # Convert from UTC to local time before formatting.
    local = DateTime.shift_zone!(dt, timezone)
    today = DateTime.now!(timezone) |> DateTime.to_date()
    date  = DateTime.to_date(local)

    cond do
      date == today           -> Calendar.strftime(local, "%I:%M %p")
      date.year == today.year -> Calendar.strftime(local, "%b %-d")
      true                    -> Calendar.strftime(local, "%b %-d, %Y")
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread_messages}>
      <div class="max-w-2xl mx-auto px-4 py-8">
        <h1 class="text-2xl font-bold mb-6 text-base-content">Your Messages</h1>

        <%!-- Buying section --%>
        <section class="mb-8">
          <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50 mb-3">Buying</h2>
          <ul class="divide-y divide-base-200">
            <li :for={conversation <- @conversations_as_buyer} id={"conv-buyer-#{conversation.id}"}>
              <.link navigate={~p"/messages/#{conversation.id}"}
                class="flex items-center gap-4 py-3 px-2 rounded-lg hover:bg-base-200 transition-colors">
                <div class="avatar">
                  <div class="w-12 h-12 rounded-full">
                    <img src={List.first(conversation.artist.artist_images, %{path: "/images/placeholder.jpg"}).path} />
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="font-semibold text-base-content truncate">{conversation.artist.nickname}</p>
                  <p class="text-xs text-base-content/50">{format_last_event_at(conversation.last_event_at)}</p>
                </div>
                <span :if={MapSet.member?(@convs_with_new, conversation.id)} class="badge badge-error badge-xs"></span>
              </.link>
            </li>
          </ul>
          <p :if={@conversations_as_buyer == []} class="text-base-content/50 text-sm py-3 px-2">
            No conversations yet. Browse artists and send a message!
          </p>
        </section>

        <%!-- Selling section — vendors only --%>
        <section :if={@current_scope.artist}>
          <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50 mb-3">Selling</h2>
          <ul class="divide-y divide-base-200">
            <li :for={conversation <- @conversations_as_vendor} id={"conv-vendor-#{conversation.id}"}
                class="flex items-center gap-4 py-3 px-2">
              <.link navigate={~p"/messages/#{conversation.id}"}
                class="flex items-center gap-4 flex-1 rounded-lg hover:bg-base-200 transition-colors">
                <div class="avatar placeholder">
                  <div class="w-12 h-12 rounded-full bg-base-300 text-base-content">
                    <span class="text-lg font-bold">
                      {String.first(conversation.buyer.username || conversation.buyer.email)}
                    </span>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="font-semibold text-base-content truncate">
                    {conversation.buyer.username || conversation.buyer.email}
                  </p>
                  <p class="text-xs text-base-content/50">{format_last_event_at(conversation.last_event_at)}</p>
                </div>
                <span :if={MapSet.member?(@convs_with_new, conversation.id)} class="badge badge-error badge-xs"></span>
              </.link>
              <%= if Mix.env() == :dev do %>
                <button phx-click="delete_conversation_dev" phx-value-id={conversation.id}
                  class="btn btn-xs btn-ghost text-error">✕</button>
              <% end %>
            </li>
          </ul>
          <p :if={@conversations_as_vendor == []} class="text-base-content/50 text-sm py-3 px-2">
            No customer conversations yet.
          </p>
        </section>
      </div>
    </Layouts.artsy_main>
    """
  end

end
