defmodule ArtsyNeighborWeb.PhotoCheckingTest do
  @moduledoc """
  Photos are checked as soon as they're uploaded, before Save (photo
  speed step 3b, `ArtsyNeighborWeb.PhotoUploads`; plan:
  `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`).
  Tried on the vendor product form; the other three photo forms use the
  same code.

  Some tests hold all the slots of the app's own
  `ArtsyNeighbor.Images.Limiter`, so that a photo has to wait for its
  turn, exactly when the test wants it to. That is safe because this
  module isn't async: no other test runs meanwhile.
  """
  use ArtsyNeighborWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighbor.CategoriesFixtures
  import ArtsyNeighborWeb.PhotoUploadHelpers

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Images.Limiter
  alias ArtsyNeighbor.Images.PreparedFolders
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Storage.Local

  @wait 10_000

  setup %{conn: conn} do
    artist = artist_fixture()
    # Made before the page opens: the form lists the categories when it opens.
    category = category_fixture()
    conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
    {:ok, view, _html} = live(conn, ~p"/vendor/products/new")

    on_exit(fn ->
      for product <- products_of(artist) do
        File.rm_rf(Local.path_for("products/#{product.id}", :public))
        File.rm_rf(Local.path_for("products/#{product.id}", :private))
      end
    end)

    %{view: view, artist: artist, category: category}
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

  defp press_save_draft(view, params) do
    view
    |> form("#product-form", product: params)
    |> put_submitter("button[value=draft]")
    |> render_submit()
  end

  # The products of `artist` (made by the form in the test).
  defp products_of(artist) do
    ArtsyNeighbor.Repo.all(
      from product in ArtsyNeighbor.Products.Product, where: product.artist_id == ^artist.id
    )
  end

  defp images_of_only_product(artist) do
    [product] = products_of(artist)
    Products.get_product_with_associations!(product.id).product_images
  end

  # The folders of prepared photos (one per photo, inside the page
  # folders) that exist right now.
  defp prepared_photo_folders do
    Path.wildcard(Path.join(PreparedFolders.default_base_dir(), "*/*"))
  end

  # Takes every slot of the app's Limiter until release_slots/1. Returns
  # the holder processes.
  defp hold_all_slots do
    slots = Application.get_env(:artsy_neighbor, Limiter)[:max_concurrent]
    test_pid = self()

    holders =
      for _ <- 1..slots do
        spawn(fn ->
          Limiter.run(fn ->
            send(test_pid, {:holding, self()})

            receive do
              :release -> :ok
            end
          end)
        end)
      end

    for holder <- holders do
      assert_receive {:holding, ^holder}
    end

    on_exit(fn -> release_slots(holders) end)
    holders
  end

  defp release_slots(holders) do
    for holder <- holders do
      send(holder, :release)
    end
  end

  # A photo checked on pick waits only this long for a slot (instead of
  # minutes), so the "site is busy" case can be tried.
  defp short_wait_for_a_slot do
    Application.put_env(:artsy_neighbor, ArtsyNeighborWeb.PhotoUploads, prepare_wait_ms: 100)
    on_exit(fn -> Application.delete_env(:artsy_neighbor, ArtsyNeighborWeb.PhotoUploads) end)
  end

  test "a picked photo is checked and shows Ready before Save; nothing is stored yet",
       %{view: view} do
    before = prepared_photo_folders()
    pick_photos(view, "#product-form", :images, [good_photo()])
    wait_for_photo_work(view)

    assert has_element?(view, "[id^=photo-entry-]", "Ready ✓")

    # Its files are in a temporary folder, not in storage.
    assert [photo_folder] = prepared_photo_folders() -- before
    assert File.exists?(Path.join(photo_folder, "source.webp"))
    assert File.exists?(Path.join(photo_folder, "thumb.webp"))
  end

  test "a photo that can't be used says so before Save", %{view: view} do
    pick_photos(view, "#product-form", :images, [small_photo()])
    wait_for_photo_work(view)

    assert has_element?(view, "[id^=photo-entry-]", "This photo is too small to look good.")
    refute has_element?(view, "[id^=photo-entry-]", "Ready")
    # Nothing to try again: the photo itself is the problem.
    refute has_element?(view, "button[phx-click=retry_photo]")
  end

  test "Save while a photo is still being checked waits for it, then stores it",
       %{view: view, artist: artist, category: category} do
    holders = hold_all_slots()
    pick_photos(view, "#product-form", :images, [good_photo()])
    assert has_element?(view, "[id^=photo-entry-]", "Checking the photo…")

    press_save_draft(view, new_product_params(category))
    # The text is saved; the page says it's saving and stays.
    assert has_element?(view, "#saving-photos")
    refute has_element?(view, "#photo-problem")

    # The photo gets its turn: it's checked, stored, and the form moves on.
    release_slots(holders)
    [product] = products_of(artist)
    assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
    assert [image] = images_of_only_product(artist)
    assert File.exists?(Local.path_for(image.path <> "/source.webp", :private))
  end

  @tag capture_log: true
  test "a photo that waited too long says the site is busy, and Try again works",
       %{view: view} do
    short_wait_for_a_slot()
    holders = hold_all_slots()
    pick_photos(view, "#product-form", :images, [good_photo()])
    wait_for_photo_work(view)

    assert has_element?(view, "[id^=photo-entry-]", "The site is busy")
    assert has_element?(view, "button[phx-click=retry_photo]", "Try again")

    release_slots(holders)
    view |> element("button[phx-click=retry_photo]") |> render_click()
    wait_for_photo_work(view)

    assert has_element?(view, "[id^=photo-entry-]", "Ready ✓")
    refute has_element?(view, "button[phx-click=retry_photo]")
  end

  @tag capture_log: true
  test "Save tries a photo that failed on our side once more",
       %{view: view, artist: artist, category: category} do
    short_wait_for_a_slot()
    holders = hold_all_slots()
    pick_photos(view, "#product-form", :images, [good_photo()])
    wait_for_photo_work(view)
    assert has_element?(view, "[id^=photo-entry-]", "The site is busy")

    release_slots(holders)
    press_save_draft(view, new_product_params(category))

    [product] = products_of(artist)
    assert_redirect(view, ~p"/vendor/products/#{product.id}/edit", @wait)
    assert [_image] = images_of_only_product(artist)
  end

  test "Save with a photo that can't be used stores the good ones and stays, asking to remove it",
       %{view: view, artist: artist, category: category} do
    pick_photos(view, "#product-form", :images, [good_photo(), small_photo()])
    wait_for_photo_work(view)

    press_save_draft(view, new_product_params(category))
    [product] = products_of(artist)
    assert_patch(view, ~p"/vendor/products/#{product.id}/edit", @wait)
    wait_for_photo_work(view)

    assert has_element?(
             view,
             "#photo-problem",
             "Your photo small.jpg was NOT saved: This photo is too small to look good. " <>
               "Please use a larger one. Remove it with ✕ and pick another photo, then save again."
           )

    assert [_good_one] = images_of_only_product(artist)
  end

  test "removing a ready photo with ✕ deletes its temporary files", %{view: view} do
    before = prepared_photo_folders()
    pick_photos(view, "#product-form", :images, [good_photo()])
    wait_for_photo_work(view)
    [photo_folder] = prepared_photo_folders() -- before

    view |> element("button[aria-label='Remove cat.jpg']") |> render_click()

    refute File.exists?(photo_folder)
    refute has_element?(view, "[id^=photo-entry-]")
  end

  test "removing a photo while it waits for its turn stops it at once", %{view: view} do
    _holders = hold_all_slots()
    pick_photos(view, "#product-form", :images, [good_photo()])
    assert length(:sys.get_state(Limiter).waiting) == 1

    view |> element("button[aria-label='Remove cat.jpg']") |> render_click()

    # It has left the line straight away, while the slots are still held.
    assert eventually(fn -> :sys.get_state(Limiter).waiting == [] end)
    refute has_element?(view, "[id^=photo-entry-]")
  end

  @tag capture_log: true
  test "when one photo finds the site busy, the photos after it aren't left waiting too",
       %{view: view} do
    short_wait_for_a_slot()
    holders = hold_all_slots()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        pick_photos(view, "#product-form", :images, [good_photo("one.jpg"), good_photo("two.jpg")])

        wait_for_photo_work(view)
      end)

    # Only the first one waited in line; the second got the same message.
    assert length(String.split(log, "waited too long")) == 2
    assert row_of(view, "one.jpg") =~ "The site is busy"
    assert row_of(view, "two.jpg") =~ "The site is busy"

    # One "Try again" tries both again. (Each row has the button, and
    # they all send the same event, so the event is sent directly.)
    release_slots(holders)
    render_click(view, "retry_photo", %{})
    wait_for_photo_work(view)

    assert row_of(view, "one.jpg") =~ "Ready ✓"
    assert row_of(view, "two.jpg") =~ "Ready ✓"
  end

  # The HTML of the upload box row of the photo named `name`.
  defp row_of(view, name) do
    view |> element("[id^=photo-entry-]", name) |> render()
  end

  test "removing a photo while it's being checked throws its result away", %{view: view} do
    holders = hold_all_slots()
    before = prepared_photo_folders()
    pick_photos(view, "#product-form", :images, [good_photo()])
    view |> element("button[aria-label='Remove cat.jpg']") |> render_click()

    # The check gets its turn after the photo was removed.
    release_slots(holders)
    wait_for_photo_work(view)
    render_async(view, @wait)

    assert prepared_photo_folders() -- before == []
    refute has_element?(view, "[id^=photo-entry-]")
  end

  # Killing the page makes its upload processes log errors.
  @tag capture_log: true
  test "closing the page deletes its temporary folder", %{view: view} do
    before = prepared_photo_folders()
    pick_photos(view, "#product-form", :images, [good_photo()])
    wait_for_photo_work(view)
    [photo_folder] = prepared_photo_folders() -- before
    page_folder = Path.dirname(photo_folder)

    # As when the artist closes the tab: the page's process ends. (The
    # test process is linked to it; trapping exits keeps the test alive.)
    Process.flag(:trap_exit, true)
    ref = Process.monitor(view.pid)
    Process.exit(view.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}

    # PreparedFolders is told too, and deletes the folder.
    assert eventually(fn -> not File.exists?(page_folder) end)
  end

  # True as soon as `check` returns true, within a second.
  defp eventually(check, tries \\ 50) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(20)
        eventually(check, tries - 1)
    end
  end
end
