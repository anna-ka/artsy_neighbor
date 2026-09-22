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

    test "redirects with a flash when the category is archived", %{conn: conn} do
      {:ok, archived} = category_fixture() |> ArtsyNeighbor.Categories.soft_delete_category()

      assert {:error, {:live_redirect, %{to: "/categories", flash: flash}}} =
               live(conn, ~p"/categories/#{archived}")

      assert flash["error"] == "Category not found."
    end

    test "redirects with a flash when the category does not exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/categories", flash: flash}}} =
               live(conn, ~p"/categories/0")

      assert flash["error"] == "Category not found."
    end
  end
end
