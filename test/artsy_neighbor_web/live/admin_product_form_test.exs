defmodule ArtsyNeighborWeb.AdminProductFormTest do
  @moduledoc """
  Photo uploads on the admin product form. Photos are processed in the
  background (`ArtsyNeighborWeb.PhotoUploads`); a new product made by
  an admin is published once it has a photo.
  """
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.CategoriesFixtures
  import ArtsyNeighborWeb.PhotoUploadHelpers

  alias ArtsyNeighbor.Accounts.Admin
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Repo
  alias ArtsyNeighbor.Storage.Local

  @wait 10_000

  setup %{conn: conn} do
    admin = user_fixture()
    Repo.insert!(%Admin{user_id: admin.id})
    %{conn: log_in_user(conn, admin), artist: artist_fixture(), category: category_fixture()}
  end

  defp product_params(artist, category) do
    %{
      title: "Kelp forest",
      descr: "A linocut of a kelp forest",
      details: "Printed on washi paper",
      price: "90",
      artist_id: artist.id,
      category_id: category.id
    }
  end

  defp only_product_of(artist) do
    product = Repo.get_by!(Product, artist_id: artist.id)

    on_exit(fn ->
      File.rm_rf(Local.path_for("products/#{product.id}", :public))
      File.rm_rf(Local.path_for("products/#{product.id}", :private))
    end)

    product
  end

  test "a new product with a photo is stored and published",
       %{conn: conn, artist: artist, category: category} do
    {:ok, view, _html} = live(conn, ~p"/admin/products/new")
    pick_photos(view, "#product-form", :images, [good_photo()])

    view |> form("#product-form", product: product_params(artist, category)) |> render_submit()

    flash = assert_redirect(view, ~p"/admin/products", @wait)
    assert flash["info"] == "Product created successfully."

    product = only_product_of(artist)
    assert Products.get_product!(product.id).status == :available

    assert [%{path: "products/" <> _}] =
             Products.get_product_with_associations!(product.id).product_images
  end

  test "a refused photo keeps the page open on the new product's edit address, unpublished",
       %{conn: conn, artist: artist, category: category} do
    {:ok, view, _html} = live(conn, ~p"/admin/products/new")
    pick_photos(view, "#product-form", :images, [small_photo()])

    view |> form("#product-form", product: product_params(artist, category)) |> render_submit()

    product = only_product_of(artist)
    assert_patch(view, ~p"/admin/products/#{product.id}/edit", @wait)
    assert has_element?(view, "#photo-problem", "small.jpg was NOT saved")
    assert Products.get_product!(product.id).status == :draft
  end

  test "after a refused photo, removing it and saving again still publishes the new product",
       %{conn: conn, artist: artist, category: category} do
    {:ok, view, _html} = live(conn, ~p"/admin/products/new")
    pick_photos(view, "#product-form", :images, [good_photo(), small_photo()])

    view |> form("#product-form", product: product_params(artist, category)) |> render_submit()

    product = only_product_of(artist)
    assert_patch(view, ~p"/admin/products/#{product.id}/edit", @wait)
    assert Products.get_product!(product.id).status == :draft

    view |> element("button[aria-label='Remove small.jpg']") |> render_click()
    view |> form("#product-form") |> render_submit()

    flash = assert_redirect(view, ~p"/admin/products", @wait)
    assert flash["info"] == "Product created successfully."
    assert Products.get_product!(product.id).status == :available
  end

  test "a stored photo can be removed", %{conn: conn, artist: artist, category: category} do
    {:ok, product} =
      ArtsyNeighbor.Admin.AdminProducts.create_product(
        admin_scope_fixture(),
        product_params(artist, category)
      )

    {:ok, image} =
      Products.create_product_image(admin_scope_fixture(), product, %{
        path: "/photo.jpg",
        position: 1
      })

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product}/edit")
    render_click(view, "delete_image", %{"imageid" => to_string(image.id)})

    assert Products.get_product_with_associations!(product.id).product_images == []
  end

  # Choosing the artist (audit S-3 review). Works without photos, so
  # saving redirects at once.
  # Deleted in another admin tab, after this list was loaded.
  describe "the product list, for a product that is gone" do
    test "Archive, Restore and Delete say so instead of crashing", %{conn: conn} do
      product = ArtsyNeighbor.ProductsFixtures.product_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/products")
      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), product)

      for event <- ["archive", "restore", "delete"], id <- [to_string(product.id), "abc"] do
        html = render_click(view, event, %{"id" => id})
        assert html =~ "That product doesn&#39;t exist any more."
      end
    end
  end

  describe "the artist of a work" do
    test "a work whose artist isn't active can still be edited",
         %{conn: conn, category: category} do
      inactive = artist_fixture(%{status: :inactive})

      product =
        ArtsyNeighbor.ProductsFixtures.product_fixture(%{
          artist_id: inactive.id,
          category_id: category.id
        })

      {:ok, view, html} = live(conn, ~p"/admin/products/#{product}/edit")
      assert html =~ "#{inactive.nickname} (inactive)"

      view |> form("#product-form", product: %{price: "77"}) |> render_submit()

      assert_redirect(view, ~p"/admin/products", @wait)
      updated = Products.get_product!(product.id)
      assert Decimal.equal?(updated.price, "77")
      assert updated.artist_id == inactive.id
    end

    test "a work can be moved to an artist who has no collections",
         %{conn: conn, artist: artist, category: category} do
      {:ok, prints} =
        Products.create_collection(artist_scope_fixture(artist), %{name: "Prints"})

      product =
        ArtsyNeighbor.ProductsFixtures.product_fixture(%{
          artist_id: artist.id,
          category_id: category.id,
          collection_id: prints.id
        })

      new_artist = artist_fixture()

      for collection <- Products.list_collections_for_artist(new_artist.id) do
        Repo.delete!(collection)
      end

      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product}/edit")

      # Picking the artist empties and disables the collection field, so
      # the form then sends no collection at all.
      view
      |> element("#product-form select[name='product[artist_id]']")
      |> render_change(%{"product" => %{"artist_id" => to_string(new_artist.id)}})

      view |> form("#product-form") |> render_submit()

      assert_redirect(view, ~p"/admin/products", @wait)
      moved = Products.get_product!(product.id)
      assert moved.artist_id == new_artist.id
      assert moved.collection_id == nil
    end
  end
end
