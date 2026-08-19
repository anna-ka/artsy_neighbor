defmodule ArtsyNeighborWeb.OrderLive.Detail do
  # Buyer's view of a single order — full item list, totals, pickup details,
  # and review status with Edit/Delete actions within the 30-day edit window.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Reviews
  import ArtsyNeighborWeb.OrderFormatters

  def mount(%{"id" => id}, _session, socket) do
    order = Orders.get_order!(id)
    user  = socket.assigns.current_scope.user

    if order.buyer_id != user.id do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorised to view this order.")
       |> push_navigate(to: ~p"/orders")}
    else
      {:ok, load_reviews(socket, order)}
    end
  end

  # Loads or reloads all review state into assigns.
  # Called on mount and after any delete so the page is always fresh.
  defp load_reviews(socket, order) do
    {vendor_review, product_reviews_by_product, received_review, days_left} =
      if order.status == :completed do
        vr  = Reviews.get_vendor_review_for_order(order.id)
        prs = order.id
              |> Reviews.get_product_reviews_for_order()
              |> Map.new(&{&1.product_id, &1})
        rr  = Reviews.get_buyer_review_for_order(order.id)
        dl  = Reviews.days_remaining_in_window(order)
        {vr, prs, rr, dl}
      else
        {nil, %{}, nil, 0}
      end

    socket
    |> assign(:order, order)
    |> assign(:vendor_review, vendor_review)
    |> assign(:product_reviews_by_product, product_reviews_by_product)
    |> assign(:received_review, received_review)
    |> assign(:days_left, days_left)
    |> assign(:page_title, "Order from #{order.artist_name}")
  end

  def handle_event("delete_vendor_review", _params, socket) do
    case Reviews.delete_vendor_review(socket.assigns.vendor_review) do
      {:ok, _} ->
        {:noreply, assign(socket, :vendor_review, nil)}

      {:error, :edit_window_expired} ->
        {:noreply, put_flash(socket, :error, "The 30-day edit window for this review has closed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete the review. Please try again.")}
    end
  end

  def handle_event("delete_product_review", %{"product-id" => pid_str}, socket) do
    product_id = String.to_integer(pid_str)
    review     = socket.assigns.product_reviews_by_product[product_id]

    case review && Reviews.delete_product_review(review) do
      {:ok, _} ->
        updated = Map.delete(socket.assigns.product_reviews_by_product, product_id)
        {:noreply, assign(socket, :product_reviews_by_product, updated)}

      {:error, :edit_window_expired} ->
        {:noreply, put_flash(socket, :error, "The 30-day edit window for this review has closed.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete the review. Please try again.")}
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
      <div class="max-w-2xl mx-auto px-4 py-10">

        <.link navigate={~p"/orders"} class="text-sm text-base-content/50 hover:text-base-content inline-flex items-center gap-1 mb-6">
          ← Back to orders
        </.link>

        <div class="bg-base-200 rounded-2xl p-6 mt-4 flex flex-col gap-6">

          <%!-- Header: artist + status --%>
          <div class="flex items-start justify-between gap-4">
            <div>
              <h1 class="text-xl font-bold text-base-content">Order from {@order.artist_name}</h1>
              <p class="text-xs text-base-content/50 mt-1">Placed {format_dt(@order.inserted_at)}</p>
            </div>
            <span class={"badge badge-lg #{order_badge(@order.status)} shrink-0"}>
              {@order.status}
            </span>
          </div>

          <%!-- Item list --%>
          <div>
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50 mb-3">Items</h2>
            <ul class="flex flex-col gap-3">
              <li :for={item <- @order.items} class="flex items-center gap-3">
                <div class="w-12 h-12 rounded-lg overflow-hidden bg-base-300 shrink-0">
                  <%= if path = thumb_path(item) do %>
                    <img src={path} alt={item.product_title} class="w-full h-full object-cover" />
                  <% else %>
                    <div class="w-full h-full flex items-center justify-center text-base-content/20 text-lg">
                      🖼
                    </div>
                  <% end %>
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-base-content truncate">{item.product_title}</p>
                  <p class="text-xs text-base-content/50">
                    CA${Decimal.to_string(item.unit_price)} each
                  </p>
                </div>
                <span class="text-sm text-base-content/60 shrink-0">×{item.quantity}</span>
              </li>
            </ul>
          </div>

          <%!-- Totals --%>
          <div class="border-t border-base-content/10 pt-4 flex flex-col gap-1 text-sm">
            <div class="flex justify-between text-base-content/60">
              <span>Subtotal</span>
              <span>CA${Decimal.to_string(@order.subtotal)}</span>
            </div>
            <div class="flex justify-between text-base-content/60">
              <span>Platform fee</span>
              <span>CA${Decimal.to_string(@order.platform_fee)}</span>
            </div>
            <div class="flex justify-between font-bold text-base-content mt-2">
              <span>Total</span>
              <span>CA${Decimal.to_string(@order.total)}</span>
            </div>
          </div>

          <%!-- Pickup details — shown once vendor has scheduled --%>
          <div :if={@order.pickup_scheduled_at} class="bg-base-300/50 rounded-xl p-4 text-sm flex flex-col gap-1">
            <p class="font-semibold text-base-content/80 mb-1">Pickup details</p>
            <p class="text-base-content/70"><span class="font-medium">Date:</span> {@order.pickup_date}</p>
            <p class="text-base-content/70"><span class="font-medium">Time:</span> {@order.pickup_time}</p>
            <p class="text-base-content/70"><span class="font-medium">Address:</span> {@order.pickup_address}</p>
            <p :if={@order.pickup_instructions} class="text-base-content/70">
              <span class="font-medium">Notes:</span> {@order.pickup_instructions}
            </p>
          </div>

          <p :if={@order.completed_at} class="text-xs text-base-content/40">
            Completed {format_dt(@order.completed_at)}
          </p>

          <%!-- Section 1: Your reviews of the vendor — only on completed orders --%>
          <div :if={@order.status == :completed} class="border-t border-base-content/10 pt-4 flex flex-col gap-3">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50">Your reviews</h2>

            <%!-- Vendor review row --%>
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm text-base-content">Review of the vendor</span>
              <%= cond do %>
                <% is_nil(@vendor_review) and @days_left > 0 -> %>
                  <.link navigate={~p"/orders/#{@order.id}/review/vendor"} class="btn btn-xs btn-primary shrink-0">
                    Leave a review
                  </.link>
                <% is_nil(@vendor_review) -> %>
                  <span class="text-xs text-base-content/40 shrink-0">Window closed</span>
                <% true -> %>
                  <div class="flex flex-col items-end gap-1 shrink-0">
                    <span class="text-xs text-success">Submitted ✓</span>
                    <%= if Reviews.within_edit_window?(@vendor_review) do %>
                      <div class="flex items-center gap-2">
                        <.link navigate={~p"/orders/#{@order.id}/review/vendor"} class="btn btn-xs btn-ghost">Edit</.link>
                        <button
                          phx-click="delete_vendor_review"
                          data-confirm="Delete your vendor review? This cannot be undone."
                          class="btn btn-xs btn-ghost text-error"
                        >
                          Delete
                        </button>
                      </div>
                    <% else %>
                      <span class="text-xs text-base-content/40">Reviews cannot be edited or deleted after {Reviews.edit_window_days()} days</span>
                    <% end %>
                  </div>
              <% end %>
            </div>

            <%!-- Per-product review rows --%>
            <div :for={item <- @order.items} :if={not is_nil(item.product_id)}
                 class="flex items-center justify-between gap-3">
              <span class="text-sm text-base-content/70 truncate flex-1">{item.product_title}</span>
              <% existing = @product_reviews_by_product[item.product_id] %>
              <%= cond do %>
                <% is_nil(existing) and @days_left > 0 -> %>
                  <.link navigate={~p"/orders/#{@order.id}/review/products"} class="btn btn-xs btn-ghost shrink-0">
                    Review item
                  </.link>
                <% is_nil(existing) -> %>
                  <span class="text-xs text-base-content/40 shrink-0">Window closed</span>
                <% true -> %>
                  <div class="flex flex-col items-end gap-1 shrink-0">
                    <span class="text-xs text-success">Reviewed ✓</span>
                    <%= if Reviews.within_edit_window?(existing) do %>
                      <div class="flex items-center gap-2">
                        <.link navigate={~p"/orders/#{@order.id}/review/products"} class="btn btn-xs btn-ghost">Edit</.link>
                        <button
                          phx-click="delete_product_review"
                          phx-value-product-id={item.product_id}
                          data-confirm="Delete your review for #{item.product_title}?"
                          class="btn btn-xs btn-ghost text-error"
                        >
                          Delete
                        </button>
                      </div>
                    <% else %>
                      <span class="text-xs text-base-content/40">Reviews cannot be edited or deleted after {Reviews.edit_window_days()} days</span>
                    <% end %>
                  </div>
              <% end %>
            </div>
          </div>

          <%!-- Section 2: Vendor's review of you — only on completed orders --%>
          <div :if={@order.status == :completed} class="border-t border-base-content/10 pt-4 flex flex-col gap-4">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50">Vendor's review of you</h2>

            <%!-- Hidden until the buyer has submitted their own vendor review (blind review pattern) --%>
            <%= if is_nil(@vendor_review) and @days_left > 0 do %>
              <p class="text-sm text-base-content/50 italic">
                Submit your review of the vendor first — you'll be able to see their review of you once you have.
              </p>
            <% else %>
              <%= if @received_review do %>
                <div class="flex flex-col gap-1">
                  <div class="flex items-center gap-2">
                    <span class="text-warning tracking-tight">
                      {"★" |> String.duplicate(@received_review.stars)}<span class="text-base-content/20">{"★" |> String.duplicate(5 - @received_review.stars)}</span>
                    </span>
                    <span class="text-xs text-base-content/50">{@received_review.stars}/5</span>
                  </div>
                  <p :if={@received_review.body && @received_review.body != ""} class="text-sm text-base-content/70 mt-1">
                    "{@received_review.body}"
                  </p>
                </div>
              <% else %>
                <p class="text-sm text-base-content/40 italic">The vendor has not left a review yet.</p>
              <% end %>
            <% end %>
          </div>

          <%!-- Link to the conversation with the vendor --%>
          <.link navigate={~p"/messages/#{@order.conversation_id}"} class="btn btn-ghost btn-sm w-full">
            View conversation →
          </.link>

        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
