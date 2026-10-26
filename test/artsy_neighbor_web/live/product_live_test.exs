defmodule ArtsyNeighborWeb.ProductLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Products

  describe "Index" do
    test "products listing page loads", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/products")
      assert html =~ "localpalette"
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
      {:ok, _} = ArtsyNeighbor.Products.soft_delete_product(product)

      assert {:error, {:live_redirect, %{to: "/products", flash: flash}}} =
               live(conn, ~p"/products/#{product}")

      assert flash["error"] == "Product not found."
    end

    test "redirects instead of rendering an unavailable product", %{conn: conn} do
      product = product_fixture()
      {:ok, product} = ArtsyNeighbor.Products.update_product(product, %{status: :unavailable})

      assert {:error, {:live_redirect, %{to: "/products"}}} = live(conn, ~p"/products/#{product}")
    end

    test "shows the work's details, the artist's area and the exact price", %{conn: conn} do
      product =
        product_fixture(%{
          title: "Crow with Stones",
          materials: "Oil on round canvas",
          width: "60",
          length: "45",
          unique_work: true,
          price: "640.00"
        })

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ".product-info h1", "Crow with Stones")
      assert has_element?(view, ~s|.product-by a[href="/artists/#{product.artist_id}"]|)
      # Only the postal district, never the full postal code (M5H 2N2).
      assert has_element?(view, ".artist-area", "M5H · Victoria")
      refute render(view) =~ "M5H 2N2"
      assert has_element?(view, ".product-facts", "Oil on round canvas")
      assert has_element?(view, ".product-facts", "60\u00A0×\u00A045\u00A0cm")
      assert has_element?(view, ".product-unique", "Unique work")
      assert has_element?(view, ".product-price", "CA$640")
      refute has_element?(view, ".product-price", "CA$640.00")
    end

    test "a price with cents keeps them", %{conn: conn} do
      product = product_fixture(%{price: "120.5"})
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ".product-price", "CA$120.50")
    end

    test "the arrows and thumbnails switch photos, wrapping around", %{conn: conn} do
      product = product_fixture()

      for position <- 1..3 do
        {:ok, _image} =
          Products.create_product_image(%{
            path: "/uploads/work-#{position}.jpg",
            position: position,
            product_id: product.id
          })
      end

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")
      assert photo_shown?(view, "/uploads/work-1.jpg")

      view |> element(".carousel-arrow.prev") |> render_click()
      assert photo_shown?(view, "/uploads/work-3.jpg")

      view |> element(~s|.work-thumbs button[aria-label="Show photo 2"]|) |> render_click()
      assert photo_shown?(view, "/uploads/work-2.jpg")
      refute photo_shown?(view, "/uploads/work-1.jpg")
    end

    test "a work with one photo has no arrows or thumbnails", %{conn: conn} do
      product = product_fixture()

      {:ok, _image} =
        Products.create_product_image(%{
          path: "/uploads/only.jpg",
          position: 1,
          product_id: product.id
        })

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert photo_shown?(view, "/uploads/only.jpg")
      refute has_element?(view, ".carousel-arrow")
      refute has_element?(view, ".work-thumbs")
    end

    test "the large view shows the current photo and has its own arrows", %{conn: conn} do
      product = product_fixture()

      for position <- 1..2 do
        {:ok, _image} =
          Products.create_product_image(%{
            path: "/uploads/work-#{position}.jpg",
            position: position,
            product_id: product.id
          })
      end

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      # The browser opens it (showModal, from app.js); the page only has
      # to contain it, with the button that opens it.
      assert has_element?(view, "button.work-enlarge")
      assert has_element?(view, ~s|#work-viewer img[src="/uploads/work-1.jpg"]|)
      assert has_element?(view, "#work-viewer .work-viewer-count", "Photo 1 of 2")

      view |> element(".work-viewer-arrow.next") |> render_click()

      assert has_element?(view, ~s|#work-viewer img[src="/uploads/work-2.jpg"]|)
      assert has_element?(view, "#work-viewer .work-viewer-count", "Photo 2 of 2")
      # The page's own photo follows, so closing the large view shows the same one.
      assert photo_shown?(view, "/uploads/work-2.jpg")
    end

    test "a work without photos has no large view", %{conn: conn} do
      product = product_fixture()
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      refute has_element?(view, "#work-viewer")
      refute has_element?(view, "button.work-enlarge")
    end

    test "a logged-out visitor is asked to log in to buy", %{conn: conn} do
      product = product_fixture()
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ~s|a[href="/users/log-in"]|, "Log in to buy")
      assert has_element?(view, ~s|a[href="/users/register"]|, "Create an account")
      refute has_element?(view, "button", "Request to buy")
    end

    test "Request to buy starts an order and opens the conversation", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      product = product_fixture()
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert {:error, {:live_redirect, %{to: "/messages/" <> _conversation_id}}} =
               view |> element("button", "Request to buy") |> render_click()
    end

    test "Send message opens the conversation with the artist", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      product = product_fixture()
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert {:error, {:live_redirect, %{to: "/messages/" <> _conversation_id}}} =
               view |> element("button", "Send message") |> render_click()
    end

    test "the artist sees both buttons disabled on their own work", %{conn: conn} do
      product = product_fixture() |> ArtsyNeighbor.Repo.preload(:artist)
      conn = log_in_user(conn, Accounts.get_user!(product.artist.user_id))
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, "button[disabled]", "Request to buy")
      assert has_element?(view, "button[disabled]", "Send message")

      # A click that gets through anyway does nothing.
      render_click(view, "request_to_buy", %{})
      render_click(view, "message_artist", %{})
      assert has_element?(view, ".product-info h1")
    end

    test "the Back link shows only when the page was opened with one", %{conn: conn} do
      product = product_fixture()

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")
      refute has_element?(view, ".back-under-menu")

      query = [return_to: "/artists/#{product.artist_id}/store", return_label: "Back to the shop"]
      {:ok, view, _html} = live(conn, ~p"/products/#{product}?#{query}")

      assert has_element?(
               view,
               ~s|.back-under-menu[href="/artists/#{product.artist_id}/store"]|,
               "Back to the shop"
             )
    end
  end

  # True when the photo with this path is the one shown (the others are
  # in the page but hidden).
  defp photo_shown?(view, path) do
    has_element?(view, ~s|.work-frame img[src="#{path}"]:not([hidden])|)
  end
end
