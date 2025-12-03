defmodule ArtsyNeighborWeb.PageController do
  use ArtsyNeighborWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
