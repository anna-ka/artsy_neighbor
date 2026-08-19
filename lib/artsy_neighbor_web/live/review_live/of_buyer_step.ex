defmodule ArtsyNeighborWeb.ReviewLive.OfBuyerStep do
  # The vendor's side of the review flow: rate the buyer who purchased from you.
  # Route: /vendor/orders/:id/review/buyer — only accessible to the order's artist.
  #
  # Supports both create and edit: if a buyer review already exists the form is
  # pre-filled with existing stars/body; submit calls update instead of create.
  # The 30-day edit window is enforced by Reviews.update_buyer_review/2.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Reviews

  def mount(%{"id" => id}, _session, socket) do
    order     = Orders.get_order!(id)
    artist    = socket.assigns.current_scope.artist
    days_left = Reviews.days_remaining_in_window(order)
    existing  = Reviews.get_buyer_review_for_order(order.id)

    cond do
      # We check artist identity rather than user identity because the order is
      # linked to an Artist record, not directly to a User. A nil artist means
      # the current user has no artist profile at all (shouldn't happen inside
      # the :require_vendor live_session, but safe to guard anyway).
      is_nil(artist) || artist.id != order.artist_id ->
        {:ok,
         socket
         |> put_flash(:error, "You are not authorised to review this order.")
         |> push_navigate(to: ~p"/vendor")}

      order.status != :completed ->
        {:ok,
         socket
         |> put_flash(:error, "This order is not complete yet.")
         |> push_navigate(to: ~p"/vendor")}

      days_left == 0 ->
        {:ok,
         socket
         |> put_flash(:info, "The review window for this order has closed.")
         |> push_navigate(to: ~p"/vendor")}

      # Edit mode: review exists → pre-fill the form instead of redirecting.
      not is_nil(existing) ->
        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:days_left, days_left)
         |> assign(:existing_review, existing)
         |> assign(:stars, existing.stars)
         |> assign(:body, existing.body || "")
         |> assign(:error, nil)
         |> assign(:page_title, "Edit your buyer review")}

      true ->
        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:days_left, days_left)
         |> assign(:existing_review, nil)
         |> assign(:stars, nil)
         |> assign(:body, "")
         |> assign(:error, nil)
         |> assign(:page_title, "Review your buyer")}
    end
  end

  # Stars are tracked in assigns rather than form params so clicking a star
  # gives instant visual feedback without waiting for a form change cycle.
  def handle_event("set_stars", %{"stars" => stars}, socket) do
    {:noreply, socket |> assign(:stars, String.to_integer(stars)) |> assign(:error, nil)}
  end

  def handle_event("form_changed", params, socket) do
    {:noreply, assign(socket, :body, Map.get(params, "body", ""))}
  end

  def handle_event("submit", _params, socket) do
    if is_nil(socket.assigns.stars) do
      {:noreply, assign(socket, :error, "Please choose a star rating before submitting.")}
    else
      order = socket.assigns.order
      user  = socket.assigns.current_scope.user

      attrs = %{
        order_id:    order.id,
        reviewer_id: user.id,
        buyer_id:    order.buyer_id,
        stars:       socket.assigns.stars,
        body:        String.trim(socket.assigns.body)
      }

      result =
        case socket.assigns.existing_review do
          nil      -> Reviews.create_buyer_review(attrs)
          existing -> Reviews.update_buyer_review(existing, attrs)
        end

      case result do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Thank you — your review has been submitted.")
           |> push_navigate(to: ~p"/vendor/orders/#{order.id}")}

        {:error, :edit_window_expired} ->
          {:noreply, assign(socket, :error, "The 30-day edit window for this review has closed.")}

        {:error, changeset} ->
          msg =
            Ecto.Changeset.traverse_errors(changeset, fn {m, _opts} -> m end)
            |> Enum.map_join(", ", fn {f, msgs} -> "#{f} #{Enum.join(msgs, ", ")}" end)

          {:noreply, assign(socket, :error, msg)}
      end
    end
  end

  defp star_label(n) do
    %{1 => "Poor", 2 => "Fair", 3 => "Good", 4 => "Very good", 5 => "Excellent"}[n]
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
      <div class="max-w-lg mx-auto px-4 py-12">
        <div class="bg-base-200 rounded-xl p-6 flex flex-col gap-6">

          <div>
            <h1 class="text-2xl font-bold text-base-content">
              {if @existing_review, do: "Edit your buyer review", else: "Review your buyer"}
            </h1>
            <p class="text-sm text-base-content/60 mt-1">
              How was the transaction with this buyer?
              You have {@days_left} day{if @days_left != 1, do: "s"} left to review.
            </p>
          </div>

          <div class="bg-base-300/50 rounded-lg p-4 text-sm text-base-content/70 flex flex-col gap-1">
            <p class="font-medium text-base-content mb-1">Order summary</p>
            <p :for={item <- @order.items}>{item.product_title} × {item.quantity}</p>
            <p class="mt-2 font-medium text-base-content">
              Total: CA${Decimal.to_string(@order.total)}
            </p>
          </div>

          <div>
            <p class="text-sm font-medium text-base-content mb-3">Your rating</p>
            <div class="flex gap-1" role="group" aria-label="Star rating">
              <button
                :for={i <- 1..5}
                type="button"
                phx-click="set_stars"
                phx-value-stars={i}
                class={[
                  "text-4xl transition-colors select-none leading-none",
                  if((@stars || 0) >= i,
                    do:   "text-warning",
                    else: "text-base-content/20 hover:text-warning/50")
                ]}
                aria-label={"#{i} star#{if i != 1, do: "s"}"}
              >★</button>
            </div>
            <p :if={@stars} class="text-xs text-base-content/50 mt-1">{star_label(@stars)}</p>
          </div>

          <form phx-submit="submit" phx-change="form_changed" class="flex flex-col gap-4">
            <div>
              <label class="text-sm font-medium text-base-content block mb-2">
                Comments
                <span class="text-base-content/40 font-normal">(optional)</span>
              </label>
              <textarea
                name="body"
                rows="4"
                maxlength="500"
                class="textarea textarea-bordered w-full text-sm resize-none"
                placeholder="Was the buyer responsive, respectful, and punctual?"
              >{@body}</textarea>
              <p class="text-right text-xs text-base-content/40 mt-1">{String.length(@body)}/500</p>
            </div>

            <p :if={@error} class="text-sm text-error">{@error}</p>

            <button type="submit" class="btn btn-primary w-full">
              {if @existing_review, do: "Save changes", else: "Submit review"}
            </button>
          </form>

        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
