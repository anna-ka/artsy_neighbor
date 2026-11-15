defmodule ArtsyNeighborWeb.ImageDisplayTest do
  @moduledoc """
  Photos stored by `Images.process_upload/3` are saved under a key (a
  folder name like "products/12/<uuid>"), not a web address. These
  tests check that the pages show such photos through `Images.url/2`,
  in the size chosen for each place (see step 3 of
  docs/plans/2026-10-28-image-storage-and-resizing.md), and that
  old-style paths starting with "/" still show unchanged.

  No real files are needed: the tests only look at the addresses in
  the page.
  """
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Products
  alias ArtsyNeighborWeb.OrderFormatters

  # A product with one photo stored the new way; returns the product
  # and the photo's key.
  defp product_with_key_photo do
    product = product_fixture()
    key = "products/#{product.id}/#{Ecto.UUID.generate()}"

    {:ok, _image} =
      Products.create_product_image(%{path: key, position: 1, product_id: product.id})

    {product, key}
  end

  describe "product page" do
    test "shows the medium size, the thumb in the row of small photos, and the large size in the large view",
         %{conn: conn} do
      {product, key} = product_with_key_photo()

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ~s(img.work-enlargeable[src$="#{key}/medium.webp"]))

      # Large view: the medium photo (already downloaded) underneath, so
      # it shows at once; the large one on top, fetched only when opened.
      assert has_element?(view, ~s(#work-viewer img[src$="#{key}/medium.webp"]))

      assert has_element?(
               view,
               ~s(#work-viewer img.work-viewer-large[src$="#{key}/large.webp"][loading="lazy"])
             )

      # The bare key is never used as an address on its own.
      refute has_element?(view, ~s(img[src="#{key}"]))
    end

    test "shows an old-style photo path unchanged", %{conn: conn} do
      product = product_fixture()

      {:ok, _image} =
        Products.create_product_image(%{
          path: "/images/seed/old-photo.jpg",
          position: 1,
          product_id: product.id
        })

      {:ok, view, _html} = live(conn, ~p"/products/#{product}")

      assert has_element?(view, ~s(img.work-enlargeable[src="/images/seed/old-photo.jpg"]))
      assert has_element?(view, ~s(#work-viewer img[src="/images/seed/old-photo.jpg"]))
    end
  end

  describe "cards and lists" do
    test "the products listing shows the thumb size", %{conn: conn} do
      {_product, key} = product_with_key_photo()

      {:ok, view, _html} = live(conn, ~p"/products")

      assert has_element?(view, ~s(img[src$="#{key}/thumb.webp"]))
    end

    test "the artist page shows the artist's photo in the thumb size", %{conn: conn} do
      artist = artist_fixture()
      key = "artists/#{artist.id}/#{Ecto.UUID.generate()}"
      artist_image_fixture(artist, %{path: key})

      {:ok, view, _html} = live(conn, ~p"/artists/#{artist}")

      assert has_element?(view, ~s(.artist-photo img[src$="#{key}/thumb.webp"]))
    end
  end

  describe "category pictures" do
    test "a category without a picture stores nil and its page shows the placeholder",
         %{conn: conn} do
      category = ArtsyNeighbor.CategoriesFixtures.category_fixture(%{main_img: nil})

      # Placeholders are shown, never stored.
      assert category.main_img == nil

      {:ok, view, _html} = live(conn, ~p"/categories/#{category}")

      assert has_element?(view, ~s(img[src="#{ArtsyNeighbor.Images.placeholder(:category)}"]))
    end
  end

  describe "OrderFormatters.thumb_path/1" do
    test "gives the thumb address of the item's cover photo (lowest position), or nil" do
      {product, key} = product_with_key_photo()

      # A second photo with a higher position, inserted after the cover.
      {:ok, _image} =
        Products.create_product_image(%{
          path: "/images/not-the-cover.jpg",
          position: 2,
          product_id: product.id
        })

      product = ArtsyNeighbor.Repo.preload(product, :product_images)
      # Load order mustn't matter: put the second photo first.
      product = %{product | product_images: Enum.reverse(product.product_images)}

      assert OrderFormatters.thumb_path(%{product: product}) =~ ~r{#{key}/thumb\.webp$}
      assert OrderFormatters.thumb_path(%{product: nil}) == nil
    end
  end

  describe "the web code as a whole" do
    # A stored key put straight into src= gives a broken image, and only
    # a few pages have their own test above. So this reads the source
    # files instead: every line in lib/artsy_neighbor_web that uses a
    # photo's `.path` must pass it through `Images.url(`. (Most pages
    # use `Images.first_url/3`, which doesn't mention `.path` at all.)
    # The one exception is the uploaded temporary file (`file.path`)
    # handed to `Images.process_upload/3`.
    test "never shows a photo's stored path without Images.url" do
      files = Path.wildcard("lib/artsy_neighbor_web/**/*.{ex,heex}")
      assert files != [], "no source files found: is the test run from the project root?"

      offending_lines =
        for file <- files,
            {line, line_number} <- Enum.with_index(String.split(File.read!(file), "\n"), 1),
            uses_raw_path?(line) do
          "#{file}:#{line_number}: #{String.trim(line)}"
        end

      assert offending_lines == [],
             "Use Images.url(path, size) or Images.first_url(images, size, placeholder) here:\n" <>
               Enum.join(offending_lines, "\n")
    end
  end

  defp uses_raw_path?(line) do
    Regex.match?(~r/\w\.path\b/, line) and
      not String.contains?(line, "Images.url(") and
      not String.contains?(line, "file.path")
  end
end
