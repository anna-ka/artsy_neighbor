defmodule ArtsyNeighbor.Admin.AdminArtists do

  @moduledoc """
  Admin context module for managing artists.
  """

  import Ecto.Query
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
  def change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.changeset(artist, attrs)
  end

  def get_artist!(id) do
    Repo.get!(Artist, id)
  end

  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    artist
    |> change_artist(attrs)
    |> Repo.update()
  end

  def delete_artist(%Artist{} = artist) do
    Repo.delete(artist)
  end

end
