defmodule ArtsyNeighbor.Orders do
  @moduledoc """
  The Orders context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Orders.Order
  alias ArtsyNeighbor.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any order changes.

  The broadcasted messages match the pattern:

    * {:created, %Order{}}
    * {:updated, %Order{}}
    * {:deleted, %Order{}}

  """
  def subscribe_orders(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{key}:orders")
  end

  defp broadcast_order(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ArtsyNeighbor.PubSub, "user:#{key}:orders", message)
  end

  @doc """
  Returns the list of orders.

  ## Examples

      iex> list_orders(scope)
      [%Order{}, ...]

  """
  def list_orders(%Scope{} = scope) do
    Repo.all_by(Order, user_id: scope.user.id)
  end

  @doc """
  Gets a single order.

  Raises `Ecto.NoResultsError` if the Order does not exist.

  ## Examples

      iex> get_order!(scope, 123)
      %Order{}

      iex> get_order!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_order!(%Scope{} = scope, id) do
    Repo.get_by!(Order, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a order.

  ## Examples

      iex> create_order(scope, %{field: value})
      {:ok, %Order{}}

      iex> create_order(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_order(%Scope{} = scope, attrs) do
    with {:ok, order = %Order{}} <-
           %Order{}
           |> Order.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_order(scope, {:created, order})
      {:ok, order}
    end
  end

  @doc """
  Updates a order.

  ## Examples

      iex> update_order(scope, order, %{field: new_value})
      {:ok, %Order{}}

      iex> update_order(scope, order, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_order(%Scope{} = scope, %Order{} = order, attrs) do
    true = order.user_id == scope.user.id

    with {:ok, order = %Order{}} <-
           order
           |> Order.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_order(scope, {:updated, order})
      {:ok, order}
    end
  end

  @doc """
  Deletes a order.

  ## Examples

      iex> delete_order(scope, order)
      {:ok, %Order{}}

      iex> delete_order(scope, order)
      {:error, %Ecto.Changeset{}}

  """
  def delete_order(%Scope{} = scope, %Order{} = order) do
    true = order.user_id == scope.user.id

    with {:ok, order = %Order{}} <-
           Repo.delete(order) do
      broadcast_order(scope, {:deleted, order})
      {:ok, order}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking order changes.

  ## Examples

      iex> change_order(scope, order)
      %Ecto.Changeset{data: %Order{}}

  """
  def change_order(%Scope{} = scope, %Order{} = order, attrs \\ %{}) do
    true = order.user_id == scope.user.id

    Order.changeset(order, attrs, scope)
  end

  alias ArtsyNeighbor.Orders.OrderItem
  alias ArtsyNeighbor.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any order_item changes.

  The broadcasted messages match the pattern:

    * {:created, %OrderItem{}}
    * {:updated, %OrderItem{}}
    * {:deleted, %OrderItem{}}

  """
  def subscribe_order_items(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(ArtsyNeighbor.PubSub, "user:#{key}:order_items")
  end

  defp broadcast_order_item(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(ArtsyNeighbor.PubSub, "user:#{key}:order_items", message)
  end

  @doc """
  Returns the list of order_items.

  ## Examples

      iex> list_order_items(scope)
      [%OrderItem{}, ...]

  """
  def list_order_items(%Scope{} = scope) do
    Repo.all_by(OrderItem, user_id: scope.user.id)
  end

  @doc """
  Gets a single order_item.

  Raises `Ecto.NoResultsError` if the Order item does not exist.

  ## Examples

      iex> get_order_item!(scope, 123)
      %OrderItem{}

      iex> get_order_item!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_order_item!(%Scope{} = scope, id) do
    Repo.get_by!(OrderItem, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a order_item.

  ## Examples

      iex> create_order_item(scope, %{field: value})
      {:ok, %OrderItem{}}

      iex> create_order_item(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_order_item(%Scope{} = scope, attrs) do
    with {:ok, order_item = %OrderItem{}} <-
           %OrderItem{}
           |> OrderItem.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_order_item(scope, {:created, order_item})
      {:ok, order_item}
    end
  end

  @doc """
  Updates a order_item.

  ## Examples

      iex> update_order_item(scope, order_item, %{field: new_value})
      {:ok, %OrderItem{}}

      iex> update_order_item(scope, order_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_order_item(%Scope{} = scope, %OrderItem{} = order_item, attrs) do
    true = order_item.user_id == scope.user.id

    with {:ok, order_item = %OrderItem{}} <-
           order_item
           |> OrderItem.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_order_item(scope, {:updated, order_item})
      {:ok, order_item}
    end
  end

  @doc """
  Deletes a order_item.

  ## Examples

      iex> delete_order_item(scope, order_item)
      {:ok, %OrderItem{}}

      iex> delete_order_item(scope, order_item)
      {:error, %Ecto.Changeset{}}

  """
  def delete_order_item(%Scope{} = scope, %OrderItem{} = order_item) do
    true = order_item.user_id == scope.user.id

    with {:ok, order_item = %OrderItem{}} <-
           Repo.delete(order_item) do
      broadcast_order_item(scope, {:deleted, order_item})
      {:ok, order_item}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking order_item changes.

  ## Examples

      iex> change_order_item(scope, order_item)
      %Ecto.Changeset{data: %OrderItem{}}

  """
  def change_order_item(%Scope{} = scope, %OrderItem{} = order_item, attrs \\ %{}) do
    true = order_item.user_id == scope.user.id

    OrderItem.changeset(order_item, attrs, scope)
  end
end
