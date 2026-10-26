defmodule ArtsyNeighborWeb.HomeLiveTest do
  # Not async: these tests change the hero setting (:home_hero), which is
  # shared by the whole app while they run.
  use ArtsyNeighborWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures

  alias ArtsyNeighbor.Products

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
      product = product_fixture(%{title: "Crow with Stones"})
      {:ok, _} = Products.update_product(product, %{status: :unavailable})
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
  end
end
