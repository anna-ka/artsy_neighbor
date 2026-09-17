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

    test "redirects instead of rendering an archived product (regression: this used to leak)", %{
      conn: conn
    } do
      product = product_fixture()
      {:ok, _} = ArtsyNeighbor.Products.remove_product(product)

      assert {:error, {:live_redirect, %{to: "/products", flash: flash}}} =
               live(conn, ~p"/products/#{product}")

      assert flash["error"] == "Product not found."
    end

    test "redirects instead of rendering an unavailable product", %{conn: conn} do
      product = product_fixture()
      {:ok, product} = ArtsyNeighbor.Products.update_product(product, %{status: :unavailable})

      assert {:error, {:live_redirect, %{to: "/products"}}} = live(conn, ~p"/products/#{product}")
    end
  end
end
