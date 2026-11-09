defmodule ArtsyNeighborWeb.VendorProfileFormTest do
  @moduledoc """
  Profile photos on the vendor profile form: a public (:active) profile
  must keep at least one photo (`Artists.delete_artist_image/1`), and
  photos uploaded on step 2 are processed in the background when the
  artist presses Next (`ArtsyNeighborWeb.PhotoUploads`).
  """
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighborWeb.PhotoUploadHelpers

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Storage.Local

  test "removing the last photo of a public profile is refused, saying what to do instead",
       %{conn: conn} do
    artist = artist_fixture(%{status: :active})
    image = artist_image_fixture(artist)
    conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
    {:ok, view, _html} = live(conn, ~p"/vendor/profile/edit")

    # The photo list is on step 2 of the form; the event is sent
    # directly rather than clicking through the steps.
    html = render_click(view, "delete_image", %{"imageid" => to_string(image.id)})

    assert html =~ "Please upload another photo before removing this one."
    assert html =~ "De-activate profile"
    assert length(Artists.get_images_for_artist(artist)) == 1
  end

  test "the last photo of a hidden profile can be removed", %{conn: conn} do
    artist = artist_fixture(%{status: :inactive})
    image = artist_image_fixture(artist)
    conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
    {:ok, view, _html} = live(conn, ~p"/vendor/profile/edit")

    render_click(view, "delete_image", %{"imageid" => to_string(image.id)})

    assert Artists.get_images_for_artist(artist) == []
  end

  describe "uploading photos on step 2" do
    @wait 10_000

    # Opens the edit form of a finished profile and goes to step 2.
    defp open_step_2(conn, artist) do
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
      {:ok, view, _html} = live(conn, ~p"/vendor/profile/edit")

      on_exit(fn ->
        File.rm_rf(Local.path_for("artists/#{artist.id}", :public))
        File.rm_rf(Local.path_for("artists/#{artist.id}", :private))
      end)

      view |> element("button[phx-click=next_step]") |> render_click()
      assert has_element?(view, "#artist_form input[type=file]")
      view
    end

    # Waits until the background processing is done and returns the page.
    defp wait_for_photos(view) do
      render_async(view, @wait)
    end

    test "a good photo is stored and the form moves on to step 3", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive, onboarding_complete: true})
      view = open_step_2(conn, artist)
      pick_photos(view, "#artist_form", :profile_images, [good_photo()])

      view |> element("button[phx-click=next_step]") |> render_click()
      html = wait_for_photos(view)

      assert html =~ "Payment info stub"
      assert [image] = Artists.get_images_for_artist(artist)
      assert String.starts_with?(image.path, "artists/#{artist.id}/")
    end

    test "with a second photo, the form stays on step 2 and asks to check the order",
         %{conn: conn} do
      artist = artist_fixture(%{status: :inactive, onboarding_complete: true})
      artist_image_fixture(artist)
      view = open_step_2(conn, artist)
      pick_photos(view, "#artist_form", :profile_images, [good_photo()])

      view |> element("button[phx-click=next_step]") |> render_click()
      html = wait_for_photos(view)

      assert html =~ "check their order"
      refute html =~ "Payment info stub"
      assert length(Artists.get_images_for_artist(artist)) == 2
    end

    test "a refused photo keeps the form on step 2, with the reason in red", %{conn: conn} do
      artist = artist_fixture(%{status: :inactive, onboarding_complete: true})
      view = open_step_2(conn, artist)
      pick_photos(view, "#artist_form", :profile_images, [small_photo()])

      view |> element("button[phx-click=next_step]") |> render_click()
      html = wait_for_photos(view)

      refute html =~ "Payment info stub"
      assert html =~ "Not saved: This photo is too small to look good."
      assert has_element?(view, "#photo-problem", "small.jpg was NOT saved")
      assert Artists.get_images_for_artist(artist) == []
    end

    test "pressing Enter on step 2 (a form submit) saves the picked photos like Next does",
         %{conn: conn} do
      artist = artist_fixture(%{status: :inactive, onboarding_complete: true})
      view = open_step_2(conn, artist)
      pick_photos(view, "#artist_form", :profile_images, [good_photo()])

      view |> form("#artist_form") |> render_submit()
      html = wait_for_photos(view)

      assert html =~ "Payment info stub"
      assert [_stored] = Artists.get_images_for_artist(artist)
    end

    test "while photos are being saved, Previous, Enter and the photo buttons do nothing",
         %{conn: conn} do
      artist = artist_fixture(%{status: :inactive, onboarding_complete: true})
      view = open_step_2(conn, artist)
      pick_photos(view, "#artist_form", :profile_images, [good_photo()])

      view |> element("button[phx-click=next_step]") |> render_click()
      assert has_element?(view, "#saving-photos")
      # The file picker and Previous are disabled meanwhile.
      assert has_element?(view, "#artist_form input[type=file][disabled]")
      assert has_element?(view, "button[phx-click=prev_step][disabled]")

      # Sent anyway (e.g. a fast double press): ignored, no navigation.
      render_click(view, "prev_step", %{})
      view |> form("#artist_form") |> render_submit()
      assert has_element?(view, "#saving-photos")

      html = wait_for_photos(view)
      assert html =~ "Payment info stub"
      assert [_stored] = Artists.get_images_for_artist(artist)
    end
  end
end
