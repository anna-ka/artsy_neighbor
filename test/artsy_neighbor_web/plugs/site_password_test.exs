defmodule ArtsyNeighborWeb.Plugs.SitePasswordTest do
  # Not async: these tests switch the password on for the whole app, which
  # would make other tests running at the same time get 401 answers.
  use ArtsyNeighborWeb.ConnCase, async: false

  @image "/images/site/logo-draft.png"

  describe "when no site password is configured (dev and test)" do
    test "pages and files are served as usual", %{conn: conn} do
      assert conn |> get(~p"/") |> html_response(200)
      assert get(build_conn(), @image).status == 200
    end
  end

  describe "when a site password is configured (the private deployment)" do
    setup do
      Application.put_env(:artsy_neighbor, :site_password,
        username: "tester",
        password: "right-password"
      )

      on_exit(fn -> Application.delete_env(:artsy_neighbor, :site_password) end)
    end

    test "a page asks for the password", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert conn.status == 401

      assert get_resp_header(conn, "www-authenticate") ==
               ["Basic realm=\"Artsy Neighbor (private)\""]
    end

    test "an image asks for the password too", %{conn: conn} do
      assert get(conn, @image).status == 401
    end

    test "a wrong password is refused", %{conn: conn} do
      conn =
        conn
        |> with_site_login("tester", "wrong-password")
        |> get(~p"/")

      assert conn.status == 401
    end

    test "the right username and password let pages and files through", %{conn: conn} do
      assert conn
             |> with_site_login("tester", "right-password")
             |> get(~p"/")
             |> html_response(200)

      image_conn = build_conn() |> with_site_login("tester", "right-password") |> get(@image)
      assert image_conn.status == 200
    end
  end

  # What the browser sends after the visitor fills in its login box.
  defp with_site_login(conn, username, password) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(username, password))
  end
end
