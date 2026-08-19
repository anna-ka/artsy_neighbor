defmodule ArtsyNeighborWeb.ReviewLive.OfProductsStep do
  # Step 2 of the buyer review flow: the buyer rates each product in the order
  # individually. This step is entirely optional — the buyer can skip every item
  # or submit reviews for only some of them.
  #
  # All per-product form state lives in @reviews, a map keyed by product_id:
  #   %{product_id => %{stars, body, submitted, editing, existing_review, error}}
  #
  # Each product card is independent: the buyer can submit or edit one without
  # touching the others, and submit calls update when an existing review is present.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Orders
  alias ArtsyNeighbor.Reviews

  def mount(%{"id" => id}, _session, socket) do
    order     = Orders.get_order!(id)
    user      = socket.assigns.current_scope.user
    days_left = Reviews.days_remaining_in_window(order)

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

      days_left == 0 ->
        {:ok,
         socket
         |> put_flash(:info, "The review window for this order has closed.")
         |> push_navigate(to: ~p"/messages/#{order.conversation_id}")}

      true ->
        # Load full ProductReview structs (not just IDs) so we can pre-fill
        # the form and call update/2 on edit.
        existing_by_product =
          order.id
          |> Reviews.get_product_reviews_for_order()
          |> Map.new(fn r -> {r.product_id, r} end)

        # De-duplicate by product_id: if the buyer ordered qty 2 of the same
        # product, we still only show one review card for it.
        products =
          order.items
          |> Enum.filter(& &1.product_id)
          |> Enum.uniq_by(& &1.product_id)
          |> Enum.map(fn item ->
            %{
              id:    item.product_id,
              title: item.product_title,
              thumb: item.product && List.first(item.product.product_images)
            }
          end)

        reviews =
          Map.new(products, fn p ->
            existing = Map.get(existing_by_product, p.id)
            {p.id,
             %{
               stars:           existing && existing.stars,
               body:            (existing && existing.body) || "",
               submitted:       not is_nil(existing),
               editing:         false,
               existing_review: existing,
               error:           nil
             }}
          end)

        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:days_left, days_left)
         |> assign(:products, products)
         |> assign(:reviews, reviews)
         |> assign(:page_title, "Review your items")}
    end
  end

  # Star buttons use phx-value-product-id to identify which card they belong to,
  # so a single event handler can serve all cards on the page.
  def handle_event("set_stars", %{"product-id" => pid_str, "stars" => stars_str}, socket) do
    product_id = String.to_integer(pid_str)
    stars      = String.to_integer(stars_str)

    reviews =
      Map.update!(socket.assigns.reviews, product_id, fn r ->
        %{r | stars: stars, error: nil}
      end)

    {:noreply, assign(socket, :reviews, reviews)}
  end

  # Reveal the edit form for an already-submitted product card.
  def handle_event("edit_product", %{"product-id" => pid_str}, socket) do
    product_id = String.to_integer(pid_str)
    reviews    = Map.update!(socket.assigns.reviews, product_id, &%{&1 | editing: true})
    {:noreply, assign(socket, :reviews, reviews)}
  end

  # Each product form carries a hidden product_id field so this single handler
  # can route the body update to the right entry in @reviews.
  def handle_event("form_changed", %{"product_id" => pid_str} = params, socket) do
    product_id = String.to_integer(pid_str)
    body       = Map.get(params, "body", "")
    reviews    = Map.update!(socket.assigns.reviews, product_id, &%{&1 | body: body})
    {:noreply, assign(socket, :reviews, reviews)}
  end

  def handle_event("submit_product", %{"product_id" => pid_str} = params, socket) do
    product_id = String.to_integer(pid_str)
    order      = socket.assigns.order
    user       = socket.assigns.current_scope.user
    state      = socket.assigns.reviews[product_id]

    # The hidden <input name="stars"> in the form mirrors the assign, but the
    # assign is the source of truth. We fall back to the form param only in case
    # the assign was somehow lost (e.g. a reconnect between star-click and submit).
    stars =
      case Map.get(params, "stars", "") do
        "" -> nil
        s  -> String.to_integer(s)
      end

    stars = state.stars || stars

    if is_nil(stars) do
      reviews = Map.update!(socket.assigns.reviews, product_id, &%{&1 | error: "Please choose a star rating."})
      {:noreply, assign(socket, :reviews, reviews)}
    else
      attrs = %{
        order_id:    order.id,
        reviewer_id: user.id,
        product_id:  product_id,
        stars:       stars,
        body:        String.trim(Map.get(params, "body", state.body))
      }

      result =
        case state.existing_review do
          nil      -> Reviews.create_product_review(attrs)
          existing -> Reviews.update_product_review(existing, attrs)
        end

      case result do
        # Mark this product as done and clear the edit flag.
        {:ok, saved_review} ->
          reviews =
            Map.update!(socket.assigns.reviews, product_id, fn r ->
              %{r | submitted: true, editing: false, existing_review: saved_review, error: nil}
            end)
          {:noreply, assign(socket, :reviews, reviews)}

        {:error, :edit_window_expired} ->
          reviews = Map.update!(socket.assigns.reviews, product_id, &%{&1 | error: "The 30-day edit window has closed."})
          {:noreply, assign(socket, :reviews, reviews)}

        {:error, changeset} ->
          msg =
            Ecto.Changeset.traverse_errors(changeset, fn {m, _opts} -> m end)
            |> Enum.map_join(", ", fn {f, msgs} -> "#{f} #{Enum.join(msgs, ", ")}" end)

          reviews = Map.update!(socket.assigns.reviews, product_id, &%{&1 | error: msg})
          {:noreply, assign(socket, :reviews, reviews)}
      end
    end
  end

  def handle_event("done", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/orders/#{socket.assigns.order.id}")}
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
      <div class="max-w-lg mx-auto px-4 py-12 flex flex-col gap-6">

        <div>
          <p class="text-xs text-base-content/50 uppercase tracking-widest mb-2">Step 2 of 2</p>
          <h1 class="text-2xl font-bold text-base-content">Review your items</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Rate each piece individually. You have {@days_left} day{if @days_left != 1, do: "s"} left.
            All fields are optional — skip any item you prefer not to review.
          </p>
        </div>

        <div :for={product <- @products} class="bg-base-200 rounded-xl p-5 flex flex-col gap-4">
          <% state = @reviews[product.id] %>

          <div class="flex items-center gap-3">
            <div class="w-12 h-12 rounded-lg overflow-hidden bg-base-300 shrink-0">
              <%= if product.thumb do %>
                <img src={product.thumb.path} alt={product.title} class="w-full h-full object-cover" />
              <% else %>
                <div class="w-full h-full flex items-center justify-center text-base-content/20 text-xs">?</div>
              <% end %>
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-base-content truncate">{product.title}</p>
              <p :if={state.submitted and not state.editing} class="text-xs text-success mt-0.5">Review submitted ✓</p>
            </div>
            <%!-- Edit button — only while the 30-day edit window is open --%>
            <button
              :if={state.submitted and not state.editing and state.existing_review && Reviews.within_edit_window?(state.existing_review)}
              phx-click="edit_product"
              phx-value-product-id={product.id}
              class="btn btn-xs btn-ghost shrink-0"
            >
              Edit
            </button>
          </div>

          <%= if state.submitted and not state.editing do %>
            <p class="text-sm text-base-content/50 italic">
              {if state.stars, do: "#{state.stars} ★ — ", else: ""}Thank you for your review!
            </p>
          <% else %>
            <div>
              <p class="text-sm font-medium text-base-content mb-2">Rating</p>
              <div class="flex gap-1">
                <button
                  :for={i <- 1..5}
                  type="button"
                  phx-click="set_stars"
                  phx-value-product-id={product.id}
                  phx-value-stars={i}
                  class={[
                    "text-3xl transition-colors select-none leading-none",
                    if((state.stars || 0) >= i,
                      do:   "text-warning",
                      else: "text-base-content/20 hover:text-warning/50")
                  ]}
                >★</button>
              </div>
              <p :if={state.stars} class="text-xs text-base-content/50 mt-1">{star_label(state.stars)}</p>
            </div>

            <form phx-submit="submit_product" phx-change="form_changed" class="flex flex-col gap-3">
              <input type="hidden" name="product_id" value={product.id} />
              <input type="hidden" name="stars" value={state.stars || ""} />
              <div>
                <textarea
                  name="body"
                  rows="3"
                  maxlength="500"
                  class="textarea textarea-bordered w-full text-sm resize-none"
                  placeholder="Share your thoughts on this piece (optional)"
                >{state.body}</textarea>
                <p class="text-right text-xs text-base-content/40 mt-1">{String.length(state.body)}/500</p>
              </div>
              <p :if={state.error} class="text-sm text-error">{state.error}</p>
              <button type="submit" class="btn btn-primary btn-sm w-full">
                {if state.existing_review, do: "Save changes", else: "Submit review for this item"}
              </button>
            </form>
          <% end %>
        </div>

        <button phx-click="done" class="btn btn-ghost w-full">
          Done — back to order
        </button>

      </div>
    </Layouts.artsy_main>
    """
  end
end
