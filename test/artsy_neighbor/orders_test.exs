defmodule ArtsyNeighbor.OrdersTest do
  use ArtsyNeighbor.DataCase

  alias ArtsyNeighbor.Orders

  describe "orders" do
    alias ArtsyNeighbor.Orders.Order

    import ArtsyNeighbor.AccountsFixtures, only: [user_scope_fixture: 0]
    import ArtsyNeighbor.OrdersFixtures

    @invalid_attrs %{status: nil, total: nil, delivery_method: nil, delivery_address: nil, subtotal: nil, platform_fee: nil, complete_token: nil, complete_token_at: nil}

    test "list_orders/1 returns all scoped orders" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      order = order_fixture(scope)
      other_order = order_fixture(other_scope)
      assert Orders.list_orders(scope) == [order]
      assert Orders.list_orders(other_scope) == [other_order]
    end

    test "get_order!/2 returns the order with given id" do
      scope = user_scope_fixture()
      order = order_fixture(scope)
      other_scope = user_scope_fixture()
      assert Orders.get_order!(scope, order.id) == order
      assert_raise Ecto.NoResultsError, fn -> Orders.get_order!(other_scope, order.id) end
    end

    test "create_order/2 with valid data creates a order" do
      valid_attrs = %{status: "some status", total: "120.5", delivery_method: "some delivery_method", delivery_address: "some delivery_address", subtotal: "120.5", platform_fee: "120.5", complete_token: "some complete_token", complete_token_at: ~U[2026-04-06 19:49:00Z]}
      scope = user_scope_fixture()

      assert {:ok, %Order{} = order} = Orders.create_order(scope, valid_attrs)
      assert order.status == "some status"
      assert order.total == Decimal.new("120.5")
      assert order.delivery_method == "some delivery_method"
      assert order.delivery_address == "some delivery_address"
      assert order.subtotal == Decimal.new("120.5")
      assert order.platform_fee == Decimal.new("120.5")
      assert order.complete_token == "some complete_token"
      assert order.complete_token_at == ~U[2026-04-06 19:49:00Z]
      assert order.user_id == scope.user.id
    end

    test "create_order/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Orders.create_order(scope, @invalid_attrs)
    end

    test "update_order/3 with valid data updates the order" do
      scope = user_scope_fixture()
      order = order_fixture(scope)
      update_attrs = %{status: "some updated status", total: "456.7", delivery_method: "some updated delivery_method", delivery_address: "some updated delivery_address", subtotal: "456.7", platform_fee: "456.7", complete_token: "some updated complete_token", complete_token_at: ~U[2026-04-07 19:49:00Z]}

      assert {:ok, %Order{} = order} = Orders.update_order(scope, order, update_attrs)
      assert order.status == "some updated status"
      assert order.total == Decimal.new("456.7")
      assert order.delivery_method == "some updated delivery_method"
      assert order.delivery_address == "some updated delivery_address"
      assert order.subtotal == Decimal.new("456.7")
      assert order.platform_fee == Decimal.new("456.7")
      assert order.complete_token == "some updated complete_token"
      assert order.complete_token_at == ~U[2026-04-07 19:49:00Z]
    end

    test "update_order/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      order = order_fixture(scope)

      assert_raise MatchError, fn ->
        Orders.update_order(other_scope, order, %{})
      end
    end

    test "update_order/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      order = order_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Orders.update_order(scope, order, @invalid_attrs)
      assert order == Orders.get_order!(scope, order.id)
    end

    test "delete_order/2 deletes the order" do
      scope = user_scope_fixture()
      order = order_fixture(scope)
      assert {:ok, %Order{}} = Orders.delete_order(scope, order)
      assert_raise Ecto.NoResultsError, fn -> Orders.get_order!(scope, order.id) end
    end

    test "delete_order/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      order = order_fixture(scope)
      assert_raise MatchError, fn -> Orders.delete_order(other_scope, order) end
    end

    test "change_order/2 returns a order changeset" do
      scope = user_scope_fixture()
      order = order_fixture(scope)
      assert %Ecto.Changeset{} = Orders.change_order(scope, order)
    end
  end

  describe "order_items" do
    alias ArtsyNeighbor.Orders.OrderItem

    import ArtsyNeighbor.AccountsFixtures, only: [user_scope_fixture: 0]
    import ArtsyNeighbor.OrdersFixtures

    @invalid_attrs %{quantity: nil, unit_price: nil, product_title: nil, return_policy_snapshot: nil, selected_options: nil}

    test "list_order_items/1 returns all scoped order_items" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      other_order_item = order_item_fixture(other_scope)
      assert Orders.list_order_items(scope) == [order_item]
      assert Orders.list_order_items(other_scope) == [other_order_item]
    end

    test "get_order_item!/2 returns the order_item with given id" do
      scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      other_scope = user_scope_fixture()
      assert Orders.get_order_item!(scope, order_item.id) == order_item
      assert_raise Ecto.NoResultsError, fn -> Orders.get_order_item!(other_scope, order_item.id) end
    end

    test "create_order_item/2 with valid data creates a order_item" do
      valid_attrs = %{quantity: 42, unit_price: "120.5", product_title: "some product_title", return_policy_snapshot: "some return_policy_snapshot", selected_options: %{}}
      scope = user_scope_fixture()

      assert {:ok, %OrderItem{} = order_item} = Orders.create_order_item(scope, valid_attrs)
      assert order_item.quantity == 42
      assert order_item.unit_price == Decimal.new("120.5")
      assert order_item.product_title == "some product_title"
      assert order_item.return_policy_snapshot == "some return_policy_snapshot"
      assert order_item.selected_options == %{}
      assert order_item.user_id == scope.user.id
    end

    test "create_order_item/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Orders.create_order_item(scope, @invalid_attrs)
    end

    test "update_order_item/3 with valid data updates the order_item" do
      scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      update_attrs = %{quantity: 43, unit_price: "456.7", product_title: "some updated product_title", return_policy_snapshot: "some updated return_policy_snapshot", selected_options: %{}}

      assert {:ok, %OrderItem{} = order_item} = Orders.update_order_item(scope, order_item, update_attrs)
      assert order_item.quantity == 43
      assert order_item.unit_price == Decimal.new("456.7")
      assert order_item.product_title == "some updated product_title"
      assert order_item.return_policy_snapshot == "some updated return_policy_snapshot"
      assert order_item.selected_options == %{}
    end

    test "update_order_item/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      order_item = order_item_fixture(scope)

      assert_raise MatchError, fn ->
        Orders.update_order_item(other_scope, order_item, %{})
      end
    end

    test "update_order_item/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Orders.update_order_item(scope, order_item, @invalid_attrs)
      assert order_item == Orders.get_order_item!(scope, order_item.id)
    end

    test "delete_order_item/2 deletes the order_item" do
      scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      assert {:ok, %OrderItem{}} = Orders.delete_order_item(scope, order_item)
      assert_raise Ecto.NoResultsError, fn -> Orders.get_order_item!(scope, order_item.id) end
    end

    test "delete_order_item/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      assert_raise MatchError, fn -> Orders.delete_order_item(other_scope, order_item) end
    end

    test "change_order_item/2 returns a order_item changeset" do
      scope = user_scope_fixture()
      order_item = order_item_fixture(scope)
      assert %Ecto.Changeset{} = Orders.change_order_item(scope, order_item)
    end
  end
end
