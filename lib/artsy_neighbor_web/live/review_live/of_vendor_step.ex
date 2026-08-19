defmodule ArtsyNeighborWeb.ReviewLive.OfVendorStep do
  # Step 1 of the buyer review flow: the buyer rates the vendor (artist).
  # After submitting (or skipping), the buyer is sent to OfProductsStep to rate
  # individual products. The two steps are independent — neither is required for
  # the other to be submitted.
  #
  # Supports both create and edit: if a vendor review already exists for this
  # order, the form is pre-filled and submit calls update instead of create.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Reviews

  def mount(%{"id" => id}, _session, socket) do
    order     = Orders.get_order!(id)
    user      = socket.assigns.current_scope.user
    days_left = Reviews.days_remaining_in_window(order)
    existing  = Reviews.get_vendor_review_for_order(order.id)

    # Guard checks run in priority order: wrong user first (security), then
    # business-logic guards, then edit-vs-create decision.
    cond do
      order.buyer_id != user.id ->
        {:ok,
         socket
         |> put_flash(:error, "You are not authorised to review this order.")
         |> push_navigate(to: ~p"/messages")}

      order.status != :completed ->
        {:ok,
         socket
         |> put_flash(:error, "This order is not complete yet.")
         |> push_navigate(to: ~p"/messages/#{order.conversation_id}")}

      # days_remaining_in_window returns 0 once the 14-day window has passed.
      days_left == 0 ->
        {:ok,
         socket
         |> put_flash(:info, "The review window for this order has closed.")
         |> push_navigate(to: ~p"/messages/#{order.conversation_id}")}

      # Edit mode: review exists → pre-fill form and let the buyer update it.
      # The 30-day edit window is enforced by Reviews.update_vendor_review/2.
      not is_nil(existing) ->
        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:days_left, days_left)
         |> assign(:existing_review, existing)
         |> assign(:stars, existing.stars)
         |> assign(:body, existing.body || "")
         |> assign(:error, nil)
         |> assign(:page_title, "Edit your vendor review")}

      true ->
        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:days_left, days_left)
         |> assign(:existing_review, nil)
         |> assign(:stars, nil)
         |> assign(:body, "")
         |> assign(:error, nil)
         |> assign(:page_title, "Review your experience")}
    end
  end

  # Stars are tracked in socket assigns rather than as a form field so that
  # clicking a star button gives instant visual feedback without a full form
  # change event. The hidden <input name="stars"> in the form reflects the
  # current value at submit time, but we read from assigns to be safe.
  def handle_event("set_stars", %{"stars" => stars}, socket) do
    {:noreply, socket |> assign(:stars, String.to_integer(stars)) |> assign(:error, nil)}
  end

  # Keep :body in sync as the user types so the character counter stays live.
  def handle_event("form_changed", params, socket) do
    {:noreply, assign(socket, :body, Map.get(params, "body", ""))}
  end

  def handle_event("submit", _params, socket) do
    if is_nil(socket.assigns.stars) do
      {:noreply, assign(socket, :error, "Please choose a star rating before continuing.")}
    else
      order = socket.assigns.order
      user  = socket.assigns.current_scope.user

      attrs = %{
        order_id:    order.id,
        reviewer_id: user.id,
        artist_id:   order.artist_id,
        stars:       socket.assigns.stars,
        body:        String.trim(socket.assigns.body)
      }

      result =
        case socket.assigns.existing_review do
          nil      -> Reviews.create_vendor_review(attrs)
          existing -> Reviews.update_vendor_review(existing, attrs)
        end

      case result do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Thank you for your review!")
           |> push_navigate(to: ~p"/orders/#{order.id}/review/products")}

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
            <p class="text-xs text-base-content/50 uppercase tracking-widest mb-2">Step 1 of 2</p>
            <h1 class="text-2xl font-bold text-base-content">
              {if @existing_review, do: "Edit your vendor review", else: "Rate your experience"}
            </h1>
            <p class="text-sm text-base-content/60 mt-1">
              How was your purchase from <span class="font-medium">{@order.artist_name}</span>?
              You have {@days_left} day{if @days_left != 1, do: "s"} left.
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
                Share your experience
                <span class="text-base-content/40 font-normal">(optional)</span>
              </label>
              <textarea
                name="body"
                rows="4"
                maxlength="500"
                class="textarea textarea-bordered w-full text-sm resize-none"
                placeholder="What did you love? Any suggestions?"
              >{@body}</textarea>
              <p class="text-right text-xs text-base-content/40 mt-1">{String.length(@body)}/500</p>
            </div>

            <p :if={@error} class="text-sm text-error">{@error}</p>

            <button type="submit" class="btn btn-primary w-full">
              {if @existing_review, do: "Save changes", else: "Submit and continue to product reviews"}
            </button>
          </form>

          <.link
            navigate={~p"/orders/#{@order.id}/review/products"}
            class="btn btn-ghost btn-sm w-full text-base-content/50"
          >
            {if @existing_review, do: "Skip to product reviews", else: "Skip vendor review"}
          </.link>

        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
