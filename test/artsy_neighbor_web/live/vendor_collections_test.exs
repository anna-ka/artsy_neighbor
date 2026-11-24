defmodule ArtsyNeighborWeb.VendorCollectionsTest do
  @moduledoc """
  A vendor's collections: the collection form (`VendorLive.CollectionForm`)
  and the dashboard's collection links (`VendorLive.Dashboard`). Includes
  the hand-made requests of audit S-4, which must be refused.
  """
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.ProductsFixtures

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Products

  setup %{conn: conn} do
    artist = artist_fixture()
    conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
    default = Products.get_collection!(Products.default_collection_id(artist.id))
    %{conn: conn, artist: artist, default: default}
  end

  describe "the collection form" do
    test "a new collection belongs to the logged-in artist", %{conn: conn, artist: artist} do
      other_artist = artist_fixture()
      {:ok, view, _html} = live(conn, ~p"/vendor/collections/new")

      # A hand-made request (render_submit/3 sends the params as given).
      assert {:error, {:live_redirect, %{to: "/vendor"}}} =
               render_submit(view, "save", %{
                 "product_collection" => %{
                   "name" => "Prints",
                   "artist_id" => to_string(other_artist.id)
                 }
               })

      names =
        artist.id
        |> Products.list_collections_for_artist()
        |> Enum.map(fn collection -> collection.name end)

      assert "Prints" in names
      assert [_only_default] = Products.list_collections_for_artist(other_artist.id)
    end

    test "editing: an artist_id in the params doesn't move the collection", %{
      conn: conn,
      artist: artist
    } do
      other_artist = artist_fixture()
      {:ok, collection} = Products.create_collection(artist.id, %{name: "Mine"})
      {:ok, view, _html} = live(conn, ~p"/vendor/collections/#{collection.id}/edit")

      render_submit(view, "save", %{
        "product_collection" => %{
          "name" => "Still mine",
          "artist_id" => to_string(other_artist.id)
        }
      })

      updated = Products.get_collection!(collection.id)
      assert updated.name == "Still mine"
      assert updated.artist_id == artist.id
    end

    test "another artist's collection can't be opened", %{conn: conn} do
      other_artist = artist_fixture()
      {:ok, theirs} = Products.create_collection(other_artist.id, %{name: "Theirs"})

      assert {:error, {:redirect, %{to: "/vendor", flash: flash}}} =
               live(conn, ~p"/vendor/collections/#{theirs.id}/edit")

      assert flash["error"] == "You are not authorized to edit this collection."
    end

    test "a collection that doesn't exist sends the artist back to the dashboard", %{conn: conn} do
      for id <- ["999999999", "abc"] do
        assert {:error, {:redirect, %{to: "/vendor", flash: flash}}} =
                 live(conn, "/vendor/collections/#{id}/edit")

        assert flash["error"] == "That collection doesn't exist any more."
      end
    end

    test "the default collection can be renamed, and stays the default", %{
      conn: conn,
      default: default
    } do
      {:ok, view, _html} = live(conn, ~p"/vendor/collections/#{default.id}/edit")

      view
      |> form("#collection-form", product_collection: %{name: "Odds and ends"})
      |> render_submit()

      renamed = Products.get_collection!(default.id)
      assert renamed.name == "Odds and ends"
      assert renamed.is_default
    end
  end

  describe "the dashboard's collection links" do
    test "the default collection has no Delete link, others do", %{
      conn: conn,
      artist: artist,
      default: default
    } do
      {:ok, other} = Products.create_collection(artist.id, %{name: "Prints"})
      {:ok, view, _html} = live(conn, ~p"/vendor")

      refute has_element?(view, "[phx-click=delete_collection][phx-value-id='#{default.id}']")
      assert has_element?(view, "[phx-click=delete_collection][phx-value-id='#{other.id}']")
    end

    test "a hand-made request to delete the default collection is refused", %{
      conn: conn,
      default: default
    } do
      {:ok, view, _html} = live(conn, ~p"/vendor")

      html = render_click(view, "delete_collection", %{"id" => to_string(default.id)})

      assert html =~ "This collection can&#39;t be deleted, but you can rename it."
      assert Products.get_collection!(default.id)
    end

    test "deleting a collection moves its works to the default one, by its current name", %{
      conn: conn,
      artist: artist,
      default: default
    } do
      {:ok, _} = Products.update_collection(default, %{name: "Odds and ends"})
      {:ok, prints} = Products.create_collection(artist.id, %{name: "Prints"})
      product = product_fixture(%{artist_id: artist.id, collection_id: prints.id})
      {:ok, view, _html} = live(conn, ~p"/vendor")

      html =
        view
        |> element("[phx-click=delete_collection][phx-value-id='#{prints.id}']")
        |> render_click()

      assert html =~ "Its products have been moved to &quot;Odds and ends&quot;."
      assert Products.get_product!(product.id).collection_id == default.id
    end

    test "a bad or unknown id to delete gets a message, not a crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/vendor")

      for id <- ["abc", "999999999", "99999999999999999999"] do
        html = render_click(view, "delete_collection", %{"id" => id})
        assert html =~ "That collection had already been deleted."
      end
    end

    test "the default collection stays last: no arrows, and nothing moves into its place", %{
      conn: conn,
      artist: artist,
      default: default
    } do
      {:ok, prints} = Products.create_collection(artist.id, %{name: "Prints"})
      {:ok, oils} = Products.create_collection(artist.id, %{name: "Oils"})
      {:ok, view, _html} = live(conn, ~p"/vendor")

      refute has_element?(
               view,
               "[phx-click=move_collection_up][phx-value-collectionid='#{default.id}']"
             )

      assert has_element?(
               view,
               "[phx-click=move_collection_down][phx-value-collectionid='#{prints.id}']"
             )

      # Oils is just above the default collection: no "down".
      refute has_element?(
               view,
               "[phx-click=move_collection_down][phx-value-collectionid='#{oils.id}']"
             )

      # The same as hand-made requests: nothing changes.
      render_click(view, "move_collection_up", %{"collectionid" => to_string(default.id)})
      render_click(view, "move_collection_down", %{"collectionid" => to_string(oils.id)})

      names =
        artist.id
        |> Products.list_collections_for_artist()
        |> Enum.map(fn collection -> collection.name end)

      assert names == ["Prints", "Oils", "Uncategorized"]
      assert Products.get_collection!(default.id).position == default.position
    end
  end
end
