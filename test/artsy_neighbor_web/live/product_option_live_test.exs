defmodule ArtsyNeighborWeb.ProductOptionLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures

  @create_attrs %{name: "some name", values: ["option1", "option2"], descr: "some descr"}
  @update_attrs %{name: "some updated name", values: ["option1"], descr: "some updated descr"}
  @invalid_attrs %{name: nil, values: [], descr: nil}
  defp create_product_option(_) do
    product_option = product_option_fixture()

    %{product_option: product_option}
  end

  describe "Index" do
    setup [:create_product_option]

    test "lists all product_options", %{conn: conn, product_option: product_option} do
      {:ok, _index_live, html} = live(conn, ~p"/product_options")

      assert html =~ "Listing Product options"
      assert html =~ product_option.name
    end

    test "saves new product_option", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/product_options")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Product option")
               |> render_click()
               |> follow_redirect(conn, ~p"/product_options/new")

      assert render(form_live) =~ "New Product option"

      assert form_live
             |> form("#product_option-form", product_option: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#product_option-form", product_option: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/product_options")

      html = render(index_live)
      assert html =~ "Product option created successfully"
      assert html =~ "some name"
    end

    test "updates product_option in listing", %{conn: conn, product_option: product_option} do
      {:ok, index_live, _html} = live(conn, ~p"/product_options")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#product_options-#{product_option.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/product_options/#{product_option}/edit")

      assert render(form_live) =~ "Edit Product option"

      assert form_live
             |> form("#product_option-form", product_option: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#product_option-form", product_option: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/product_options")

      html = render(index_live)
      assert html =~ "Product option updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes product_option in listing", %{conn: conn, product_option: product_option} do
      {:ok, index_live, _html} = live(conn, ~p"/product_options")

      assert index_live |> element("#product_options-#{product_option.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#product_options-#{product_option.id}")
    end
  end

  describe "Show" do
    setup [:create_product_option]

    test "displays product_option", %{conn: conn, product_option: product_option} do
      {:ok, _show_live, html} = live(conn, ~p"/product_options/#{product_option}")

      assert html =~ "Show Product option"
      assert html =~ product_option.name
    end

    test "updates product_option and returns to show", %{conn: conn, product_option: product_option} do
      {:ok, show_live, _html} = live(conn, ~p"/product_options/#{product_option}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/product_options/#{product_option}/edit?return_to=show")

      assert render(form_live) =~ "Edit Product option"

      assert form_live
             |> form("#product_option-form", product_option: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#product_option-form", product_option: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/product_options/#{product_option}")

      html = render(show_live)
      assert html =~ "Product option updated successfully"
      assert html =~ "some updated name"
    end
  end
end
