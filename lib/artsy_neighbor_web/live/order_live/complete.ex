defmodule ArtsyNeighborWeb.OrderLive.Complete do
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders

  def mount(%{"id" => id, "token" => token} = _params, _session, socket) do
    order = Orders.get_order!(id)
    buyer = socket.assigns.current_scope.user

    cond do
      order.buyer_id != buyer.id ->
        {:ok,
         socket
         |> put_flash(:error, "You are not authorised to complete this order.")
         |> push_navigate(to: ~p"/messages")}

      order.status != :confirmed ->
        {:ok,
         socket
         |> put_flash(:error, "This order is not waiting for pickup (status: #{order.status}).")
         |> push_navigate(to: ~p"/messages/#{order.conversation_id}")}

      true ->
        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:token, token)
         |> assign(:page_title, "Complete Pickup")}
    end
  end

  def handle_event("cancel_order", _params, socket) do
    order = socket.assigns.order
    case Orders.cancel_order(order, :buyer) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Order cancelled.")
         |> push_navigate(to: ~p"/messages/#{order.conversation_id}")}
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cancel the order. Please try again.")}
    end
  end

  def handle_event("complete_pickup", _params, socket) do
    order = socket.assigns.order
    token = socket.assigns.token

    case Orders.complete_pickup(order, token) do
      {:ok, _order} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pickup complete — thank you!")
         |> push_navigate(to: ~p"/messages/#{order.conversation_id}")}

      {:error, :invalid_token} ->
        {:noreply, put_flash(socket, :error, "This pickup link is invalid.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Something went wrong. Please try again.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash} nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread_messages}>
      <div class="max-w-lg mx-auto px-4 py-12">

        <div class="bg-base-200 rounded-xl p-6 flex flex-col gap-6">

          <div>
            <h1 class="text-2xl font-bold text-base-content mb-1">Complete Purchase</h1>
            <p class="text-sm text-base-content/60">Confirm that you have received the following items from <span class="font-medium">{@order.artist_name}</span>.</p>
          </div>

          <%!-- Order items --%>
          <ul class="flex flex-col gap-3">
            <%= for item <- @order.items do %>
              <li class="flex items-center gap-3">
                <div class="w-14 h-14 rounded-lg overflow-hidden bg-base-300 shrink-0">
                  <%= if thumb = List.first(item.product && item.product.product_images) do %>
                    <img src={thumb.path} alt={item.product_title} class="w-full h-full object-cover" />
                  <% else %>
                    <div class="w-full h-full flex items-center justify-center text-base-content/30 text-xs">?</div>
                  <% end %>
                </div>
                <div class="flex-1">
                  <p class="text-sm font-medium text-base-content">{item.product_title}</p>
                  <p class="text-xs text-base-content/60">CA${Decimal.to_string(item.unit_price)} each</p>
                </div>
                <span :if={item.quantity > 1} class="text-sm text-base-content/60">×{item.quantity}</span>
              </li>
            <% end %>
          </ul>

          <%!-- Total --%>
          <div class="flex justify-between items-center border-t border-base-content/10 pt-4">
            <span class="text-sm text-base-content/60">Total price </span>
            <span class="text-lg font-bold text-base-content">CA${Decimal.to_string(@order.total)}</span>
          </div>

          <%!-- Confirm button --%>
          <button phx-click="complete_pickup" class="btn btn-primary w-full">
            Complete purchase — CA${Decimal.to_string(@order.total)}
          </button>

          <p class="text-xs text-center text-base-content/40">
            Only click once you have physically received your items.
          </p>

          <div class="border-t border-base-content/10 pt-4">
            <button phx-click="cancel_order" data-confirm="Are you sure you want to cancel this order?" class="btn btn-ghost btn-sm w-full text-error">
              Cancel order
            </button>
          </div>

        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
