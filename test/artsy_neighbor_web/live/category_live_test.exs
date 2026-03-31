defmodule ArtsyNeighborWeb.CategoryLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.CategoriesFixtures

  describe "Index" do
    test "lists categories page loads", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/categories")
      assert html =~ "Artsy Neighbor"
    end

    test "shows category in listing", %{conn: conn} do
      category = category_fixture()
      {:ok, _live, html} = live(conn, ~p"/categories")
      assert html =~ category.name
    end
  end

  describe "Show" do
    test "displays category page", %{conn: conn} do
      category = category_fixture()
      {:ok, _live, html} = live(conn, ~p"/categories/#{category}")
      assert html =~ category.name
    end
  end
end
