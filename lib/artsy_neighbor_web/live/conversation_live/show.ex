defmodule ArtsyNeighborWeb.ConversationLive.Show do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Conversations.ConversationEvent
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Artists

  import ArtsyNeighborWeb.CustomComponents, only: [button_artsy: 1, back: 1]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       message_key: 0,
       schedule_pickup_order_id: nil,
       add_item_order_id: nil,
       vendor_products: []
     )}
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

        is_system = conversation.conversation_type == :system

        authorized =
          (is_system && conversation.user_id == current_user.id) or
            (not is_system && conversation.buyer_id == current_user.id) or
            (not is_system && artist && artist.id == conversation.artist_id)

        if authorized do
          conversation = Conversations.get_conversation_with_participants(conversation.id)

          {current_role, other_name, other_thumbnail} =
            if is_system do
              platform = Application.get_env(:artsy_neighbor, :platform_name, "Artsy Neighbour")
              {:user, platform, nil}
            else
              role = if current_user.id == conversation.buyer_id, do: :buyer, else: :vendor

              {name, thumb} =
                if role == :buyer do
                  {conversation.artist.nickname,
                   List.first(conversation.artist.artist_images, %{path: nil}).path}
                else
                  buyer = conversation.buyer
                  {buyer.username || buyer.email, nil}
                end

              {role, name, thumb}
            end

          if connected?(socket) do
            Conversations.subscribe_to_conversation(conversation.id)
            Conversations.mark_conversation_read(conversation, current_role, current_user.id)
          end

          msg_changeset =
            ConversationEvent.message_changeset(%ConversationEvent{event_type: :message}, %{})

          socket =
            socket
            |> stream(:messages, Conversations.list_events_for_conversation(conversation.id))
            |> assign(:conversation, conversation)
            |> assign(:is_system, is_system)
            |> assign(:current_role, current_role)
            |> assign(:other_name, other_name)
            |> assign(:other_thumbnail, other_thumbnail)
            |> assign(:form, to_form(msg_changeset))
            |> assign(
              :open_orders,
              if(is_system,
                do: [],
                else: Orders.list_open_orders_for_conversation(conversation.id)
              )
            )

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
    <Layouts.artsy_main
      flash={@flash}
      nav_categories={@nav_categories}
      current_scope={@current_scope}
      has_unread={@has_unread_messages}
      pending_reviews_as_buyer={@pending_reviews_as_buyer}
      pending_reviews_as_vendor={@pending_reviews_as_vendor}
    >
      <div class="max-w-5xl mx-auto px-4 py-6">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
          <%!-- Left: chat panel --%>
          <div class="lg:col-span-2">
            <%!-- Conversation header --%>
            <div class="flex items-center gap-3 mb-6 pb-4 border-b border-base-200">
              <div class="avatar placeholder">
                <div class="w-11 h-11 rounded-full overflow-hidden bg-base-300 flex items-center justify-center">
                  <%= if @is_system do %>
                    <span class="text-lg text-primary">✦</span>
                  <% else %>
                    <%= if @other_thumbnail do %>
                      <img src={@other_thumbnail} class="w-full h-full object-cover" />
                    <% else %>
                      <span class="text-lg font-bold text-base-content">
                        {String.first(@other_name)}
                      </span>
                    <% end %>
                  <% end %>
                </div>
              </div>
              <div>
                <h1 class="text-lg font-bold text-base-content">{@other_name}</h1>
                <p class="text-xs text-base-content/50">
                  <%= if @is_system do %>
                    Platform notifications
                  <% else %>
                    {if @current_role == :buyer, do: "Artist", else: "Buyer"}
                  <% end %>
                </p>
              </div>
            </div>

            <%!-- Message thread --%>
            <ul
              id="msg-list"
              phx-update="stream"
              phx-hook="ScrollToBottom"
              class="flex flex-col gap-1 mb-6 overflow-y-auto max-h-[60vh]"
            >
              <li :for={{dom_id, message} <- @streams.messages} id={dom_id}>
                <%= if message.event_type == :status_change or @is_system do %>
                  <%!-- Status-change events and all system-inbox messages render as
                       banners with linkify so URLs become clickable links. --%>
                  <div class="my-4 bg-secondary/10 border-l-4 border-secondary rounded-r-lg px-4 py-3 text-sm text-base-content whitespace-pre-wrap">
                    {linkify(message.body)}
                  </div>
                <% else %>
                  <% is_mine = message.actor_type == @current_role %>
                  <% my_role_label = if @current_role == :buyer, do: "Buyer", else: "Artist" %>
                  <% other_role_label = if @current_role == :buyer, do: "Artist", else: "Buyer" %>
                  <div class={["chat", if(is_mine, do: "chat-end", else: "chat-start")]}>
                    <%= if !is_mine do %>
                      <div class="chat-image avatar">
                        <div class="w-8 rounded-full overflow-hidden bg-base-300 flex items-center justify-center">
                          <%= if @other_thumbnail do %>
                            <img src={@other_thumbnail} class="w-full h-full object-cover" />
                          <% else %>
                            <span class="text-xs font-bold text-base-content">
                              {String.first(@other_name)}
                            </span>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                    <div class="chat-header text-xs text-base-content/50 mb-0.5">
                      {if is_mine,
                        do: "You (#{my_role_label})",
                        else: "#{@other_name} (#{other_role_label})"}
                    </div>
                    <div class={[
                      "chat-bubble",
                      if(is_mine, do: "chat-bubble-info", else: "chat-bubble-neutral")
                    ]}>
                      {message.body}
                    </div>
                    <div class="chat-footer opacity-50 text-xs mt-0.5">
                      {format_message_time(message.inserted_at)}
                    </div>
                  </div>
                <% end %>
              </li>
            </ul>

            <%!-- Compose area — hidden for system conversations (users cannot reply to the platform) --%>
            <div :if={not @is_system} class="border-t border-base-200 pt-4">
              <.form
                for={@form}
                id={"new_msg-#{@message_key}"}
                phx-change="validate_msg"
                phx-submit="post_msg"
              >
                <div class="flex gap-2 items-end">
                  <div class="flex-1">
                    <.input
                      field={@form[:body]}
                      type="text"
                      placeholder="Type your message..."
                      phx-debounce="2000"
                      label=""
                    />
                  </div>
                  <button type="submit" class="btn btn-primary mb-2">Send</button>
                </div>
              </.form>
            </div>
          </div>

          <%!-- Right: order sidebar (only when there are open orders) --%>
          <div :if={length(@open_orders) > 0} class="lg:col-span-1">
            <div class="sticky top-4 flex flex-col gap-4">
              <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wide">
                Open Orders
              </h2>
              <%= for order <- @open_orders do %>
                <div class="bg-base-200 rounded-xl p-4 flex flex-col gap-3">
                  <%!-- Items --%>
                  <ul class="flex flex-col gap-2">
                    <%= for item <- order.items do %>
                      <li class="flex items-center gap-3">
                        <div class="w-12 h-12 rounded-lg overflow-hidden bg-base-300 shrink-0">
                          <%= if thumb = List.first(item.product && item.product.product_images) do %>
                            <img
                              src={thumb.path}
                              alt={item.product_title}
                              class="w-full h-full object-cover"
                            />
                          <% else %>
                            <div class="w-full h-full flex items-center justify-center text-base-content/30 text-xs">
                              ?
                            </div>
                          <% end %>
                        </div>
                        <div class="flex-1 flex items-center justify-between gap-1 min-w-0">
                          <span class="text-sm text-base-content leading-tight truncate">
                            {item.product_title}
                          </span>
                          <div class="flex items-center gap-1 shrink-0">
                            <button
                              phx-click="remove_order_item"
                              phx-value-order-id={order.id}
                              phx-value-item-id={item.id}
                              class="btn btn-ghost btn-xs text-base-content/50 hover:text-error"
                              title={
                                if item.quantity == 1, do: "Remove item", else: "Decrease quantity"
                              }
                            >
                              −
                            </button>
                            <span class="text-sm font-medium w-4 text-center">{item.quantity}</span>
                            <button
                              phx-click="increment_order_item"
                              phx-value-order-id={order.id}
                              phx-value-item-id={item.id}
                              class="btn btn-ghost btn-xs text-base-content/50 hover:text-primary"
                              title="Increase quantity"
                            >
                              +
                            </button>
                          </div>
                        </div>
                      </li>
                    <% end %>
                  </ul>

                  <%!-- Total + status --%>
                  <div class="flex items-center justify-between">
                    <span class="font-bold text-base-content">
                      CA${Decimal.to_string(order.total)}
                    </span>
                    <span class={[
                      "badge badge-sm",
                      order.status == :requested && "badge-warning",
                      order.status == :confirmed && "badge-success"
                    ]}>
                      {order.status}
                    </span>
                  </div>

                  <%!-- Pickup details — visible to both roles when scheduled --%>
                  <div
                    :if={order.status == :confirmed && order.pickup_scheduled_at != nil}
                    class="bg-base-100 rounded-lg p-3 flex flex-col gap-1"
                  >
                    <p class="text-xs font-semibold text-base-content/60 mb-0.5">
                      {if order.pickup_date || order.pickup_time,
                        do: "Pick-up Scheduled",
                        else: "Pick-up Info"}
                    </p>
                    <p :if={order.pickup_date} class="text-xs text-base-content/80">
                      <span class="font-medium">Date:</span> {order.pickup_date}
                    </p>
                    <p :if={order.pickup_time} class="text-xs text-base-content/80">
                      <span class="font-medium">Time:</span> {order.pickup_time}
                    </p>
                    <p class="text-xs text-base-content/80">
                      <span class="font-medium">Address:</span> {order.pickup_address}
                    </p>
                    <p :if={order.pickup_instructions} class="text-xs text-base-content/80">
                      <span class="font-medium">Notes:</span> {order.pickup_instructions}
                    </p>
                  </div>

                  <%!-- Complete purchase — buyer only, available once the vendor has confirmed.
                       Always visible here (not just in the chat message) so the buyer isn't
                       stuck hunting through the conversation for the link. --%>
                  <div
                    :if={
                      @current_role == :buyer && order.status == :confirmed && order.complete_token
                    }
                    class="bg-base-100 rounded-lg p-3 flex flex-col gap-2"
                  >
                    <p class="text-xs text-base-content/70">
                      Only tap this once you've received your item(s) in hand and are ready to pay — it will initiate payment.
                    </p>
                    <.button_artsy
                      variant="primary"
                      size="sm"
                      navigate={~p"/orders/#{order.id}/complete-purchase/#{order.complete_token}"}
                    >
                      Complete Purchase — CA${Decimal.to_string(order.total)}
                    </.button_artsy>
                  </div>

                  <%!-- Vendor actions --%>
                  <div :if={@current_role == :vendor} class="flex flex-col gap-2">
                    <.button_artsy
                      :if={order.status == :requested}
                      variant="primary"
                      size="sm"
                      phx-click="confirm_order"
                      phx-value-id={order.id}
                    >
                      Confirm Order
                    </.button_artsy>

                    <%!-- Schedule / reschedule pick-up (confirmed orders, vendor) --%>
                    <div :if={order.status == :confirmed}>
                      <%= if @schedule_pickup_order_id == order.id do %>
                        <form
                          phx-submit="submit_schedule"
                          class="flex flex-col gap-2 bg-base-100 rounded-lg p-3"
                        >
                          <p class="text-xs font-semibold text-base-content/70">
                            {if order.pickup_scheduled_at,
                              do: "Reschedule Pick-up",
                              else: "Schedule Pick-up"}
                          </p>
                          <p class="text-[11px] text-base-content/50 -mt-1">
                            Date and time are optional — leave blank if you already agreed on a time in chat.
                          </p>
                          <input
                            type="date"
                            name="schedule[date]"
                            min={min_pickup_date()}
                            class="input input-bordered input-sm w-full"
                          />
                          <input
                            type="time"
                            name="schedule[time]"
                            class="input input-bordered input-sm w-full"
                          />
                          <input
                            type="text"
                            name="schedule[address]"
                            placeholder="Pick-up address"
                            required
                            value={default_pickup_address(order, @current_scope.artist)}
                            class="input input-bordered input-sm w-full"
                          />
                          <textarea
                            name="schedule[instructions]"
                            placeholder="Special instructions (optional)"
                            rows="2"
                            class="textarea textarea-bordered textarea-sm w-full"
                          >{default_pickup_instructions(order, @current_scope.artist)}</textarea>
                          <label class="flex items-center gap-2 text-xs text-base-content/60">
                            <input
                              type="checkbox"
                              name="schedule[save_default]"
                              value="true"
                              class="checkbox checkbox-xs"
                            /> Save as my default pickup info
                          </label>
                          <div class="flex gap-2">
                            <button type="submit" class="btn btn-primary btn-sm flex-1">Send</button>
                            <button
                              type="button"
                              phx-click="cancel_schedule"
                              class="btn btn-ghost btn-sm"
                            >
                              Cancel
                            </button>
                          </div>
                        </form>
                      <% else %>
                        <.button_artsy
                          variant="secondary"
                          size="sm"
                          phx-click="open_schedule_form"
                          phx-value-id={order.id}
                        >
                          {if order.pickup_scheduled_at,
                            do: "Reschedule Pick-up",
                            else: "Schedule Pick-up"}
                        </.button_artsy>
                        <button
                          :if={order.pickup_scheduled_at != nil}
                          phx-click="cancel_pickup"
                          phx-value-id={order.id}
                          class="btn btn-ghost btn-sm w-full text-warning"
                        >
                          Cancel Pick-up
                        </button>
                      <% end %>
                    </div>

                    <%!-- Add item to order (vendor) — e.g. buyer sees more work in person and wants it too --%>
                    <div :if={order.status in [:requested, :confirmed]}>
                      <%= if @add_item_order_id == order.id do %>
                        <div class="flex flex-col gap-2 bg-base-100 rounded-lg p-3">
                          <p class="text-xs font-semibold text-base-content/70">
                            Add an item to this order
                          </p>
                          <div class="flex flex-col gap-1 max-h-48 overflow-y-auto">
                            <button
                              :for={product <- @vendor_products}
                              :if={
                                !(product.unique_work &&
                                    Enum.any?(order.items, &(&1.product_id == product.id)))
                              }
                              type="button"
                              phx-click="vendor_add_item"
                              phx-value-order-id={order.id}
                              phx-value-product-id={product.id}
                              class="flex items-center gap-2 text-left px-2 py-1.5 rounded-lg hover:bg-base-200 w-full"
                            >
                              <div class="w-8 h-8 rounded overflow-hidden bg-base-300 shrink-0 flex items-center justify-center">
                                <img
                                  :if={thumb = List.first(product.product_images)}
                                  src={thumb.path}
                                  class="w-full h-full object-cover"
                                />
                              </div>
                              <span class="flex-1 truncate text-xs text-base-content">
                                {product.title}
                              </span>
                              <span class="text-xs text-base-content/60 shrink-0">
                                CA${Decimal.to_string(product.price)}
                              </span>
                            </button>
                            <p
                              :if={@vendor_products == []}
                              class="text-xs text-base-content/50 px-2 py-1"
                            >
                              You have no available products to add.
                            </p>
                          </div>
                          <button
                            type="button"
                            phx-click="cancel_add_item"
                            class="btn btn-ghost btn-sm"
                          >
                            Cancel
                          </button>
                        </div>
                      <% else %>
                        <.button_artsy
                          variant="secondary"
                          size="sm"
                          phx-click="open_add_item_form"
                          phx-value-id={order.id}
                        >
                          + Add Item
                        </.button_artsy>
                      <% end %>
                    </div>

                    <.button_artsy
                      :if={order.status in [:requested, :confirmed]}
                      variant="ghost"
                      size="sm"
                      phx-click="cancel_order"
                      phx-value-id={order.id}
                    >
                      Cancel Order
                    </.button_artsy>
                  </div>

                  <%!-- Buyer actions --%>
                  <div
                    :if={@current_role == :buyer && order.status in [:requested, :confirmed]}
                    class="flex flex-col gap-2"
                  >
                    <button
                      :if={order.pickup_scheduled_at != nil}
                      phx-click="cancel_pickup"
                      phx-value-id={order.id}
                      class="btn btn-ghost btn-sm w-full text-warning"
                    >
                      Request New Time
                    </button>
                    <.button_artsy
                      variant="ghost"
                      size="sm"
                      phx-click="cancel_order"
                      phx-value-id={order.id}
                    >
                      Cancel Order
                    </.button_artsy>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
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
      |> ConversationEvent.message_changeset(params)
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
        msg_changeset =
          ConversationEvent.message_changeset(%ConversationEvent{event_type: :message}, %{})

        {:noreply,
         socket
         |> assign(:form, to_form(msg_changeset))
         |> assign(:message_key, System.unique_integer())}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("open_schedule_form", %{"id" => id}, socket) do
    {:noreply, assign(socket, :schedule_pickup_order_id, String.to_integer(id))}
  end

  def handle_event("cancel_schedule", _params, socket) do
    {:noreply, assign(socket, :schedule_pickup_order_id, nil)}
  end

  def handle_event("submit_schedule", %{"schedule" => params}, socket) do
    order_id = socket.assigns.schedule_pickup_order_id
    order = Enum.find(socket.assigns.open_orders, &(&1.id == order_id))
    artist = socket.assigns.current_scope.artist

    date_raw = String.trim(params["date"] || "")
    time_raw = String.trim(params["time"] || "")
    address = String.trim(params["address"] || "")
    instructions = String.trim(params["instructions"] || "")
    save_default = params["save_default"] == "true"

    cond do
      address == "" ->
        {:noreply, put_flash(socket, :error, "Pick-up address is required.")}

      date_raw != "" and past_pickup_date?(date_raw) ->
        {:noreply, put_flash(socket, :error, "Pick-up date can't be in the past.")}

      true ->
        if save_default do
          Artists.update_pickup_defaults(artist, %{
            default_pickup_address: address,
            delivery_info: Map.put(artist.delivery_info || %{}, "pickup", instructions)
          })
        end

        completion_url = url(~p"/orders/#{order.id}/complete-purchase/#{order.complete_token}")
        date = format_picked_date(date_raw)
        time = format_picked_time(time_raw)

        case Orders.schedule_pickup(order, %{
               date: date,
               time: time,
               address: address,
               instructions: instructions,
               completion_url: completion_url
             }) do
          {:ok, _event} ->
            {:noreply, assign(socket, :schedule_pickup_order_id, nil)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not send schedule. Please try again.")}
        end
    end
  end

  def handle_event("remove_order_item", %{"order-id" => order_id, "item-id" => item_id}, socket) do
    order = Orders.get_order!(order_id)
    actor_type = socket.assigns.current_role

    case Orders.remove_order_item(order, String.to_integer(item_id), actor_type) do
      {:ok, _} -> {:noreply, reload_open_orders(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not remove item.")}
    end
  end

  def handle_event(
        "increment_order_item",
        %{"order-id" => order_id, "item-id" => item_id},
        socket
      ) do
    order = Orders.get_order!(order_id)
    actor_type = socket.assigns.current_role

    case Orders.increment_order_item(order, String.to_integer(item_id), actor_type) do
      {:ok, _} -> {:noreply, reload_open_orders(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update quantity.")}
    end
  end

  def handle_event("confirm_order", %{"id" => id}, socket) do
    order = Orders.get_order!(id)

    case Orders.confirm_order(order) do
      {:ok, confirmed_order} ->
        if confirmed_order.pickup_date do
          completion_url =
            url(
              ~p"/orders/#{confirmed_order.id}/complete-purchase/#{confirmed_order.complete_token}"
            )

          Orders.schedule_pickup(confirmed_order, %{
            date: confirmed_order.pickup_date,
            time: confirmed_order.pickup_time,
            address: confirmed_order.pickup_address,
            instructions: confirmed_order.pickup_instructions || "",
            completion_url: completion_url
          })
        end

        {:noreply, reload_open_orders(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not confirm order.")}
    end
  end

  def handle_event("cancel_pickup", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    actor_type = socket.assigns.current_role

    case Orders.cancel_pickup(order, actor_type) do
      {:ok, _} -> {:noreply, reload_open_orders(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not cancel pick-up.")}
    end
  end

  def handle_event("cancel_order", %{"id" => id}, socket) do
    order = Orders.get_order!(id)
    actor_type = socket.assigns.current_role

    case Orders.cancel_order(order, actor_type) do
      {:ok, _order} ->
        {:noreply, reload_open_orders(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel order.")}
    end
  end

  # Bug fix: this used to call Products.get_products_by_artist/1 — the
  # public-scoped variant (only_available/1: requires the product
  # :available AND the artist :active). That's wrong here: this is the
  # vendor managing their own already-open order/conversation, not a
  # public listing, and on_mount(:require_vendor, ...) doesn't check
  # artist status, so a self-deactivated or admin-removed vendor could
  # still reach this page and see zero products to add — even ones
  # genuinely :available — purely because their own artist record wasn't
  # :active. The vendor dashboard already avoids this same trap by using
  # get_products_by_artist_all_status/1 for exactly this reason; this
  # call site just hadn't been audited for it.
  def handle_event("open_add_item_form", %{"id" => id}, socket) do
    artist = socket.assigns.current_scope.artist
    products = Products.get_products_by_artist_all_status(artist.id)

    {:noreply,
     socket
     |> assign(:add_item_order_id, String.to_integer(id))
     |> assign(:vendor_products, products)}
  end

  def handle_event("cancel_add_item", _params, socket) do
    {:noreply, assign(socket, :add_item_order_id, nil)}
  end

  def handle_event(
        "vendor_add_item",
        %{"order-id" => order_id, "product-id" => product_id},
        socket
      ) do
    order = Orders.get_order!(order_id)
    product = Products.get_product!(product_id)

    case Orders.add_item_to_order(order, product, :vendor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:add_item_order_id, nil)
         |> reload_open_orders()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add item.")}
    end
  end

  def handle_info({:new_message, conv_event}, socket) do
    socket =
      if conv_event.event_type == :status_change do
        reload_open_orders(socket)
      else
        socket
      end

    {:noreply, stream_insert(socket, :messages, conv_event)}
  end

  defp reload_open_orders(socket) do
    assign(
      socket,
      :open_orders,
      Orders.list_open_orders_for_conversation(socket.assigns.conversation.id)
    )
  end

  # Formats a message timestamp for display next to each bubble.
  # Shows time only (e.g. "2:34 PM") for messages sent today,
  # and date + time for older messages (e.g. "Apr 12, 2:34 PM").
  # Escapes the body text then wraps any http(s) URLs in clickable anchor tags.
  defp linkify(text) do
    escaped = Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string()

    linked =
      Regex.replace(~r/https?:\/\/[^\s]+/, escaped, fn url ->
        ~s(<a href="#{url}" target="_blank" class="underline text-primary break-all">#{url}</a>)
      end)

    Phoenix.HTML.raw(linked)
  end

  defp format_message_time(nil), do: ""

  defp format_message_time(dt) do
    timezone = Application.fetch_env!(:artsy_neighbor, :timezone)
    # Convert from UTC to local time before formatting.
    local = DateTime.shift_zone!(dt, timezone)
    today = DateTime.now!(timezone) |> DateTime.to_date()
    date = DateTime.to_date(local)

    if date == today do
      Calendar.strftime(local, "%I:%M %p")
    else
      Calendar.strftime(local, "%b %-d, %I:%M %p")
    end
  end

  # Today's date in the app's display timezone, as an ISO string — used as
  # the `min` attribute on the pick-up date input so past dates can't be picked.
  defp min_pickup_date do
    timezone = Application.fetch_env!(:artsy_neighbor, :timezone)
    DateTime.now!(timezone) |> DateTime.to_date() |> Date.to_iso8601()
  end

  defp past_pickup_date?(iso_date) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} ->
        timezone = Application.fetch_env!(:artsy_neighbor, :timezone)
        today = DateTime.now!(timezone) |> DateTime.to_date()
        Date.compare(date, today) == :lt

      _ ->
        false
    end
  end

  # Formats the raw "YYYY-MM-DD" value from the date input into a human
  # string for storage/display, e.g. "June 5, 2026". Falls back to the raw
  # value if it somehow doesn't parse.
  defp format_picked_date(""), do: ""

  defp format_picked_date(iso_date) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} -> Calendar.strftime(date, "%B %-d, %Y")
      _ -> iso_date
    end
  end

  # Formats the raw "HH:MM" value from the time input into a human string,
  # e.g. "2:00 PM". Falls back to the raw value if it doesn't parse.
  defp format_picked_time(""), do: ""

  defp format_picked_time(hh_mm) do
    with [h, m | _] <- String.split(hh_mm, ":"),
         {hour, ""} <- Integer.parse(h),
         {minute, ""} <- Integer.parse(m),
         {:ok, time} <- Time.new(hour, minute, 0) do
      Calendar.strftime(time, "%-I:%M %p")
    else
      _ -> hh_mm
    end
  end

  # Prefills the schedule form's address field: this order's own previously
  # used address (rescheduling) takes precedence over the vendor's saved default.
  defp default_pickup_address(order, artist) do
    cond do
      order.pickup_address not in [nil, ""] -> order.pickup_address
      artist -> artist.default_pickup_address || ""
      true -> ""
    end
  end

  defp default_pickup_instructions(order, artist) do
    cond do
      order.pickup_instructions not in [nil, ""] -> order.pickup_instructions
      artist -> get_in(artist.delivery_info || %{}, ["pickup"]) || ""
      true -> ""
    end
  end
end
