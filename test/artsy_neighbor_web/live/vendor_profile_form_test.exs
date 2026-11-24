defmodule ArtsyNeighborWeb.VendorProfileFormTest do
  @moduledoc """
  Profile photos on the vendor profile form: a public (:active) profile
  must keep at least one photo (`Artists.delete_artist_image/1`), and
  photos uploaded on step 2 are processed in the background when the
  artist presses Next (`ArtsyNeighborWeb.PhotoUploads`). Also: the
  form can't change a profile's owner or its onboarding state.
  """
  use ArtsyNeighborWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures
  import ArtsyNeighborWeb.PhotoUploadHelpers

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Admin.AdminArtists
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Repo
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
      wait_for_photo_work(view, @wait)
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
      assert has_element?(view, "[id^=photo-entry-]", "This photo is too small to look good.")
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

  # Audit S-2: the profile's owner (user_id) and its onboarding state
  # (onboarding_step, onboarding_complete) are set by the server only.
  # A hand-made request that sends them along with the form must not
  # change them. These tests send the events directly, as such a request
  # would.
  describe "fields only the server sets" do
    # What step 1 of a new profile asks for.
    @step_1_params %{
      "nickname" => "Newcomer",
      "first_name" => "New",
      "last_name" => "Comer",
      "email" => "newcomer@example.com",
      "phone" => "250-555-1234",
      "street_address" => "1 Fort Street",
      "area_code" => "V8W 1A1"
    }

    test "a new profile is always the logged-in user's own, whatever user_id is sent",
         %{conn: conn} do
      victim = artist_fixture()
      victim_user = Accounts.get_user!(victim.user_id)
      user = user_fixture()
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/vendor/profile/new")

      params = Map.put(@step_1_params, "user_id", to_string(victim_user.id))
      render_change(view, "validate", %{"artist" => params})
      # Step 1 saves and then goes on to the edit page; the result is
      # that redirect, not needed here.
      _ = render_click(view, "next_step", %{})

      assert profiles_owned_by(victim_user) == 1
      assert Artists.get_artist_by_user_id(user.id).nickname == "Newcomer"

      # The victim can still open pages (with two profiles, every page
      # would crash).
      victim_conn = log_in_user(build_conn(), victim_user)
      assert html_response(get(victim_conn, ~p"/"), 200)
    end

    test "a user_id sent with the edit form is ignored: the profile keeps its owner",
         %{conn: conn} do
      artist = artist_fixture(%{onboarding_complete: true})
      other_user = user_fixture()
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
      {:ok, view, _html} = live(conn, ~p"/vendor/profile/edit")

      render_change(view, "validate", %{
        "artist" => %{"nickname" => artist.nickname, "user_id" => to_string(other_user.id)}
      })

      render_click(view, "next_step", %{})

      assert Repo.get!(Artist, artist.id).user_id == artist.user_id
      assert Artists.get_artist_by_user_id(other_user.id) == nil
    end

    test "onboarding_step and onboarding_complete sent on step 1 are ignored", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/vendor/profile/new")

      params =
        Map.merge(@step_1_params, %{"onboarding_step" => "3", "onboarding_complete" => "true"})

      render_change(view, "validate", %{"artist" => params})
      _ = render_click(view, "next_step", %{})

      artist = Artists.get_artist_by_user_id(user.id)
      assert artist.onboarding_step == 1
      assert artist.onboarding_complete == false
    end

    test "step 1 of a new profile, when one was made meanwhile in another tab, opens that one",
         %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/vendor/profile/new")

      # The other tab finishes step 1 while this page is open.
      {:ok, existing} =
        AdminArtists.create_artist(%{
          user_id: user.id,
          nickname: "Made Elsewhere",
          first_name: "Made",
          last_name: "Elsewhere",
          email: "made.elsewhere@example.com",
          phone: "250-555-1234",
          street_address: "1 Fort Street",
          area_code: "V8W 1A1",
          bio: String.duplicate("A painter of the coast. ", 5),
          medium: ["Watercolour"]
        })

      render_change(view, "validate", %{"artist" => @step_1_params})
      render_click(view, "next_step", %{})

      {path, flash} = assert_redirect(view)
      assert path == ~p"/vendor/profile/edit"
      assert flash["info"] =~ "You already have an artist profile"
      assert profiles_owned_by(user) == 1
      assert Artists.get_artist_by_user_id(user.id).id == existing.id
    end

    test "the last step's save marks onboarding complete, still ignoring a sent user_id",
         %{conn: conn} do
      # onboarding_step 2 = steps 1 and 2 are done; the form opens on step 3.
      artist = artist_fixture(%{onboarding_step: 2})
      other_user = user_fixture()
      conn = log_in_user(conn, Accounts.get_user!(artist.user_id))
      {:ok, view, _html} = live(conn, ~p"/vendor/profile/edit")

      _ =
        render_submit(view, "save", %{
          "artist" => %{
            "nickname" => artist.nickname,
            "user_id" => to_string(other_user.id),
            "onboarding_step" => "-1"
          }
        })

      saved = Repo.get!(Artist, artist.id)
      assert saved.onboarding_complete == true
      assert saved.onboarding_step == 2
      assert saved.user_id == artist.user_id
    end
  end

  defp profiles_owned_by(user) do
    Repo.aggregate(from(a in Artist, where: a.user_id == ^user.id), :count)
  end
end
