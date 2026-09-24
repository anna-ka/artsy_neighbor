defmodule ArtsyNeighbor.Orders do
  require Logger
  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Orders.OrderItem
  alias ArtsyNeighbor.Conversations
  alias ArtsyNeighbor.Conversations.Conversation
  alias ArtsyNeighbor.Conversations.ConversationEvent
  alias ArtsyNeighbor.Accounts.User
  alias ArtsyNeighbor.Reviews.ReviewNotifier

  @doc """
  Creates an order within an existing conversation.
  items is a list of %{product: product, quantity: integer}.
  Atomically inserts the order, order items, a system ConversationEvent,
  and stamps conversation.last_event_at.
  Returns {:error, :invalid_quantity} if any item's quantity isn't a
  positive integer.
  """
  def create_order(conversation, buyer, artist, items, delivery_method \\ :pickup) do
    if Enum.any?(items, fn %{quantity: q} -> not (is_integer(q) and q > 0) end) do
      {:error, :invalid_quantity}
    else
      do_create_order(conversation, buyer, artist, items, delivery_method)
    end
  end

  # The actual order-creation work, split out from create_order/5 so the
  # quantity guard above can short-circuit before any of this runs. Builds
  # the Order, its OrderItem rows, and the "requested" ConversationEvent in
  # one Multi so a failure partway through (e.g. a duplicate item) leaves no
  # partial order behind.
  defp do_create_order(conversation, buyer, artist, items, delivery_method) do
    vendor_user = Repo.get!(User, artist.user_id)
    {subtotal, platform_fee, total} = calculate_totals(items)

    Multi.new()
    |> Multi.insert(:order, Order.changeset(%Order{}, %{
      conversation_id: conversation.id,
      buyer_id: buyer.id,
      artist_id: artist.id,
      status: :requested,
      delivery_method: delivery_method,
      subtotal: subtotal,
      platform_fee: platform_fee,
      total: total,
      buyer_email: buyer.email,
      vendor_email: vendor_user.email,
      artist_name: artist.nickname
    }))
    |> Multi.run(:order_items, fn _repo, %{order: order} ->
      results =
        Enum.map(items, fn %{product: product, quantity: quantity} ->
          %OrderItem{}
          |> OrderItem.changeset(%{
            order_id: order.id,
            product_id: product.id,
            quantity: quantity,
            unit_price: product.price,
            product_title: product.title,
            return_policy_snapshot: "All sales final unless item is significantly not as described."
          })
          |> Repo.insert()
        end)

      case Enum.find(results, fn {k, _} -> k == :error end) do
        nil -> {:ok, Enum.map(results, fn {:ok, item} -> item end)}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Multi.run(:event, fn _repo, %{order: order} ->
      item_summary =
        case items do
          [%{product: p, quantity: 1}] -> p.title
          [%{product: p, quantity: q}] -> "#{p.title} ×#{q}"
          _ -> "#{length(items)} items"
        end

      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: conversation.id,
        actor_type: :buyer,
        actor_id: buyer.id,
        order_id: order.id,
        to_status: "requested",
        body: "Buyer requested to purchase #{item_summary} — CA$#{total}"
      })
      |> Repo.insert()
    end)
    |> Multi.run(:stamp_conversation, fn _repo, _changes ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.update_all(
        from(c in Conversation, where: c.id == ^conversation.id),
        set: [last_event_at: now]
      )
      {:ok, :stamped}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, event: event}} ->
        Conversations.broadcast_order_event(order.conversation_id, event)
        {:ok, order}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Vendor confirms the order. Generates a pickup token and posts a system event.
  Only works when the order is in :requested state.
  """
  def confirm_order(%Order{status: :requested} = order) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:order, Order.changeset(order, %{
      status: :confirmed,
      complete_token: token,
      complete_token_at: now
    }))
    |> Multi.run(:event, fn _repo, %{order: updated_order} ->
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: updated_order.conversation_id,
        actor_type: :vendor,
        order_id: updated_order.id,
        from_status: "requested",
        to_status: "confirmed",
        body: "Order confirmed — CA$#{updated_order.total}. I'll send you the pickup link when you're ready."
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, event: event}} ->
        Conversations.broadcast_order_event(order.conversation_id, event)
        {:ok, order}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def confirm_order(%Order{}), do: {:error, :wrong_state}



  @doc """
  Buyer completes the pickup by providing the token from the vendor.
  Uses constant-time comparison to prevent timing attacks.
  """
  def complete_pickup(%Order{complete_token: nil}, _token), do: {:error, :invalid_token}

  def complete_pickup(%Order{status: :confirmed, delivery_method: :pickup} = order, token) do
    if Plug.Crypto.secure_compare(order.complete_token, token) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      base_url = ArtsyNeighborWeb.Endpoint.url()
      buyer_review_url  = "#{base_url}/orders/#{order.id}/review/vendor"
      vendor_review_url = "#{base_url}/vendor/orders/#{order.id}/review/buyer"

      # Capture user IDs now — the Multi returns the bare updated order struct
      # without preloads, so we cannot reliably read order.artist.user_id after.
      buyer_user_id  = order.buyer_id
      vendor_user_id = order.artist.user_id

      result =
        Multi.new()
        |> Multi.update(:order, Order.changeset(order, %{status: :completed, completed_at: now}))
        |> Multi.run(:event, fn _repo, %{order: updated_order} ->
          %ConversationEvent{event_type: :status_change}
          |> ConversationEvent.status_change_changeset(%{
            conversation_id: updated_order.conversation_id,
            actor_type: :buyer,
            order_id: updated_order.id,
            from_status: "confirmed",
            to_status: "completed",
            body: "Pickup completed — thank you!"
          })
          |> Repo.insert()
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{order: completed_order}} ->
          # Review messages and emails are sent outside the transaction.
          # A failure here should not roll back a successfully completed order.
          send_review_request_messages(buyer_user_id, vendor_user_id, buyer_review_url, vendor_review_url)

          ReviewNotifier.deliver_review_request_buyer(
            completed_order.buyer_email,
            completed_order.artist_name,
            buyer_review_url
          )
          ReviewNotifier.deliver_review_request_vendor(
            completed_order.vendor_email,
            completed_order.buyer_email,
            vendor_review_url
          )
          {:ok, completed_order}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    else
      {:error, :invalid_token}
    end
  end

  # Catch-all also covers delivery_method: :delivery orders — there is no
  # completion flow for delivery yet (only :pickup is implemented), so a
  # :confirmed delivery order lands here and gets :wrong_state rather than
  # silently doing nothing. Build a real delivery-completion clause above
  # this one when that feature is implemented.
  def complete_pickup(%Order{}, _token), do: {:error, :wrong_state}

  # Posts a private review-request message to each party's system inbox.
  # System conversations are created on demand if the user doesn't have one yet.
  # Called after the order transaction commits so a messaging failure never
  # rolls back a completed order.
  defp send_review_request_messages(buyer_user_id, vendor_user_id, buyer_url, vendor_url) do
    platform = Application.get_env(:artsy_neighbor, :platform_name, "Artsy Neighbour")

    with {:ok, buyer_conv}  <- Conversations.get_or_create_system_conversation(buyer_user_id),
         {:ok, vendor_conv} <- Conversations.get_or_create_system_conversation(vendor_user_id) do
      Conversations.post_system_message(buyer_conv, """
      Your order is complete! You have 14 days to share your experience.

      Leave a review of your vendor here:
      #{buyer_url}

      — #{platform}
      """)

      Conversations.post_system_message(vendor_conv, """
      Your order is complete! You have 14 days to review your buyer.

      Leave a review of your buyer here:
      #{vendor_url}

      — #{platform}
      """)
    else
      {:error, reason} ->
        Logger.error("[Orders] send_review_request_messages failed — buyer_user_id=#{buyer_user_id} vendor_user_id=#{vendor_user_id} reason=#{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Adds a product to an open order, incrementing its quantity if already present
  or appending a new line item at the current product price.
  actor_type must be :buyer or :vendor (either party can add items in person).
  """
  def add_item_to_order(%Order{status: status} = order, product, actor_type)
      when status in [:requested, :confirmed] and actor_type in [:buyer, :vendor] do
    # force: true — do_amend deletes and reinserts every OrderItem row on any
    # amendment, so a caller holding an order struct from a *previous*
    # mutation would otherwise have its (already "loaded") :items silently
    # skipped by preload, and this function would compute specs from
    # stale/deleted item rows. Callers should still prefer re-fetching via
    # get_order!/1 between actions (as the LiveViews do); this guards the
    # cases where they don't.
    order = Repo.preload(order, :items, force: true)

    specs =
      case Enum.find(order.items, &(&1.product_id == product.id)) do
        nil ->
          to_specs(order.items) ++
            [%{product_id: product.id, product_title: product.title, quantity: 1, unit_price: product.price}]

        found ->
          Enum.map(order.items, fn item ->
            spec = to_spec(item)
            if item.id == found.id, do: %{spec | quantity: spec.quantity + 1}, else: spec
          end)
      end

    {_, _, total} = calculate_totals_from_specs(specs)
    actor_label = if actor_type == :buyer, do: "Buyer", else: "Vendor"
    do_amend(order, specs, actor_type, "#{actor_label} added #{product.title} to the order — new total CA$#{total}")
  end

  def add_item_to_order(%Order{}, _product, _actor_type), do: {:error, :wrong_state}

  @doc """
  Removes one unit of an order item (decrements quantity, or removes the line
  entirely if quantity is 1). Cancels the whole order if no items remain.
  actor_type must be :buyer or :vendor.
  """
  def remove_order_item(%Order{status: status} = order, order_item_id, actor_type)
      when status in [:requested, :confirmed] and actor_type in [:buyer, :vendor, :system] do
    order = Repo.preload(order, :items, force: true)

    case Enum.find(order.items, &(&1.id == order_item_id)) do
      nil ->
        {:error, :not_found}

      item ->
        actor_label = case actor_type do
          :buyer -> "Buyer"
          :vendor -> "Vendor"
          :system -> "System"
        end

        if item.quantity > 1 do
          new_qty = item.quantity - 1
          specs = Enum.map(order.items, fn i ->
            spec = to_spec(i)
            if i.id == item.id, do: %{spec | quantity: new_qty}, else: spec
          end)
          {_, _, total} = calculate_totals_from_specs(specs)
          do_amend(order, specs, actor_type, "#{actor_label} decremented quantity of #{item.product_title} to #{new_qty}. New total: CA$#{total}")
        else
          specs = order.items |> Enum.reject(&(&1.id == order_item_id)) |> to_specs()
          if Enum.empty?(specs) do
            cancel_order(order, actor_type)
          else
            {_, _, total} = calculate_totals_from_specs(specs)
            do_amend(order, specs, actor_type, "#{actor_label} removed #{item.product_title} from the order — new total CA$#{total}")
          end
        end
    end
  end

  def remove_order_item(%Order{}, _item_id, _actor), do: {:error, :wrong_state}

  @doc """
  Increments the quantity of an existing order item by 1, keeping the snapshot price.
  actor_type must be :buyer or :vendor.
  """
  def increment_order_item(%Order{status: status} = order, order_item_id, actor_type)
      when status in [:requested, :confirmed] and actor_type in [:buyer, :vendor] do
    order = Repo.preload(order, :items, force: true)

    case Enum.find(order.items, &(&1.id == order_item_id)) do
      nil ->
        {:error, :not_found}

      item ->
        new_qty = item.quantity + 1
        specs = Enum.map(order.items, fn i ->
          spec = to_spec(i)
          if i.id == item.id, do: %{spec | quantity: new_qty}, else: spec
        end)
        {_, _, total} = calculate_totals_from_specs(specs)
        actor_label = if actor_type == :buyer, do: "Buyer", else: "Vendor"
        do_amend(order, specs, actor_type, "#{actor_label} incremented quantity of #{item.product_title} to #{new_qty}. New total: CA$#{total}")
    end
  end

  def increment_order_item(%Order{}, _item_id, _actor_type), do: {:error, :wrong_state}

  @doc """
  Amends an order by replacing its items with a new list.
  items is a list of %{product: product, quantity: integer}.
  Prices are taken from the product struct (use add_item_to_order / remove_order_item
  to preserve snapshot prices for existing items).
  """
  def amend_order(%Order{status: status} = order, items)
      when status in [:requested, :confirmed] do
    specs = Enum.map(items, fn %{product: p, quantity: q} ->
      %{product_id: p.id, product_title: p.title, quantity: q, unit_price: p.price}
    end)
    {_, _, total} = calculate_totals_from_specs(specs)
    do_amend(order, specs, :buyer, "Order updated — new total CA$#{total}")
  end

  def amend_order(%Order{}, _items), do: {:error, :wrong_state}

  @doc """
  Cancels an order. Can be called by either party.
  actor_type must be :buyer or :vendor.
  Posts a system ConversationEvent recording who cancelled.
  Only allowed while the order is still open (:requested or :confirmed) —
  a :completed order cannot be retroactively cancelled.
  """
  def cancel_order(%Order{status: status} = order, actor_type)
      when status in [:requested, :confirmed] and actor_type in [:buyer, :vendor, :system] do
    order = Repo.preload(order, :items, force: true)

    item_summary =
      case order.items do
        [%{product_title: title, quantity: 1}] -> title
        [%{product_title: title, quantity: q}] -> "#{title} ×#{q}"
        items -> "#{length(items)} items"
      end

    actor_label =case actor_type do
      :buyer -> "Buyer"
      :vendor -> "Vendor"
      :system -> "System"
    end

    # actor_label = if actor_type == :buyer, do: "Buyer", else: "Vendor"

    Multi.new()
    |> Multi.update(:order, Order.changeset(order, %{status: :cancelled}))
    |> Multi.run(:event, fn _repo, %{order: updated_order} ->
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: updated_order.conversation_id,
        actor_type: actor_type,
        order_id: updated_order.id,
        from_status: to_string(order.status),
        to_status: "cancelled",
        body: "#{actor_label} cancelled the order for #{item_summary} — CA$#{order.total}"
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, event: event}} ->
        Conversations.broadcast_order_event(order.conversation_id, event)
        {:ok, order}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def cancel_order(%Order{}, _actor_type), do: {:error, :wrong_state}

  @doc """
  Schedules a pick-up for a confirmed order. Saves the pickup details on the order
  and posts a status_change event with the completion link.
  details is a map with keys: date, time, address, instructions, completion_url.
  date and time may be blank — some vendors/buyers agree on a time informally
  in chat rather than through this form.
  """
  def schedule_pickup(%Order{status: :confirmed} = order, details) do
    %{date: date, time: time, address: address, instructions: instructions, completion_url: completion_url} = details
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    has_datetime = (date && date != "") or (time && time != "")
    title = if has_datetime, do: "Pick-up scheduled!", else: "Pick-up info shared"
    date_line = if date && date != "", do: "Date: #{date}\n", else: ""
    time_line = if time && time != "", do: "Time: #{time}\n", else: ""
    instruction_line = if instructions && instructions != "", do: "\n\nSpecial instructions: #{instructions}", else: ""

    body = """
    #{title}

    #{date_line}#{time_line}Address: #{address}#{instruction_line}

    To complete the purchase, use this link once you have your item in hand:
    #{completion_url}

    ⚠️ Only click the link when you have received your item and are ready to complete the transaction.
    """

    Multi.new()
    |> Multi.update(:order, Order.changeset(order, %{
      pickup_date: (if date == "", do: nil, else: date),
      pickup_time: (if time == "", do: nil, else: time),
      pickup_address: address,
      pickup_instructions: (if instructions == "", do: nil, else: instructions),
      pickup_scheduled_at: now
    }))
    |> Multi.run(:event, fn _repo, %{order: updated_order} ->
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: updated_order.conversation_id,
        actor_type: :vendor,
        order_id: updated_order.id,
        to_status: "confirmed",
        body: String.trim(body)
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        Conversations.broadcast_order_event(order.conversation_id, event)
        {:ok, event}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def schedule_pickup(%Order{}, _details), do: {:error, :wrong_state}

  @doc """
  Cancels a previously scheduled pick-up, clearing the pickup details and
  returning the order to :confirmed state (status unchanged). Posts a
  status_change event so both parties are notified.
  """
  def cancel_pickup(%Order{status: :confirmed, pickup_scheduled_at: scheduled_at} = order, actor_type)
      when not is_nil(scheduled_at) and actor_type in [:buyer, :vendor] do
    body =
      if actor_type == :buyer,
        do: "Buyer requested a new pick-up time. Please agree on a new time and reschedule.",
        else: "Vendor cancelled the pick-up. Please agree on a new time."

    Multi.new()
    |> Multi.update(:order, Order.changeset(order, %{
      pickup_date: nil,
      pickup_time: nil,
      pickup_address: nil,
      pickup_instructions: nil,
      pickup_scheduled_at: nil
    }))
    |> Multi.run(:event, fn _repo, %{order: updated_order} ->
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: updated_order.conversation_id,
        actor_type: actor_type,
        order_id: updated_order.id,
        to_status: "confirmed",
        body: body
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, event: event}} ->
        Conversations.broadcast_order_event(order.conversation_id, event)
        {:ok, order}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def cancel_pickup(%Order{}, _actor_type), do: {:error, :wrong_state}

  @doc """
  Returns true if the conversation already has an open order (:requested or
  :confirmed) that contains the given product. Used to detect duplicate requests.
  """
  def has_open_order_for_product?(conversation_id, product_id) do
    Repo.exists?(
      from o in Order,
        join: i in OrderItem, on: i.order_id == o.id,
        where: o.conversation_id == ^conversation_id,
        where: o.status in [:requested, :confirmed],
        where: i.product_id == ^product_id
    )
  end

  @doc "Returns the single most-recent open order for a conversation, or nil. Used when adding items."
  def get_open_order_for_conversation(conversation_id) do
    Order
    |> where([o], o.conversation_id == ^conversation_id)
    |> where([o], o.status in [:requested, :confirmed])
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(1)
    |> preload(:items)
    |> Repo.one()
  end

  @doc "Returns open (:requested or :confirmed) orders for a conversation, newest first, with items preloaded."
  def list_open_orders_for_conversation(conversation_id) do
    Order
    |> where([o], o.conversation_id == ^conversation_id)
    |> where([o], o.status in [:requested, :confirmed])
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> preload(items: [product: :product_images])
    |> Repo.all()
  end

  @doc "Fetches a single order by id with items, buyer, and artist preloaded. Raises if not found."
  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload([:buyer, :artist, items: [product: :product_images]])
  end

  @doc "Returns all orders for a buyer, sorted newest first."
  def list_orders_for_buyer(user_id) do
    Order
    |> where([o], o.buyer_id == ^user_id)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> preload([:items])
    |> Repo.all()
  end

  @doc "Returns all orders for an artist (vendor), sorted newest first."
  def list_orders_for_artist(artist_id) do
    Order
    |> where([o], o.artist_id == ^artist_id)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> preload([:items])
    |> Repo.all()
  end

  # Converts an OrderItem to a price-explicit amendment spec, preserving the
  # snapshot unit_price so price changes on the product don't affect open orders.
  defp to_spec(%OrderItem{} = item) do
    %{product_id: item.product_id, product_title: item.product_title,
      quantity: item.quantity, unit_price: item.unit_price}
  end

  # Same as to_spec/1, but for a whole item list.
  defp to_specs(items), do: Enum.map(items, &to_spec/1)

  # Subtotal + a flat 5% platform fee (rounded to the cent) + total, from a
  # list of %{unit_price, quantity} specs. Shared by create_order and every
  # do_amend-based mutation so the fee is calculated the same way everywhere.
  defp calculate_totals_from_specs(specs) do
    subtotal =
      Enum.reduce(specs, Decimal.new(0), fn %{unit_price: price, quantity: q}, acc ->
        Decimal.add(acc, Decimal.mult(price, Decimal.new(q)))
      end)
    platform_fee = Decimal.mult(subtotal, Decimal.new("0.05")) |> Decimal.round(2)
    total = Decimal.add(subtotal, platform_fee)
    {subtotal, platform_fee, total}
  end

  # Used by create_order only (new items always use current product price).
  defp calculate_totals(items) do
    specs = Enum.map(items, fn %{product: p, quantity: q} ->
      %{unit_price: p.price, quantity: q}
    end)
    calculate_totals_from_specs(specs)
  end

  # Internal workhorse for all amendment paths.
  # specs is a list of %{product_id, product_title, quantity, unit_price}.
  #
  # Deliberately does NOT reset status or clear complete_token/pickup details.
  # Item changes commonly happen in person (buyer adds one more piece while
  # already at the vendor's door for a scheduled pickup) — forcing a fresh
  # vendor re-confirmation and a brand new completion link for that case would
  # be pure friction. The safeguard that matters is buyer-facing: the buyer
  # must see the updated quantity/total before they complete purchase, which
  # the completion page and order sidebar already show live from the DB.
  defp do_amend(%Order{} = order, specs, actor_type, event_body) do
    {subtotal, platform_fee, total} = calculate_totals_from_specs(specs)

    Multi.new()
    |> Multi.update(:order, Order.changeset(order, %{
      subtotal: subtotal,
      platform_fee: platform_fee,
      total: total
    }))
    |> Multi.run(:delete_items, fn _repo, %{order: updated_order} ->
      Repo.delete_all(from(i in OrderItem, where: i.order_id == ^updated_order.id))
      {:ok, :deleted}
    end)
    |> Multi.run(:order_items, fn _repo, %{order: updated_order} ->
      results =
        Enum.map(specs, fn spec ->
          %OrderItem{}
          |> OrderItem.changeset(%{
            order_id: updated_order.id,
            product_id: spec.product_id,
            quantity: spec.quantity,
            unit_price: spec.unit_price,
            product_title: spec.product_title,
            return_policy_snapshot: "All sales final unless item is significantly not as described."
          })
          |> Repo.insert()
        end)

      case Enum.find(results, fn {k, _} -> k == :error end) do
        nil -> {:ok, Enum.map(results, fn {:ok, item} -> item end)}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> Multi.run(:event, fn _repo, %{order: updated_order} ->
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: updated_order.conversation_id,
        actor_type: actor_type,
        order_id: updated_order.id,
        from_status: to_string(order.status),
        to_status: to_string(updated_order.status),
        body: event_body
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order, event: event}} ->
        Conversations.broadcast_order_event(order.conversation_id, event)
        {:ok, order}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
end
