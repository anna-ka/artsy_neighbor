defmodule ArtsyNeighborWeb.ArtistLiveTest do
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures

  alias ArtsyNeighbor.Accounts

  # The artist page (ArtistLive.Show): one page, three tabs.

  describe "tabs" do
    test "the Works tab is the artist's main address", %{conn: conn} do
      artist = artist_fixture()
      {:ok, view, html} = live(conn, ~p"/artists/#{artist}")

      assert html =~ artist.nickname
      assert has_element?(view, ~s|.artist-tab[aria-current="page"]|, "Works")
      refute has_element?(view, ".artist-top.compact")
    end

    test "clicking Shop switches tabs without leaving the page", %{conn: conn} do
      product = product_fixture(%{title: "Crow with Stones"})
      {:ok, view, _html} = live(conn, ~p"/artists/#{product.artist_id}")

      view |> element(".artist-tab", "Shop") |> render_click()

      assert_patch(view, ~p"/artists/#{product.artist_id}/store")
      assert has_element?(view, ~s|.artist-tab[aria-current="page"]|, "Shop")
      assert has_element?(view, ".artist-top.compact")
      assert render(view) =~ "Crow with Stones"
    end

    test "the Shop tab's search filters the works", %{conn: conn} do
      product = product_fixture(%{title: "Crow with Stones"})
      {:ok, view, html} = live(conn, ~p"/artists/#{product.artist_id}/store")
      assert html =~ "Crow with Stones"

      view |> form("#filter-form", %{"search" => "otter"}) |> render_change()

      assert_patch(view, ~p"/artists/#{product.artist_id}/store?search=otter")
      refute render(view) =~ "Crow with Stones"
    end

    test "the Contact tab asks a logged-out visitor to log in", %{conn: conn} do
      artist = artist_fixture()
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/contact")

      assert has_element?(view, ~s|.artist-tab[aria-current="page"]|, "Contact")
      assert has_element?(view, ~s|a[href="/users/log-in"]|, "Log in to message")
    end

    test "Send message on the Contact tab opens a conversation", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      artist = artist_fixture()
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/contact")

      assert {:error, {:live_redirect, %{to: "/messages/" <> _id}}} =
               view |> element("button", "Send message") |> render_click()
    end
  end

  describe "Shop tab" do
    test "collection chips: only collections with works, each with its count", %{conn: conn} do
      artist = artist_fixture()
      oils = collection_fixture(artist, "Oils", 2)
      _empty = collection_fixture(artist, "Empty", 3)
      product_fixture(%{artist_id: artist.id, collection_id: oils.id})
      product_fixture(%{artist_id: artist.id, collection_id: oils.id})
      product_fixture(%{artist_id: artist.id})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store")

      assert has_element?(view, ~s|.filter-chip[aria-pressed="true"]|, "All works")
      assert has_element?(view, ".filter-chip", ~r/All works\s*\(3\)/)
      assert has_element?(view, ".filter-chip", ~r/Oils\s*\(2\)/)
      refute has_element?(view, ".filter-chip", "Empty")
      refute has_element?(view, ".filter-chip", "Uncategorized")
    end

    test "a chip's count leaves out works whose category was deleted, as the list does",
         %{conn: conn} do
      artist = artist_fixture()
      oils = collection_fixture(artist, "Oils", 2)
      product_fixture(%{artist_id: artist.id, collection_id: oils.id, title: "Kept"})
      lost = product_fixture(%{artist_id: artist.id, collection_id: oils.id, title: "Lost"})

      # What an admin's hard delete of the category does to its works.
      lost |> Ecto.Changeset.change(category_id: nil) |> ArtsyNeighbor.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store?collection_id=#{oils.id}")

      assert has_element?(view, ".filter-chip", ~r/Oils\s*\(1\)/)
      assert view |> render() |> titles_in_order() == ["Kept"]
    end

    test "a chip shows only that collection and keeps the search", %{conn: conn} do
      artist = artist_fixture()
      oils = collection_fixture(artist, "Oils", 2)
      product_fixture(%{artist_id: artist.id, collection_id: oils.id, title: "Crow in Oil"})
      product_fixture(%{artist_id: artist.id, collection_id: oils.id, title: "Otter in Oil"})
      product_fixture(%{artist_id: artist.id, title: "Crow in Ink"})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store?search=crow")
      view |> element(".filter-chip", "Oils") |> render_click()

      assert_patch(view, ~p"/artists/#{artist}/store?collection_id=#{oils.id}&search=crow")
      assert has_element?(view, ~s|.filter-chip[aria-pressed="true"]|, "Oils")
      assert has_element?(view, ".artwork-card", "Crow in Oil")
      refute has_element?(view, ".artwork-card", "Otter in Oil")
      refute has_element?(view, ".artwork-card", "Crow in Ink")
    end

    test "the category dropdown lists the artist's categories, only when there are two or more",
         %{conn: conn} do
      artist = artist_fixture()
      first = product_fixture(%{artist_id: artist.id})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store")
      refute has_element?(view, ~s|select[name="category_id"]|)

      _second = product_fixture(%{artist_id: artist.id, category_id: first.category_id})
      _other = product_fixture(%{artist_id: artist.id})
      first_category = ArtsyNeighbor.Repo.preload(first, :category).category

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store")

      assert has_element?(
               view,
               ~s|select[name="category_id"] option|,
               "#{first_category.name} (2)"
             )
    end

    test "newest works come first unless another order is chosen", %{conn: conn} do
      artist = artist_fixture()
      product_fixture(%{artist_id: artist.id, title: "Older and Cheap", price: "10"})
      product_fixture(%{artist_id: artist.id, title: "Newer and Dear", price: "500"})

      {:ok, _view, html} = live(conn, ~p"/artists/#{artist}/store")
      assert titles_in_order(html) == ["Newer and Dear", "Older and Cheap"]

      {:ok, _view, html} = live(conn, ~p"/artists/#{artist}/store?sort_by=price_asc")
      assert titles_in_order(html) == ["Older and Cheap", "Newer and Dear"]

      # An order that isn't offered is ignored rather than crashing.
      {:ok, _view, html} = live(conn, ~p"/artists/#{artist}/store?sort_by=collection")
      assert titles_in_order(html) == ["Newer and Dear", "Older and Cheap"]
    end

    test "shows 12 works, and 12 more with each Show more works", %{conn: conn} do
      artist = artist_fixture()
      category = ArtsyNeighbor.CategoriesFixtures.category_fixture()

      for number <- 1..14 do
        product_fixture(%{
          artist_id: artist.id,
          category_id: category.id,
          title: "Work #{number}"
        })
      end

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store")
      assert view |> render() |> titles_in_order() |> length() == 12
      assert has_element?(view, ".shop-show-more", "Showing 12 of 14 works")

      view |> element("button", "Show more works") |> render_click()

      assert view |> render() |> titles_in_order() |> length() == 14
      refute has_element?(view, ".shop-show-more")
    end

    test "shows the artist's announcement when it's turned on", %{conn: conn} do
      artist =
        artist_fixture()
        |> Ecto.Changeset.change(
          announcement: "Studio closed next week.",
          announcement_active: true
        )
        |> ArtsyNeighbor.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store")

      assert has_element?(view, ".shop-notice", "Studio closed next week.")
    end

    test "an artist with no works gets a short note, not filters", %{conn: conn} do
      artist = artist_fixture()
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store")

      assert has_element?(view, ".artist-no-works", "has no works for sale right now")
      refute has_element?(view, "#filter-form")
    end
  end

  # The titles of the artwork cards on a rendered page, top to bottom.
  defp titles_in_order(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".artwork-card-title")
    |> Enum.map(fn title -> title |> LazyHTML.text() |> String.trim() end)
  end

  describe "header" do
    test "shows only the postal district, never the full postal code", %{conn: conn} do
      artist = artist_fixture(%{area_code: "v8v 4p9"})
      {:ok, view, html} = live(conn, ~p"/artists/#{artist}")

      assert has_element?(view, ".artist-area", "V8V · Victoria")
      refute html =~ "4P9"
      refute html =~ "4p9"
    end

    test "each line of the bio is its own paragraph", %{conn: conn} do
      bio =
        "I have painted in Victoria for over thirty years.\n\n" <>
          "I grew up on a farm in the Okanagan.\nNow I paint full time in Fernwood."

      artist = artist_fixture(%{bio: bio})
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      assert has_element?(view, ".artist-bio-text p", "over thirty years.")
      assert has_element?(view, ".artist-bio-text p", "farm in the Okanagan.")
      assert has_element?(view, ".artist-bio-text p", "full time in Fernwood.")
    end

    test "Show full bio opens the whole bio, Show less shortens it again", %{conn: conn} do
      artist = artist_fixture()
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")
      assert has_element?(view, ".artist-bio-text.clamped")

      view |> element(".artist-bio button", "Show full bio") |> render_click()
      refute has_element?(view, ".artist-bio-text.clamped")
      assert has_element?(view, ~s|.artist-bio button[aria-expanded="true"]|, "Show less")

      view |> element(".artist-bio button", "Show less") |> render_click()
      assert has_element?(view, ".artist-bio-text.clamped")
    end

    test "the arrows go through the photos and wrap around", %{conn: conn} do
      artist = artist_fixture()
      add_artist_photos(artist, 3)
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      assert photo_shown?(view, "/uploads/photo-1.jpg")
      refute photo_shown?(view, "/uploads/photo-2.jpg")

      view |> element(".carousel-arrow.next") |> render_click()
      assert photo_shown?(view, "/uploads/photo-2.jpg")
      refute photo_shown?(view, "/uploads/photo-1.jpg")

      view |> element(".carousel-arrow.prev") |> render_click()
      view |> element(".carousel-arrow.prev") |> render_click()
      assert photo_shown?(view, "/uploads/photo-3.jpg")
    end

    test "the compact header keeps the current photo, without arrows", %{conn: conn} do
      artist = artist_fixture()
      add_artist_photos(artist, 2)
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      view |> element(".carousel-arrow.next") |> render_click()
      view |> element(".artist-tab", "Shop") |> render_click()

      assert photo_shown?(view, "/uploads/photo-2.jpg")
      refute has_element?(view, ".carousel-arrow")
    end

    test "an artist with no photos gets an empty frame and no arrows", %{conn: conn} do
      artist = artist_fixture()
      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      assert has_element?(view, ".artist-photo")
      refute has_element?(view, ".artist-photo img")
      refute has_element?(view, ".carousel-arrow")
    end
  end

  # Gives the artist `count` photos, /uploads/photo-1.jpg and so on.
  defp add_artist_photos(artist, count) do
    for position <- 1..count do
      %ArtsyNeighbor.Artists.ArtistImage{}
      |> ArtsyNeighbor.Artists.ArtistImage.changeset(%{
        path: "/uploads/photo-#{position}.jpg",
        position: position,
        artist_id: artist.id
      })
      |> ArtsyNeighbor.Repo.insert!()
    end
  end

  # True when the header shows the photo at `path` (and it isn't hidden).
  defp photo_shown?(view, path) do
    has_element?(view, ~s|.artist-photo img[src="#{path}"]:not([hidden])|)
  end

  describe "Works tab" do
    test "Featured works shows the 4 newest available works", %{conn: conn} do
      artist = artist_fixture()

      for number <- 1..5 do
        product_fixture(%{artist_id: artist.id, title: "Work #{number}"})
      end

      product_fixture(%{artist_id: artist.id, title: "Hidden work", status: :unavailable})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      # Work 1 is the oldest of the five, so it's the one left out.
      for number <- 2..5 do
        assert has_element?(view, ".artwork-card-title", "Work #{number}")
      end

      refute has_element?(view, ".artwork-card-title", "Work 1")
      refute has_element?(view, ".artwork-card-title", "Hidden work")
    end

    test "See all works opens the Shop tab", %{conn: conn} do
      artist = artist_fixture()
      product_fixture(%{artist_id: artist.id})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      view |> element(".artist-see-all a", "See all works") |> render_click()

      assert_patch(view, ~p"/artists/#{artist}/store")
    end

    test "an artist with no available works gets a short note", %{conn: conn} do
      artist = artist_fixture()

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      assert has_element?(view, ".artist-no-works", "has no works for sale right now")
      refute has_element?(view, ".section-heading", "Featured works")
    end

    test "each collection card opens the Shop tab with only that collection", %{conn: conn} do
      artist = artist_fixture()
      oils = collection_fixture(artist, "Oils", 2)
      product_fixture(%{artist_id: artist.id, collection_id: oils.id})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      assert has_element?(
               view,
               ~s|a.collection-card[href="/artists/#{artist.id}/store?collection_id=#{oils.id}"]|,
               "Oils"
             )
    end

    test "leaves out Uncategorized and collections with no available works", %{conn: conn} do
      artist = artist_fixture()
      [uncategorized] = ArtsyNeighbor.Products.list_collections_for_artist(artist.id)
      product_fixture(%{artist_id: artist.id, collection_id: uncategorized.id})

      _empty = collection_fixture(artist, "Empty", 2)
      sold_out = collection_fixture(artist, "Sold out", 3)

      product_fixture(%{
        artist_id: artist.id,
        collection_id: sold_out.id,
        status: :unavailable
      })

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      refute has_element?(view, ".collection-card")
      refute has_element?(view, ".section-heading", "Collections by")
    end
  end

  defp collection_fixture(artist, name, position) do
    {:ok, collection} =
      ArtsyNeighbor.Products.create_collection(%{
        name: name,
        position: position,
        artist_id: artist.id
      })

    collection
  end

  describe "Commissions tab" do
    test "shows the fixed text and a button to message the artist", %{conn: conn} do
      %{conn: conn} = register_and_log_in_user(%{conn: conn})
      artist = artist_fixture()
      {:ok, view, html} = live(conn, ~p"/artists/#{artist}/commissions")

      assert has_element?(view, ~s|.artist-tab[aria-current="page"]|, "Commissions")
      assert html =~ "#{artist.nickname} takes commissions"

      assert {:error, {:live_redirect, %{to: "/messages/" <> _id}}} =
               view |> element("button", "Send message") |> render_click()
    end
  end

  describe "artist not found" do
    test "an unknown artist goes back to the artists list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/artists", flash: flash}}} =
               live(conn, ~p"/artists/0")

      assert flash["error"] == "Artist not found."
    end

    test "an inactive artist is not shown on any tab", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive})

      for path <- [
            ~p"/artists/#{artist}",
            ~p"/artists/#{artist}/store",
            ~p"/artists/#{artist}/commissions",
            ~p"/artists/#{artist}/contact"
          ] do
        assert {:error, {:live_redirect, %{to: "/artists"}}} = live(conn, path)
      end
    end
  end

  describe "owner preview" do
    test "the owner sees their own inactive profile with ?preview=1", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive})
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))

      {:ok, view, html} = live(conn, ~p"/artists/#{artist}?preview=1")

      assert html =~ artist.nickname
      assert html =~ "Preview — your profile is not yet visible to the public."

      # Switching tabs keeps the preview.
      view |> element(".artist-tab", "Shop") |> render_click()
      assert_patch(view, ~p"/artists/#{artist}/store?preview=1")
    end

    test "the owner's preview shows their works on the Works and Shop tabs", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive})
      oils = collection_fixture(artist, "Oils", 2)
      product_fixture(%{artist_id: artist.id, collection_id: oils.id, title: "Harbour"})
      product_fixture(%{artist_id: artist.id, title: "Hidden work", status: :unavailable})
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}?preview=1")

      assert has_element?(view, ".artwork-card-title", "Harbour")
      assert has_element?(view, ".collection-card", "Oils")
      refute has_element?(view, ".artwork-card-title", "Hidden work")

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}/store?preview=1")

      assert render(view) =~ "Harbour"
      refute render(view) =~ "Hidden work"
      assert has_element?(view, ".filter-chip", "Oils")
    end

    test "someone else can't preview an inactive profile", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive})
      %{conn: conn} = register_and_log_in_user(%{conn: conn})

      assert {:error, {:live_redirect, %{to: "/artists"}}} =
               live(conn, ~p"/artists/#{artist}?preview=1")
    end

    test "the owner without ?preview=1 is not shown the inactive profile", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive})
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))

      assert {:error, {:live_redirect, %{to: "/artists"}}} = live(conn, ~p"/artists/#{artist}")
    end
  end
end
