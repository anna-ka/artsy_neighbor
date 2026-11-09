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
      Products.create_product(product_params(artist, category))

    {:ok, image} =
      Products.create_product_image(%{path: "/photo.jpg", position: 1, product_id: product.id})

    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product}/edit")
    render_click(view, "delete_image", %{"imageid" => to_string(image.id)})

    assert Products.get_product_with_associations!(product.id).product_images == []
  end
end
