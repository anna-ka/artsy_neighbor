defmodule ArtsyNeighborWeb.VendorProfileFormTest do
  @moduledoc """
  Profile photos on the vendor profile form: a public (:active) profile
  must keep at least one photo (`Artists.delete_artist_image/1`).
  """
  use ArtsyNeighborWeb.ConnCase

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Accounts
  alias ArtsyNeighbor.Artists

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
end
