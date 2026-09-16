defmodule ArtsyNeighbor.Admin.AdminArtists do
  @moduledoc """
  Admin context module for managing artists.
  """

  import Ecto.Query
  alias ArtsyNeighbor.Repo
  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists

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

  @doc """
  Returns every artist regardless of status, sorted active → inactive →
  removed, then nickname. Used by the admin artist index.
  """
  def list_artists_all_status do
    Artists.list_artists_all_status()
  end

  def create_artist(attrs \\ %{}) do
    Artists.create_artist(attrs)
  end

  @doc """
  A helper function to get a changeset for an artist.
  """
  def change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.activation_changeset(artist, attrs)
  end

  def get_artist!(id) do
    Artists.get_artist!(id)
  end

  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    artist
    |> change_artist(attrs)
    |> Repo.update()
  end

  @doc """
  Marks an artist as removed (soft, reversible). See Artists.remove_artist/1.
  """
  def remove_artist(%Artist{} = artist) do
    Artists.remove_artist(artist)
  end

  @doc """
  Permanently deletes an artist and everything that depends on them. See
  Artists.delete_artist/1.
  """
  def delete_artist(%Artist{} = artist) do
    Artists.delete_artist(artist)
  end
end
