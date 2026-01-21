defmodule ArtsyNeighbor.Admin.AdminArtists do

  @moduledoc """
  Admin context module for managing artists.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Artists.Artist

  @doc """
  Returns the list of all artists sorted by time of insertion.

  ## Examples

      iex> list_artists()
      [%Artist{}, ...]

  """
  def list_artists do
    Artist
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def create_artist(attrs \\ %{}) do
    %Artist{}
    |> Artist.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  A helper function to get a changeset for an artist.
  """
  def get_changeset_for_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.changeset(artist, attrs)
  end

end
