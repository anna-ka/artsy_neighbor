defmodule ArtsyNeighborWeb.OrderLive.Index do
  # Buyer's order history — all orders, newest first, with status pills.
  # Clicking a row opens the detail page at /orders/:id.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Reviews
  import ArtsyNeighborWeb.OrderFormatters

  def mount(_params, _session, socket) do
    user         = socket.assigns.current_scope.user
    orders       = Orders.list_orders_for_buyer(user.id)
    reviewed_ids = Reviews.reviewed_order_ids_as_buyer(user.id)

    {:ok,
     socket
     |> assign(:orders, orders)
     |> assign(:reviewed_ids, reviewed_ids)
     |> assign(:page_title, "Past Orders")}
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
      <div class="max-w-3xl mx-auto px-4 py-10">
        <h1 class="text-2xl font-bold text-base-content mb-6">Past Orders</h1>

        <div :if={@pending_reviews_as_buyer > 0} class="alert alert-warning mb-6">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <span>
            You have {@pending_reviews_as_buyer} completed order{if @pending_reviews_as_buyer != 1, do: "s"} awaiting your review.
            Click an order below to leave your feedback.
          </span>
        </div>

        <p :if={@orders == []} class="text-base-content/50 py-4">
          No orders yet. Browse artists to get started!
        </p>

        <div class="flex flex-col divide-y divide-base-200">
          <.link
            :for={order <- @orders}
            navigate={~p"/orders/#{order.id}"}
            class="flex items-center gap-4 py-4 px-3 rounded-lg hover:bg-base-200 transition-colors"
          >
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-base-content">{order.artist_name}</p>
              <p class="text-sm text-base-content/60 truncate">{item_summary(order.items)}</p>
              <p class="text-xs text-base-content/40 mt-0.5">{format_date(order.inserted_at)}</p>
            </div>
            <div class="flex items-center gap-3 shrink-0">
              <%= if order.status == :completed && Reviews.order_in_review_window?(order) do %>
                <%= if order.id in @reviewed_ids do %>
                  <span class="badge badge-success badge-sm">Reviewed ✓</span>
                <% else %>
                  <span class="badge badge-warning badge-sm">Review pending</span>
                <% end %>
              <% end %>
              <span class="font-medium text-base-content text-sm">
                CA${Decimal.to_string(order.total)}
              </span>
              <span class={"badge #{order_badge(order.status)}"}>{order.status}</span>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
