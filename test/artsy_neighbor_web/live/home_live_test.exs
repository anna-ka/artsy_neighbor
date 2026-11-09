defmodule ArtsyNeighborWeb.HomeLiveTest do
  # Not async: these tests change the hero setting (:home_hero), which is
  # shared by the whole app while they run.
  use ArtsyNeighborWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.CategoriesFixtures

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Repo

  # Points the hero at the given work for one test, and puts the real
  # setting back afterwards.
  defp use_hero_work(product_id) do
    original = Application.fetch_env!(:artsy_neighbor, :home_hero)

    Application.put_env(:artsy_neighbor, :home_hero,
      image: "/images/site/hero-protectress.jpg",
      alt: "Detail of a test painting",
      product_id: product_id
    )

    on_exit(fn -> Application.put_env(:artsy_neighbor, :home_hero, original) end)
  end

  describe "Hero" do
    test "shows the welcome and the three steps of How it works", %{conn: conn} do
      product = product_fixture()
      use_hero_work(product.id)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h1", "Greater Victoria is brimming with art.")
      assert has_element?(live, "#how-it-works-button[aria-expanded=false]", "How it works")
      # The steps are on the page, closed until the button is clicked.
      assert has_element?(live, "#how-it-works[hidden] li", "Find a work you love")
      assert has_element?(live, "#how-it-works li", "Request to buy")
      assert has_element?(live, "#how-it-works li", "Pick it up from the artist")
    end

    test "credits the work and links the picture to it while it is for sale", %{conn: conn} do
      product = product_fixture(%{title: "Crow with Stones"})
      use_hero_work(product.id)
      product = Products.get_product_with_associations(product.id)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, ~s(a.home-hero-art[href="/products/#{product.id}"] img))

      assert has_element?(
               live,
               "a.home-hero-art .home-hero-credit",
               "Crow with Stones (detail) · #{product.artist.nickname} · M5H · Victoria"
             )
    end

    test "keeps the picture and credit, without a link, when the work isn't for sale", %{
      conn: conn
    } do
      product = product_fixture(%{title: "Crow with Stones", status: :unavailable})
      use_hero_work(product.id)

      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, "a.home-hero-art")
      assert has_element?(live, "div.home-hero-art img")
      assert has_element?(live, "div.home-hero-art .home-hero-credit", "Crow with Stones")
    end

    test "shows the picture without a credit when the work doesn't exist", %{conn: conn} do
      use_hero_work(-1)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "div.home-hero-art img")
      refute has_element?(live, ".home-hero-credit")
    end

    test "shows the picture without a credit when no work is set (as in test and prod by default)",
         %{conn: conn} do
      use_hero_work(nil)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "div.home-hero-art img")
      refute has_element?(live, ".home-hero-credit")
    end
  end

  describe "Popular categories" do
    # Makes a category with the given number of works for sale.
    defp category_with_works(name, count) do
      category = category_fixture(%{name: name})

      Enum.each(1..count, fn _ ->
        product_fixture(%{category_id: category.id})
      end)

      category
    end

    test "shows the first 4 tiles, most works first, each linking to its works", %{conn: conn} do
      paintings = category_with_works("Paintings", 3)
      category_with_works("Pottery", 2)
      category_with_works("Jewelry", 1)
      category_with_works("Sculptures", 1)
      category_with_works("Clothing", 1)
      category_fixture(%{name: "Empty"})

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h2", "Popular categories")

      assert has_element?(
               live,
               ~s|#popular-categories a:nth-child(1)[href="/products?category_id=#{paintings.id}"]|,
               "Paintings"
             )

      assert has_element?(live, "#popular-categories a:nth-child(2)", "Pottery")
      # Ties by name: Clothing, Jewelry, Sculptures; Sculptures waits
      # behind "Show more categories".
      assert has_element?(live, "#popular-categories a:nth-child(3):not([hidden])", "Clothing")
      assert has_element?(live, "#popular-categories a:nth-child(4):not([hidden])", "Jewelry")
      assert has_element?(live, "#popular-categories a:nth-child(5)[hidden]", "Sculptures")
      refute has_element?(live, "#popular-categories a", "Empty")

      assert has_element?(
               live,
               "#categories-toggle[aria-expanded=false]",
               "Show more categories"
             )
    end

    test "has no Show more button with 4 categories or fewer", %{conn: conn} do
      category_with_works("Paintings", 1)
      category_with_works("Pottery", 1)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#popular-categories a", "Pottery")
      refute has_element?(live, "#categories-toggle")
    end
  end

  describe "Popular artists" do
    # The ordering is tested in ArtistsTest (list_popular_artists/1);
    # these check what the cards show.
    test "shows a card per artist, with name, area, stars, works and links", %{conn: conn} do
      artist =
        ArtsyNeighbor.ArtistsFixtures.artist_fixture(%{
          nickname: "Maren Holt",
          area_code: "V8V 4P9"
        })

      work = product_fixture(%{artist_id: artist.id, title: "Otter at Dusk"})

      for stars <- [5, 5, 4] do
        buyer = ArtsyNeighbor.AccountsFixtures.user_fixture()

        order =
          ArtsyNeighbor.OrdersFixtures.order_fixture(buyer_id: buyer.id, artist_id: artist.id)
          |> ArtsyNeighbor.OrdersFixtures.complete_order(20)

        ArtsyNeighbor.ReviewsFixtures.vendor_review_fixture(%{
          order_id: order.id,
          reviewer_id: buyer.id,
          artist_id: artist.id,
          stars: stars
        })
      end

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h2", "Popular artists")
      assert has_element?(live, ~s|a[href="/artists"]|, "See all artists")

      card = "#popular-artists .artist-card"
      assert has_element?(live, ~s|#{card} h3 a[href="/artists/#{artist.id}"]|, "Maren Holt")
      assert has_element?(live, "#{card} .artist-card-area", "V8V")
      assert has_element?(live, "#{card} .artist-card-rating", "4.7 · 3 reviews")

      assert has_element?(
               live,
               ~s|#{card} a[href="/products/#{work.id}"] img[alt="Otter at Dusk"]|
             )

      assert has_element?(live, "#{card} .artist-card-visit", "Visit page")
    end

    test "shows no stars for an artist without reviews", %{conn: conn} do
      product_fixture()

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#popular-artists .artist-card")
      refute has_element?(live, "#popular-artists .artist-card-rating")
    end

    test "has no Popular artists section when nothing is for sale", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, "h2", "Popular artists")
    end
  end

  describe "New works" do
    # Makes a work with the given title, added `days` ago, so "newest
    # first" doesn't depend on the order the fixtures were made in.
    defp work_added_days_ago(title, days) do
      added_at =
        DateTime.utc_now()
        |> DateTime.add(-days, :day)
        |> DateTime.truncate(:second)

      product_fixture(%{title: title})
      |> Ecto.Changeset.change(inserted_at: added_at)
      |> Repo.update!()
    end

    test "shows the 8 newest works, newest first, without prices", %{conn: conn} do
      Enum.each(1..9, fn days -> work_added_days_ago("Work #{days}", days) end)

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h2", "New works")
      assert has_element?(live, ~s|a[href="/products?sort_by=newest"]|, "See all new works")
      assert has_element?(live, "#new-works a:nth-child(1)", "Work 1")
      assert has_element?(live, "#new-works a:nth-child(8)", "Work 8")
      refute has_element?(live, "#new-works a", "Work 9")
      refute has_element?(live, "#new-works .artwork-card-price")
    end

    test "leaves out works that aren't for sale", %{conn: conn} do
      work = product_fixture(%{title: "Sold Out Seascape"})
      {:ok, _} = Products.soft_delete_product(work)

      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, "#new-works a", "Sold Out Seascape")
    end

    test "has no New works section when nothing is for sale", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, "h2", "New works")
    end
  end

  describe "Invitation to artists" do
    test "invites visitors to offer their art", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "h2", "Are you an artist in Greater Victoria?")
      assert has_element?(live, ~s|.home-invite a[href="/offer-art"]|, "Offer your art")
    end

    test "is left out for a visitor who already has an artist page", %{conn: conn} do
      artist = ArtsyNeighbor.ArtistsFixtures.artist_fixture()
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))

      {:ok, live, _html} = live(conn, ~p"/")

      refute has_element?(live, "h2", "Are you an artist in Greater Victoria?")
    end
  end
end
