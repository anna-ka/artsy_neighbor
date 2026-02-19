defmodule ArtsyNeighborWeb.ProductImageLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures

  @create_attrs %{position: 42, path: "some path"}
  @update_attrs %{position: 43, path: "some updated path"}
  @invalid_attrs %{position: nil, path: nil}
  defp create_product_image(_) do
    product_image = product_image_fixture()

    %{product_image: product_image}
  end

  describe "Index" do
    setup [:create_product_image]

    test "lists all product_images", %{conn: conn, product_image: product_image} do
      {:ok, _index_live, html} = live(conn, ~p"/product_images")

      assert html =~ "Listing Product images"
      assert html =~ product_image.path
    end

    test "saves new product_image", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/product_images")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Product image")
               |> render_click()
               |> follow_redirect(conn, ~p"/product_images/new")

      assert render(form_live) =~ "New Product image"

      assert form_live
             |> form("#product_image-form", product_image: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#product_image-form", product_image: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/product_images")

      html = render(index_live)
      assert html =~ "Product image created successfully"
      assert html =~ "some path"
    end

    test "updates product_image in listing", %{conn: conn, product_image: product_image} do
      {:ok, index_live, _html} = live(conn, ~p"/product_images")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#product_images-#{product_image.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/product_images/#{product_image}/edit")

      assert render(form_live) =~ "Edit Product image"

      assert form_live
             |> form("#product_image-form", product_image: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#product_image-form", product_image: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/product_images")

      html = render(index_live)
      assert html =~ "Product image updated successfully"
      assert html =~ "some updated path"
    end

    test "deletes product_image in listing", %{conn: conn, product_image: product_image} do
      {:ok, index_live, _html} = live(conn, ~p"/product_images")

      assert index_live |> element("#product_images-#{product_image.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#product_images-#{product_image.id}")
    end
  end

  describe "Show" do
    setup [:create_product_image]

    test "displays product_image", %{conn: conn, product_image: product_image} do
      {:ok, _show_live, html} = live(conn, ~p"/product_images/#{product_image}")

      assert html =~ "Show Product image"
      assert html =~ product_image.path
    end

    test "updates product_image and returns to show", %{conn: conn, product_image: product_image} do
      {:ok, show_live, _html} = live(conn, ~p"/product_images/#{product_image}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/product_images/#{product_image}/edit?return_to=show")

      assert render(form_live) =~ "Edit Product image"

      assert form_live
             |> form("#product_image-form", product_image: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#product_image-form", product_image: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/product_images/#{product_image}")

      html = render(show_live)
      assert html =~ "Product image updated successfully"
      assert html =~ "some updated path"
    end
  end
end
