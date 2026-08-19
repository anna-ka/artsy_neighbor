defmodule ArtsyNeighborWeb.VendorLive.OrdersShow do
  # Vendor's view of a single sale — items, totals, pickup details, and the
  # buyer review with Edit/Delete actions within the 30-day edit window.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Reviews
  import ArtsyNeighborWeb.OrderFormatters

  def mount(%{"id" => id}, _session, socket) do
    order  = Orders.get_order!(id)
    artist = socket.assigns.current_scope.artist

    # Guard: the current vendor must own this order.
    if is_nil(artist) || artist.id != order.artist_id do
      {:ok,
       socket
       |> put_flash(:error, "You are not authorised to view this order.")
       |> push_navigate(to: ~p"/vendor/orders")}
    else
      {:ok, load_review(socket, order)}
    end
  end

  defp load_review(socket, order) do
    {buyer_review, artist_review, product_reviews_by_product, days_left} =
      if order.status == :completed do
        br  = Reviews.get_buyer_review_for_order(order.id)
        ar  = Reviews.get_vendor_review_for_order(order.id)
        prs = order.id
              |> Reviews.get_product_reviews_for_order()
              |> Map.new(&{&1.product_id, &1})
        dl  = Reviews.days_remaining_in_window(order)
        {br, ar, prs, dl}
      else
        {nil, nil, %{}, 0}
      end

    socket
    |> assign(:order, order)
    |> assign(:buyer_review, buyer_review)
    |> assign(:artist_review, artist_review)
    |> assign(:product_reviews_by_product, product_reviews_by_product)
    |> assign(:days_left, days_left)
    |> assign(:page_title, "Sale to #{order.buyer_email}")
  end

  def handle_event("delete_buyer_review", _params, socket) do
    case Reviews.delete_buyer_review(socket.assigns.buyer_review) do
      {:ok, _} ->
        {:noreply, assign(socket, :buyer_review, nil)}

      {:error, :edit_window_expired} ->
        {:noreply, put_flash(socket, :error, "The 30-day edit window for this review has closed.")}

      {:error, _} ->
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

        <.link navigate={~p"/vendor/orders"} class="text-sm text-base-content/50 hover:text-base-content inline-flex items-center gap-1 mb-6">
          ← Back to sales
        </.link>

        <div class="bg-base-200 rounded-2xl p-6 mt-4 flex flex-col gap-6">

          <%!-- Header: buyer + status --%>
          <div class="flex items-start justify-between gap-4">
            <div>
              <h1 class="text-xl font-bold text-base-content">Sale to {@order.buyer_email}</h1>
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

          <%!-- Pickup details — shown once scheduled --%>
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

          <%!-- Buyer review — only on completed orders --%>
          <div :if={@order.status == :completed} class="border-t border-base-content/10 pt-4 flex flex-col gap-3">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50">Your review of the buyer</h2>
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm text-base-content">Review of buyer</span>
              <%= cond do %>
                <% is_nil(@buyer_review) and @days_left > 0 -> %>
                  <.link navigate={~p"/vendor/orders/#{@order.id}/review/buyer"} class="btn btn-xs btn-primary shrink-0">
                    Leave a review
                  </.link>
                <% is_nil(@buyer_review) -> %>
                  <span class="text-xs text-base-content/40 shrink-0">Window closed</span>
                <% true -> %>
                  <div class="flex items-center gap-2 shrink-0">
                    <span class="text-xs text-success">Submitted ✓</span>
                    <%= if Reviews.within_edit_window?(@buyer_review) do %>
                      <.link navigate={~p"/vendor/orders/#{@order.id}/review/buyer"} class="btn btn-xs btn-ghost">Edit</.link>
                      <button
                        phx-click="delete_buyer_review"
                        data-confirm="Delete your buyer review? This cannot be undone."
                        class="btn btn-xs btn-ghost text-error"
                      >
                        Delete
                      </button>
                    <% end %>
                  </div>
              <% end %>
            </div>
          </div>

          <%!-- Buyer's reviews of you — only on completed orders --%>
          <div :if={@order.status == :completed} class="border-t border-base-content/10 pt-4 flex flex-col gap-4">
            <h2 class="text-xs font-semibold uppercase tracking-widest text-base-content/50">Buyer's reviews of you</h2>

            <%!-- Hidden until the vendor has submitted their own review (blind review pattern) --%>
            <%= if is_nil(@buyer_review) and @days_left > 0 do %>
              <p class="text-sm text-base-content/50 italic">
                Submit your review of the buyer first — you'll be able to see their reviews of you once you have.
              </p>
            <% else %>

              <%!-- Vendor (artist) review --%>
              <div class="flex flex-col gap-1">
                <p class="text-sm font-medium text-base-content">Review of you as an artist</p>
                <%= if @artist_review do %>
                  <div class="flex items-center gap-2">
                    <span class="text-warning tracking-tight">
                      {"★" |> String.duplicate(@artist_review.stars)}<span class="text-base-content/20">{"★" |> String.duplicate(5 - @artist_review.stars)}</span>
                    </span>
                    <span class="text-xs text-base-content/50">{@artist_review.stars}/5</span>
                  </div>
                  <p :if={@artist_review.body && @artist_review.body != ""} class="text-sm text-base-content/70 mt-1">
                    "{@artist_review.body}"
                  </p>
                <% else %>
                  <p class="text-sm text-base-content/40 italic">The buyer did not leave a review.</p>
                <% end %>
              </div>

              <%!-- Per-product reviews --%>
              <div :for={item <- @order.items} :if={not is_nil(item.product_id)}
                   class="flex gap-3 pl-4 border-l-2 border-base-300">
                <div class="w-10 h-10 rounded-md overflow-hidden bg-base-300 shrink-0 mt-0.5">
                  <%= if path = thumb_path(item) do %>
                    <img src={path} alt={item.product_title} class="w-full h-full object-cover" />
                  <% else %>
                    <div class="w-full h-full flex items-center justify-center text-base-content/20 text-xs">?</div>
                  <% end %>
                </div>
                <div class="flex flex-col gap-1 min-w-0">
                  <% pr = @product_reviews_by_product[item.product_id] %>
                  <p class="text-sm font-medium text-base-content truncate">{item.product_title}</p>
                  <%= if pr do %>
                    <div class="flex items-center gap-2">
                      <span class="text-warning tracking-tight">
                        {"★" |> String.duplicate(pr.stars)}<span class="text-base-content/20">{"★" |> String.duplicate(5 - pr.stars)}</span>
                      </span>
                      <span class="text-xs text-base-content/50">{pr.stars}/5</span>
                    </div>
                    <p :if={pr.body && pr.body != ""} class="text-sm text-base-content/70">
                      "{pr.body}"
                    </p>
                  <% else %>
                    <p class="text-sm text-base-content/40 italic">No review for this item.</p>
                  <% end %>
                </div>
              </div>

            <% end %>
          </div>

          <%!-- Link to the order conversation --%>
          <.link navigate={~p"/messages/#{@order.conversation_id}"} class="btn btn-ghost btn-sm w-full">
            View conversation →
          </.link>

        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
