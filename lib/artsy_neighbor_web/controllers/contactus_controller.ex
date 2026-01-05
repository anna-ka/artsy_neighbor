defmodule ArtsyNeighborWeb.ContactusController do
  use ArtsyNeighborWeb, :controller

  def contactus(conn, _params) do
    render(conn, :contact)
  end

end
