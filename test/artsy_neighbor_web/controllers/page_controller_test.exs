defmodule ArtsyNeighborWeb.PageControllerTest do
  use ArtsyNeighborWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "localpalette"
  end
end
