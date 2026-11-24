defmodule ArtsyNeighborWeb.VendorProductFormTest do
  @moduledoc """
  The vendor product form's draft flow (image storage step 2a): Save
  draft / Preview / Publish for drafts, one Save button otherwise, and
  "Remove" on stored photos. See
  `docs/plans/2026-10-28-image-storage-and-resizing.md`.

  Most tests add photos as rows directly; the "uploading photos" tests
  (step 2b) upload real files, which are processed in the background
  (`ArtsyNeighborWeb.PhotoUploads`).
  """
  use ArtsyNeighborWeb.ConnCase

  import ArtsyNeighbor.AccountsFixtures, only: [admin_scope_fixture: 0, artist_scope_fixture: 1]

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.CategoriesFixtures
  import ArtsyNeighbor.ProductsFixtures
  import ArtsyNeighborWeb.PhotoUploadHelpers

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Storage.Local

  setup %{conn: conn} do
    artist = artist_fixture()
    conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
    %{conn: conn, artist: artist, category: category_fixture()}
  end

  defp new_product_params(category) do
    %{
      title: "Heron at dusk",
      descr: "A small watercolour of a heron",
      details: "Framed, ready to hang",
      price: "180",
      category_id: category.id
    }
  end

  # A draft made the way the form makes one, plus `photo_count` photos.
  defp draft_product(artist, category, photo_count) do
    {:ok, product} =
      Products.create_product(artist_scope_fixture(artist), new_product_params(category))

    for position <- Enum.to_list(1..photo_count//1) do
      {:ok, _} =
        Products.create_product_image(admin_scope_fixture(), product, %{
          path: "/photo-#{position}.jpg",
          position: position
        })
    end

    product
  end

  defp add_photo(product) do
    {:ok, image} =
      Products.create_product_image(admin_scope_fixture(), product, %{
        path: "/photo.jpg",
        position: 1
      })

    image
  end

  # Submits the product form by pressing the button with this
  # save_action value ("draft", "preview", "publish" or "save").
  defp press(view, save_action, params \\ %{}) do
    view
    |> form("#product-form", product: params)
    |> put_submitter("button[value=#{save_action}]")
    |> render_submit()
  end

  describe "a new product" do
    test "shows Save draft, Preview and Publish, with an explanation", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/vendor/products/new")

      assert has_element?(view, "button[value=draft]", "Save draft")
      assert has_element?(view, "button[value=preview]", "Preview")
      assert has_element?(view, "button[value=publish]", "Publish")
      assert html =~ "What do these buttons do?"
    end

    test "Save draft saves it without photos, as a draft, and opens its edit page",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      {:ok, _edit_view, html} =
        view
        |> press("draft", new_product_params(category))
        |> follow_redirect(conn)

      [product] = Products.get_products_by_artist_all_status(artist.id)
      assert product.status == :draft
      assert html =~ "Saved as a draft"
      assert html =~ "buyers can&#39;t see this work yet"
    end

    test "Publish without a photo keeps it as a draft and says why",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      {:ok, _edit_view, html} =
        view
        |> press("publish", new_product_params(category))
        |> follow_redirect(conn)

      [product] = Products.get_products_by_artist_all_status(artist.id)
      assert product.status == :draft
      assert html =~ "Add at least one photo to publish this work."
    end

    test "invalid fields are shown and nothing is saved", %{conn: conn, artist: artist} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      html = press(view, "draft", %{title: ""})

      assert html =~ "can&#39;t be blank"
      assert Products.get_products_by_artist_all_status(artist.id) == []
    end
  end

  # Audit S-3: a request made by hand (not by the page's own fields)
  # must not put a work on another artist's page. render_submit/3 with
  # an event name sends the params as given, like such a request would.
  describe "hand-made requests" do
    setup do
      other_artist = artist_fixture()

      {:ok, other_collection} =
        Products.create_collection(artist_scope_fixture(other_artist), %{
          name: "Someone else's oils"
        })

      %{other_artist: other_artist, other_collection: other_collection}
    end

    defp edit_params(product, category, extra) do
      Map.merge(
        %{
          "title" => product.title,
          "descr" => product.descr,
          "details" => product.details,
          "price" => "10",
          "category_id" => to_string(category.id)
        },
        extra
      )
    end

    test "an artist_id in the params doesn't move a work to another artist",
         %{conn: conn, artist: artist, other_artist: other_artist, category: category} do
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      render_submit(view, "save", %{
        "product" => edit_params(product, category, %{"artist_id" => to_string(other_artist.id)}),
        "save_action" => "save"
      })

      assert Products.get_product!(product.id).artist_id == artist.id
      assert Products.get_products_by_artist_all_status(other_artist.id) == []
    end

    test "editing: another artist's collection is refused", %{
      conn: conn,
      artist: artist,
      other_artist: other_artist,
      other_collection: other_collection,
      category: category
    } do
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      html =
        render_submit(view, "save", %{
          "product" =>
            edit_params(product, category, %{
              "title" => "Moved work",
              "collection_id" => to_string(other_collection.id)
            }),
          "save_action" => "save"
        })

      assert html =~ "Please choose one of this artist&#39;s own collections."
      unchanged = Products.get_product!(product.id)
      assert unchanged.title == product.title
      assert unchanged.collection_id == product.collection_id

      shown = Products.list_collections_for_artist(other_artist.id)
      assert Enum.all?(shown, fn collection -> collection.products == [] end)
    end

    test "a new work: another artist's collection is refused, and nothing is saved",
         %{conn: conn, artist: artist, other_collection: other_collection, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      params =
        category
        |> new_product_params()
        |> Map.put(:collection_id, other_collection.id)

      html = render_submit(view, "save", %{"product" => params, "save_action" => "draft"})

      assert html =~ "Please choose one of this artist&#39;s own collections."
      assert Products.get_products_by_artist_all_status(artist.id) == []
    end
  end

  describe "a draft" do
    test "Publish makes a draft with a photo available",
         %{conn: conn, artist: artist, category: category} do
      product = draft_product(artist, category, 1)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      assert {:error, {:live_redirect, %{to: "/vendor"}}} = press(view, "publish")
      assert Products.get_product!(product.id).status == :available
    end

    test "Preview saves and opens the owner's preview of the product page",
         %{conn: conn, artist: artist, category: category} do
      product = draft_product(artist, category, 1)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      {:ok, _preview_view, html} =
        view
        |> press("preview", %{title: "Heron at dawn"})
        |> follow_redirect(conn)

      assert html =~ "Heron at dawn"
      assert html =~ "Preview — buyers can&#39;t see this work yet."
      assert html =~ "Back to editing"
      assert Products.get_product!(product.id).status == :draft
    end
  end

  describe "publishing while the artist's own profile is hidden" do
    test "says buyers will see the work once the profile is public",
         %{conn: conn, artist: artist, category: category} do
      {:ok, _} = ArtsyNeighbor.Artists.deactivate_artist(artist)
      product = draft_product(artist, category, 1)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      {:ok, _dashboard, html} =
        view
        |> press("publish")
        |> follow_redirect(conn, ~p"/vendor")

      assert html =~ "Published but not visible to public yet."
      assert html =~ "Buyers will see it once your Artist profile is public"
      assert Products.get_product!(product.id).status == :available
    end
  end

  describe "a product that isn't a draft" do
    test "has one Save button, which keeps its status", %{conn: conn, artist: artist} do
      product = product_fixture(%{artist_id: artist.id})
      add_photo(product)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      refute has_element?(view, "button[value=publish]")
      assert has_element?(view, "button[value=save]", "Save")

      assert {:error, {:live_redirect, %{to: "/vendor"}}} =
               press(view, "save", %{title: "New title"})

      updated = Products.get_product!(product.id)
      assert updated.title == "New title"
      assert updated.status == :available
    end

    test "removing its last photo makes it a draft, and says so",
         %{conn: conn, artist: artist} do
      product = product_fixture(%{artist_id: artist.id})
      image = add_photo(product)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      html =
        view
        |> element("button[phx-click=delete_image][phx-value-imageid='#{image.id}']")
        |> render_click()

      assert html =~ "That was the last photo, so this work is now a draft"
      assert Products.get_product!(product.id).status == :draft
      # The form now offers Publish again.
      assert has_element?(view, "button[value=publish]")
    end
  end

  describe "removing a photo that is already gone" do
    test "says so instead of crashing", %{conn: conn, artist: artist} do
      product = product_fixture(%{artist_id: artist.id})
      image = add_photo(product)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      # Removed elsewhere (e.g. another browser tab) after the page opened.
      {:ok, _} = Products.delete_product_image(artist_scope_fixture(artist), image)

      html =
        view
        |> element("button[phx-click=delete_image][phx-value-imageid='#{image.id}']")
        |> render_click()

      assert html =~ "That photo had already been removed."
    end
  end

  describe "a work deleted while its page is open" do
    test "Remove on a photo goes back to the dashboard, instead of crashing",
         %{conn: conn, artist: artist} do
      product = product_fixture(%{artist_id: artist.id})
      image = add_photo(product)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")

      # By an admin, from /admin/products.
      {:ok, _} = Products.hard_delete_product(admin_scope_fixture(), product)

      result =
        view
        |> element("button[phx-click=delete_image][phx-value-imageid='#{image.id}']")
        |> render_click()

      assert {:error, {:live_redirect, %{to: "/vendor"}}} = result
      {:ok, _dashboard, html} = follow_redirect(result, conn)
      assert html =~ "This work doesn&#39;t exist any more."
    end
  end

  # Hand-made requests with ids that aren't the artist's, or aren't
  # numbers. Until 2026-11-23 several of these crashed the page.
  describe "bad or someone else's ids" do
    setup %{artist: artist} do
      default_id = Products.default_collection_id(artist.id)
      first = product_fixture(%{artist_id: artist.id, collection_id: default_id, position: 1})
      second = product_fixture(%{artist_id: artist.id, collection_id: default_id, position: 2})
      theirs = product_fixture()
      %{default_id: default_id, first: first, second: second, theirs: theirs}
    end

    test "moving a work does nothing, and doesn't crash",
         %{conn: conn, default_id: default_id, first: first, second: second, theirs: theirs} do
      {:ok, view, _html} = live(conn, ~p"/vendor")
      own_collection = to_string(default_id)
      their_collection = to_string(theirs.collection_id)

      for {product_id, collection_id} <- [
            {"abc", own_collection},
            {to_string(second.id), "abc"},
            {"99999999999999999999", own_collection},
            {to_string(theirs.id), own_collection},
            {to_string(theirs.id), their_collection}
          ],
          event <- ["move_product_up", "move_product_down"] do
        render_click(view, event, %{"productid" => product_id, "collectionid" => collection_id})
      end

      assert Products.get_product!(first.id).position == 1
      assert Products.get_product!(second.id).position == 2
      assert Products.get_product!(theirs.id).position == theirs.position
    end

    test "archiving someone else's work, or a bad id, is refused with a message",
         %{conn: conn, theirs: theirs} do
      {:ok, view, _html} = live(conn, ~p"/vendor")

      for id <- ["abc", "99999999999999999999", to_string(theirs.id)] do
        html = render_click(view, "archive_product", %{"id" => id})
        assert html =~ "That work isn&#39;t one of yours."
      end

      assert Products.get_product!(theirs.id).status == :available
    end

    test "someone else's work, or a made-up address, can't be opened for editing",
         %{conn: conn, theirs: theirs} do
      for id <- [to_string(theirs.id), "999999999", "abc"] do
        assert {:error, {:redirect, %{to: "/vendor", flash: flash}}} =
                 live(conn, "/vendor/products/#{id}/edit")

        assert flash["error"] == "That work isn't one of yours, or doesn't exist any more."
      end
    end

    test "the photo buttons ignore an id that isn't one of the work's photos",
         %{conn: conn, first: first} do
      photo = add_photo(first)
      someone_elses_photo = product_image_fixture()
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{first}/edit")

      for id <- ["abc", "99999999999999999999", to_string(someone_elses_photo.id)],
          event <- ["delete_image", "move_image_up", "move_image_down"] do
        render_click(view, event, %{"imageid" => id})
      end

      assert ArtsyNeighbor.Repo.get(ArtsyNeighbor.Products.ProductImage, photo.id)
      assert ArtsyNeighbor.Repo.get(ArtsyNeighbor.Products.ProductImage, someone_elses_photo.id)
    end
  end

  # Removed by an admin while the artist's page was open: the pages
  # still show their works, but every change is refused, with a message
  # that says why (Products, "Who is acting").
  describe "an artist whose profile was removed" do
    test "can't save changes to a work",
         %{conn: conn, artist: artist, category: category} do
      product = product_fixture(%{artist_id: artist.id, category_id: category.id})
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")
      {:ok, _removed} = ArtsyNeighbor.Artists.soft_delete_artist(artist)

      html =
        render_submit(view, "save", %{
          "product" => %{
            "title" => "A new title",
            "descr" => product.descr,
            "details" => product.details,
            "price" => "10",
            "category_id" => to_string(category.id)
          },
          "save_action" => "save"
        })

      assert html =~ "Your artist profile has been removed"
      assert Products.get_product!(product.id).title == product.title
    end

    test "can't move works or collections on the dashboard", %{conn: conn, artist: artist} do
      default_id = Products.default_collection_id(artist.id)
      first = product_fixture(%{artist_id: artist.id, collection_id: default_id, position: 1})
      second = product_fixture(%{artist_id: artist.id, collection_id: default_id, position: 2})
      {:ok, view, _html} = live(conn, ~p"/vendor")
      {:ok, _removed} = ArtsyNeighbor.Artists.soft_delete_artist(artist)

      html =
        view
        |> element("[phx-click=move_product_down][phx-value-productid='#{first.id}']")
        |> render_click()

      assert html =~ "Your artist profile has been removed"
      assert Products.get_product!(first.id).position == 1
      assert Products.get_product!(second.id).position == 2
    end
  end

  describe "the dashboard's View link" do
    test "opens the artist's own preview, so a draft opens too",
         %{conn: conn, artist: artist, category: category} do
      # Made without a collection: it lands in "Uncategorized", so the
      # dashboard (which lists products by collection) shows it.
      product = draft_product(artist, category, 1)
      {:ok, view, _html} = live(conn, ~p"/vendor")

      assert has_element?(view, "a[href^='/products/#{product.id}?preview=1']", "View")
    end
  end

  describe "the product page's owner preview" do
    test "isn't shown to anyone else", %{artist: artist, category: category} do
      product = draft_product(artist, category, 1)

      other_artist = artist_fixture()
      other_conn = log_in_user(build_conn(), Accounts.get_user!(other_artist.user_id))

      assert {:error, {:live_redirect, %{to: "/products"}}} =
               live(other_conn, ~p"/products/#{product}?preview=1")

      assert {:error, {:live_redirect, %{to: "/products"}}} =
               live(build_conn(), ~p"/products/#{product}?preview=1")
    end

    test "the owner without ?preview=1 gets the public behaviour",
         %{conn: conn, artist: artist, category: category} do
      product = draft_product(artist, category, 1)

      assert {:error, {:live_redirect, %{to: "/products"}}} =
               live(conn, ~p"/products/#{product}")
    end

    test "the owner's Request to buy is disabled in the preview",
         %{conn: conn, artist: artist, category: category} do
      product = draft_product(artist, category, 1)
      {:ok, view, _html} = live(conn, ~p"/products/#{product}?preview=1")

      assert has_element?(view, "button[phx-click=request_to_buy][disabled]")
    end
  end

  describe "the dashboard's Activate profile" do
    test "is refused without a profile photo, saying why", %{conn: conn, artist: artist} do
      {:ok, _} = ArtsyNeighbor.Artists.deactivate_artist(artist)
      {:ok, view, _html} = live(conn, ~p"/vendor")

      view |> element("button[phx-click=confirm_status_toggle]") |> render_click()
      html = view |> element("button[phx-click=toggle_status]") |> render_click()

      assert html =~ "Add a profile photo before making your profile public."
      assert ArtsyNeighbor.Artists.get_artist!(artist.id).status == :inactive
    end

    test "works once the profile has a photo", %{conn: conn, artist: artist} do
      {:ok, _} = ArtsyNeighbor.Artists.deactivate_artist(artist)
      artist_image_fixture(artist)
      {:ok, view, _html} = live(conn, ~p"/vendor")

      view |> element("button[phx-click=confirm_status_toggle]") |> render_click()
      html = view |> element("button[phx-click=toggle_status]") |> render_click()

      assert html =~ "Your profile is now visible to the public."
      assert ArtsyNeighbor.Artists.get_artist!(artist.id).status == :active
    end
  end

  describe "uploading photos" do
    # Processing a photo takes about a second; leave plenty of time.
    @wait 10_000

    defp images_of(product_id) do
      Products.get_product_with_associations!(product_id).product_images
    end

    # The one product of `artist` (made by the form in the test).
    defp only_product_of(artist) do
      product = ArtsyNeighbor.Repo.get_by!(ArtsyNeighbor.Products.Product, artist_id: artist.id)
      remove_stored_files_on_exit(product)
      product
    end

    # The stored photos live in a temporary test folder; remove this
    # product's folder after the test.
    defp remove_stored_files_on_exit(product) do
      on_exit(fn ->
        File.rm_rf(Local.path_for("products/#{product.id}", :public))
        File.rm_rf(Local.path_for("products/#{product.id}", :private))
      end)
    end

    test "a new draft with a photo: the photo is processed and stored in the product's folder",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")
      pick_photos(view, "#product-form", :images, [good_photo()])

      press(view, "draft", new_product_params(category))
      # The page says it's busy while the photo is processed.
      assert has_element?(view, "#saving-photos", "Saving your photos")

      product = only_product_of(artist)
      flash = assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
      assert flash["info"] =~ "Saved as a draft"
      # Only one photo, so nothing to put in order.
      refute flash["info"] =~ "check their order"

      [image] = images_of(product.id)
      assert String.starts_with?(image.path, "products/#{product.id}/")
      assert File.exists?(Local.path_for(image.path <> "/thumb.webp", :public))
      assert File.exists?(Local.path_for(image.path <> "/source.webp", :private))
    end

    test "after adding a second photo, the artist is asked to check the order, on the edit page",
         %{conn: conn, artist: artist, category: category} do
      product = draft_product(artist, category, 1)
      remove_stored_files_on_exit(product)
      {:ok, view, _html} = live(conn, ~p"/vendor/products/#{product}/edit")
      pick_photos(view, "#product-form", :images, [good_photo()])

      press(view, "publish")

      flash = assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
      assert flash["info"] =~ "Published!"
      assert flash["info"] =~ "check their order"
      assert Products.get_product!(product.id).status == :available

      # The new photo comes after the existing one.
      assert [%{position: 1}, %{position: 2, path: "products/" <> _}] = images_of(product.id)
    end

    test "a refused photo stays in the upload box with its message, loudly; the text is saved",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")
      pick_photos(view, "#product-form", :images, [small_photo()])

      press(view, "publish", new_product_params(category))

      # The page stays, but switches to the new product's edit address,
      # so saving again doesn't make a second product.
      product = only_product_of(artist)
      assert_patch(view, ~p"/vendor/products/#{product.id}/edit", @wait)

      html = render(view)
      assert has_element?(view, "[id^=photo-entry-]", "This photo is too small to look good.")
      assert has_element?(view, "#photo-problem", "small.jpg was NOT saved")
      # The flash gives the full reason too, not just a pointer to the
      # red box (it's the same text, so it appears twice on the page).
      assert html =~
               "Your work is saved. Your photo small.jpg was NOT saved: " <>
                 "This photo is too small to look good."

      assert has_element?(view, "#photo-problem", "This photo is too small to look good.")

      # Nothing stored, and not published: it has no photo.
      assert images_of(product.id) == []
      assert Products.get_product!(product.id).status == :draft
      assert Products.get_product!(product.id).title == "Heron at dusk"
    end

    test "with one good and one refused photo, the good one is stored; removing the bad one lets the save finish",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")
      pick_photos(view, "#product-form", :images, [good_photo(), small_photo()])

      press(view, "draft", new_product_params(category))
      product = only_product_of(artist)
      assert_patch(view, ~p"/vendor/products/#{product.id}/edit", @wait)

      assert [_stored] = images_of(product.id)
      # Only the refused photo is left in the upload box.
      html = render(view)
      refute html =~ "cat.jpg"
      assert html =~ "small.jpg"

      view |> element("button[aria-label='Remove small.jpg']") |> render_click()
      press(view, "draft")

      assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
      assert [_stored] = images_of(product.id)
    end

    test "a file of a kind we don't accept is refused in plain words, and saving stays on the page",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      file_input(view, "#product-form", :images, [
        %{name: "drawing.gif", content: "GIF89a", type: "image/gif"}
      ])
      |> render_upload("drawing.gif")

      assert render(view) =~ "This kind of file isn&#39;t accepted."

      press(view, "draft", new_product_params(category))
      product = only_product_of(artist)
      assert_patch(view, ~p"/vendor/products/#{product.id}/edit")
      assert has_element?(view, "#photo-problem", "drawing.gif was NOT saved")
    end

    # The browser's PhotoShrink hook (assets/js/photo_shrink.js) can't
    # run in these tests; they check the server's side of it.
    test "the picker carries the browser's shrinking code and the server's limits",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      assert has_element?(
               view,
               "[phx-hook=PhotoShrink][data-max-pixels='52000000'][data-long-side='4096']" <>
                 "[data-too-large-message='This photo is too large. Please use a smaller version.']"
             )

      assert has_element?(view, "[phx-hook=PhotoShrink] [data-preparing-list][phx-update=ignore]")
    end

    test "while the browser is still preparing a photo, saving waits for it",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      # What the hook sends when the artist has picked a photo.
      render_hook(view, "photo_picker_state", %{"preparing" => true, "refused" => []})
      press(view, "draft", new_product_params(category))

      # The text is saved, the page stays and says why.
      product = only_product_of(artist)
      assert_patch(view, ~p"/vendor/products/#{product.id}/edit")
      assert has_element?(view, "#photo-problem", "Your photos are still being prepared.")

      # The hook is done and hands the photo to LiveView. The message is
      # out of date now, so it goes, and saving works.
      render_hook(view, "photo_picker_state", %{"preparing" => false, "refused" => []})
      refute has_element?(view, "#photo-problem")
      pick_photos(view, "#product-form", :images, [good_photo()])
      press(view, "draft")

      assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
      assert [_stored] = images_of(product.id)
    end

    test "a photo the browser refused (too large) keeps the save on the page until it's removed",
         %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      # The hook refused a 60 MP photo without uploading it, and the
      # artist picked a good one too.
      render_hook(view, "photo_picker_state", %{"preparing" => false, "refused" => ["huge.png"]})
      pick_photos(view, "#product-form", :images, [good_photo()])
      press(view, "draft", new_product_params(category))

      product = only_product_of(artist)
      assert_patch(view, ~p"/vendor/products/#{product.id}/edit")

      assert has_element?(
               view,
               "#photo-problem",
               "Your photo huge.png was NOT uploaded: This photo is too large."
             )

      assert images_of(product.id) == []

      # The artist removes the red row with ✕; now saving works.
      render_hook(view, "photo_picker_state", %{"preparing" => false, "refused" => []})
      refute has_element?(view, "#photo-problem")
      press(view, "draft")

      assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
      assert [_stored] = images_of(product.id)
    end

    test "a malformed picker message doesn't crash the page", %{conn: conn, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

      # The message comes from the browser, so it can be anything.
      render_hook(view, "photo_picker_state", %{})
      render_hook(view, "photo_picker_state", %{"preparing" => "yes", "refused" => "x"})
      render_hook(view, "photo_picker_state", %{"refused" => [1, nil, %{"a" => 1}]})

      # Still alive, and none of these counted as "preparing" or "refused".
      press(view, "draft", new_product_params(category))
      assert_redirect(view, @wait)
    end

    @tag :heic
    test "an iPhone HEIC photo is accepted", %{conn: conn, artist: artist, category: category} do
      {:ok, view, _html} = live(conn, ~p"/vendor/products/new")
      pick_photos(view, "#product-form", :images, [heic_photo()])

      press(view, "draft", new_product_params(category))
      product = only_product_of(artist)
      assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
      assert [_stored] = images_of(product.id)
    end
  end
end
