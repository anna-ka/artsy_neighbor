defmodule ArtsyNeighbor.Orders do
  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Orders.OrderItem
  alias ArtsyNeighbor.Conversations.Conversation
  alias ArtsyNeighbor.Conversations.ConversationEvent
  alias ArtsyNeighbor.Accounts.User

  @doc """
  Creates an order within an existing conversation.
  items is a list of %{product: product, quantity: integer}.
  Atomically inserts the order, order items, a system ConversationEvent,
  and stamps conversation.last_event_at.
  """
  def create_order(conversation, buyer, artist, items, delivery_method \\ :pickup) do
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
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: conversation.id,
        actor_type: :buyer,
        actor_id: buyer.id,
        order_id: order.id,
        to_status: "requested"
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
      {:ok, %{order: order}} -> {:ok, order}
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
        to_status: "confirmed"
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, order}
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
      Multi.new()
      |> Multi.update(:order, Order.changeset(order, %{status: :completed}))
      |> Multi.run(:event, fn _repo, %{order: updated_order} ->
        %ConversationEvent{event_type: :status_change}
        |> ConversationEvent.status_change_changeset(%{
          conversation_id: updated_order.conversation_id,
          actor_type: :buyer,
          order_id: updated_order.id,
          from_status: "confirmed",
          to_status: "completed"
        })
        |> Repo.insert()
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{order: order}} -> {:ok, order}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, :invalid_token}
    end
  end

  def complete_pickup(%Order{}, _token), do: {:error, :wrong_state}

  @doc """
  Cancels an order. Can be called by either party.
  actor_type must be :buyer or :vendor.
  Posts a system ConversationEvent recording who cancelled.
  """
  def cancel_order(%Order{} = order, actor_type) when actor_type in [:buyer, :vendor] do
    Multi.new()
    |> Multi.update(:order, Order.changeset(order, %{status: :cancelled}))
    |> Multi.run(:event, fn _repo, %{order: updated_order} ->
      %ConversationEvent{event_type: :status_change}
      |> ConversationEvent.status_change_changeset(%{
        conversation_id: updated_order.conversation_id,
        actor_type: actor_type,
        order_id: updated_order.id,
        from_status: to_string(order.status),
        to_status: "cancelled"
      })
      |> Repo.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, order}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Fetches a single order by id with items, buyer, and artist preloaded.
  Raises Ecto.NoResultsError if not found.
  """
  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload([:items, :buyer, :artist])
  end

  @doc "Returns all orders for a buyer, sorted newest first."
  def list_orders_for_buyer(user_id) do
    Order
    |> where([o], o.buyer_id == ^user_id)
    |> order_by([o], desc: o.inserted_at)
    |> preload([:items])
    |> Repo.all()
  end

  @doc "Returns all orders for an artist (vendor), sorted newest first."
  def list_orders_for_artist(artist_id) do
    Order
    |> where([o], o.artist_id == ^artist_id)
    |> order_by([o], desc: o.inserted_at)
    |> preload([:items])
    |> Repo.all()
  end

  defp calculate_totals(items) do
    subtotal =
      Enum.reduce(items, Decimal.new(0), fn %{product: p, quantity: q}, acc ->
        Decimal.add(acc, Decimal.mult(p.price, Decimal.new(q)))
      end)

    platform_fee = Decimal.mult(subtotal, Decimal.new("0.05")) |> Decimal.round(2)
    total = Decimal.add(subtotal, platform_fee)
    {subtotal, platform_fee, total}
  end
end
