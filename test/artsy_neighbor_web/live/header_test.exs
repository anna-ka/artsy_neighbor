defmodule ArtsyNeighborWeb.HeaderTest do
  # The site header (Layouts.navlayout/1) and the Account page it links to.
  use ArtsyNeighborWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ArtsyNeighbor.AccountsFixtures
  import ArtsyNeighbor.ArtistsFixtures

  alias ArtsyNeighbor.Accounts.Admin
  alias ArtsyNeighbor.Accounts.User
  alias ArtsyNeighbor.Repo

  describe "header links" do
    test "a visitor sees Log in and Register, not Messages or Account", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, ".header-links a", "Log in")
      assert has_element?(lv, ".header-links a", "Register")
      assert has_element?(lv, ".header-links a", "Offer art")
      refute has_element?(lv, ".header-links a", "Messages")
      refute has_element?(lv, ".header-links a", "Account")
    end

    test "a logged-in buyer sees Messages, Orders and Account", %{conn: conn} do
      {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/")

      assert has_element?(lv, ".header-links a[href='/messages']", "Messages")
      assert has_element?(lv, ".header-links a[href='/orders']", "Orders")
      assert has_element?(lv, ".header-links a[href='/account']", "Account")
      assert has_element?(lv, ".header-links a", "Offer art")
      refute has_element?(lv, ".header-links a", "Log in")
      refute has_element?(lv, ".header-links a", "Your shop")
      refute has_element?(lv, ".header-links a", "Admin")
    end

    test "an artist sees Your shop instead of Offer art", %{conn: conn} do
      artist = artist_fixture()
      user = Repo.get!(User, artist.user_id)

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/")

      assert has_element?(lv, ".header-links a[href='/vendor']", "Your shop")
      refute has_element?(lv, ".header-links a", "Offer art")
    end

    test "an admin sees Admin, and admin pages have the Admin strip", %{conn: conn} do
      user = user_fixture()
      Repo.insert!(%Admin{user_id: user.id})
      conn = log_in_user(conn, user)

      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(home, ".header-links a[href='/admin']", "Admin")
      refute has_element?(home, ".admin-strip")

      # A wide admin page (artsy_wide) shows the logged-in header too.
      {:ok, admin_page, _html} = live(conn, ~p"/admin/artists")
      assert has_element?(admin_page, ".admin-strip", "Admin")
      assert has_element?(admin_page, ".header-links a", "Account")
    end
  end

  describe "Account page" do
    test "shows who is logged in, the way to settings, and Log out", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

      assert has_element?(lv, "#account-username", user.username)
      assert has_element?(lv, "#account-email", user.email)
      assert has_element?(lv, "a[href='/users/settings']")
      assert has_element?(lv, "#log-out[href='/users/log-out'][data-method='delete']")
    end

    test "opens even long after logging in (no re-login needed)", %{conn: conn} do
      long_ago = DateTime.add(DateTime.utc_now(:second), -2, :hour)

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture(), token_authenticated_at: long_ago)
        |> live(~p"/account")

      assert html =~ "Your account"
    end

    test "sends a visitor to the log-in page", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/account")
      assert path == ~p"/users/log-in"
    end
  end
end
