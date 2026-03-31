defmodule ArtsyNeighborWeb.ProductLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures

  describe "Index" do
    test "products listing page loads", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/products")
      assert html =~ "Artsy Neighbor"
    end

    test "shows product title in listing", %{conn: conn} do
      product = product_fixture()
      {:ok, _live, html} = live(conn, ~p"/products")
      assert html =~ product.title
    end
  end

  describe "Show" do
    test "displays product page", %{conn: conn} do
      product = product_fixture()
      {:ok, _live, html} = live(conn, ~p"/products/#{product}")
      assert html =~ product.title
    end
  end
end
