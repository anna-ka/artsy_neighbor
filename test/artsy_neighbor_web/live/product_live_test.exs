defmodule ArtsyNeighborWeb.ProductLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.OrdersFixtures
  import ArtsyNeighbor.ReviewsFixtures

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

    test "shows About this work, Details, and the artist's pickup and delivery", %{conn: conn} do
      artist =
        ArtsyNeighbor.ArtistsFixtures.artist_fixture(%{
          delivery_options: ["pickup", "shipping"],
          delivery_info: %{"pickup" => "Weekday afternoons in Fernwood."}
        })

      product =
        product_fixture(%{
          artist_id: artist.id,
          descr: "A crow near Ross Bay.\nThe stones are from the same beach.",
          details: "Painted in 2025."
        })

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ".product-sections h2", "About this work")
      # Each line the artist typed is its own paragraph.
      assert has_element?(view, ".product-sections p", "A crow near Ross Bay.")
      assert has_element?(view, ".product-sections p", "The stones are from the same beach.")
      assert has_element?(view, ".product-sections h2", "Details")
      assert has_element?(view, ".product-sections p", "Painted in 2025.")
      assert has_element?(view, ".product-sections h2", "Pickup and delivery")
      assert has_element?(view, ".delivery-list li", "Pickup at the artist's studio")
      assert has_element?(view, ".delivery-list li", "Weekday afternoons in Fernwood.")
      assert has_element?(view, ".delivery-list li", "Shipping")
      # The old page's made-up returns text is gone.
      refute render(view) =~ "original packaging"
    end

    test "no Pickup and delivery section when the artist has no options", %{conn: conn} do
      artist = ArtsyNeighbor.ArtistsFixtures.artist_fixture(%{delivery_options: []})
      product = product_fixture(%{artist_id: artist.id})

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      refute has_element?(view, ".product-sections h2", "Pickup and delivery")
    end

    test "a work with reviews: the star row and Reviews of this work", %{conn: conn} do
      product = product_fixture()
      reviewed(product, stars: 5, body: "Even lovelier in person.")
      reviewed(product, stars: 4, body: "Easy pickup.")

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      # Just above the price, a link down to the reviews.
      assert has_element?(
               view,
               ~s|.product-rating a[href="#work-reviews"]|,
               "Reviews of this work"
             )

      assert has_element?(view, "#work-reviews h2", "Reviews of this work")
      assert has_element?(view, "#work-reviews", "4.5 out of 5 · 2 reviews")
      # One or two reviews are simply shown, with nothing to open.
      assert has_element?(view, "#work-reviews .review", "Even lovelier in person.")
      assert has_element?(view, "#work-reviews .review", "Easy pickup.")
      refute has_element?(view, "#work-reviews-list")
      assert has_element?(view, ~s|#work-reviews a[href="#top"]|, "Back to top")
    end

    test "three or more reviews are closed behind See reviews", %{conn: conn} do
      product = product_fixture()
      reviewed(product, stars: 5, body: "Even lovelier in person.")
      reviewed(product, stars: 4, body: "Easy pickup.")
      reviewed(product, stars: 5, body: "Beautifully framed.")

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      # The list is in the page, closed until "See reviews ›" is pressed.
      assert has_element?(view, "#work-reviews-list:not([open]) summary", "See reviews")
      assert has_element?(view, "#work-reviews-list .review", "Even lovelier in person.")
      assert has_element?(view, "#work-reviews-list .review", "Beautifully framed.")
    end

    test "a work without reviews says so, near the price and in the section", %{conn: conn} do
      product = product_fixture()
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      # Plain text near the price, not a link.
      assert has_element?(view, ".product-rating", "No reviews of this work yet")
      refute has_element?(view, ".product-rating a")
      assert has_element?(view, "#work-reviews h2", "Reviews of this work")
      assert has_element?(view, "#work-reviews", "No reviews yet.")
      refute has_element?(view, "#work-reviews-list")
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

  describe "Show: below the top" do
    test "More by the artist: their other works, newest first, and a link to the Shop tab",
         %{conn: conn} do
      product = product_fixture() |> ArtsyNeighbor.Repo.preload(:artist)
      artist_id = product.artist_id

      for days <- [5, 4, 3, 2, 1] do
        product_fixture(%{artist_id: artist_id, title: "Other work #{days}"})
        |> made_days_ago(days)
      end

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")
      nickname = product.artist.nickname

      assert has_element?(view, "#more-by-artist h2", "More by #{nickname}")
      # The four newest: the oldest of the five is left out, and so is
      # this work itself.
      assert has_element?(view, "#more-by-artist .artwork-card", "Other work 1")
      assert has_element?(view, "#more-by-artist .artwork-card", "Other work 4")
      refute has_element?(view, "#more-by-artist .artwork-card", "Other work 5")
      refute has_element?(view, ~s|#more-by-artist a[href="/products/#{product.id}"]|)

      assert has_element?(
               view,
               ~s|.product-see-all a[href="/artists/#{artist_id}/store"]|,
               "See all works by #{nickname}"
             )
    end

    test "You may also like: works by other artists in the same category", %{conn: conn} do
      product = product_fixture()
      similar = product_fixture(%{category_id: product.category_id, title: "A neighbouring work"})

      _same_artist =
        product_fixture(%{
          artist_id: product.artist_id,
          category_id: product.category_id,
          title: "Same artist's work"
        })

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, "#similar-works h2", "You may also like")
      assert has_element?(view, ~s|#similar-works a[href="/products/#{similar.id}"]|)
      # The artist's own works are under More by, not here.
      assert has_element?(view, "#more-by-artist .artwork-card", "Same artist")
      refute has_element?(view, "#similar-works .artwork-card", "Same artist")
    end

    test "no sections when there are no other works", %{conn: conn} do
      product = product_fixture()
      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      refute has_element?(view, ".product-more")
      refute has_element?(view, ".product-divider")
    end

    test "a work whose category was deleted still has its page", %{conn: conn} do
      product = product_fixture()

      product
      |> Ecto.Changeset.change(category_id: nil)
      |> ArtsyNeighbor.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ".product-info h1", product.title)
      refute has_element?(view, "#similar-works")
    end
  end

  # Sets when the product was added, `days` ago, so "newest first" can be
  # tested without depending on the order the fixtures were made in.
  defp made_days_ago(product, days) do
    added_at =
      DateTime.utc_now()
      |> DateTime.add(-days, :day)
      |> DateTime.truncate(:second)

    product
    |> Ecto.Changeset.change(inserted_at: added_at)
    |> ArtsyNeighbor.Repo.update!()
  end

  # A visible review of the work: a completed order, 20 days ago (past
  # the 14 days, so the public may see it), reviewed by a new buyer.
  defp reviewed(product, opts) do
    buyer = ArtsyNeighbor.AccountsFixtures.user_fixture()

    order =
      order_fixture(buyer_id: buyer.id, artist_id: product.artist_id)
      |> complete_order(20)

    product_review_fixture(%{
      order_id: order.id,
      product_id: product.id,
      reviewer_id: buyer.id,
      stars: Keyword.fetch!(opts, :stars),
      body: Keyword.fetch!(opts, :body)
    })
  end

  # True when the photo with this path is the one shown (the others are
  # in the page but hidden).
  defp photo_shown?(view, path) do
    has_element?(view, ~s|.work-frame img[src="#{path}"]:not([hidden])|)
  end
end
