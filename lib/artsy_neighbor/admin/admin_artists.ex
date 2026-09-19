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

  @doc """
  Updates an artist. Delegates to Artists.update_artist/2, matching every
  other function in this module — not a separate implementation. This
  used to do its own change_artist/2 + Repo.update/1 directly, which meant
  it silently skipped Artists.update_artist/2's own :active -> :inactive
  product cascade (see that function's doc comment) despite looking
  identical to it. Not currently called from any LiveView (only this
  module's own tests exercise it) — fixed now so it isn't a live trap if
  it ever is.
  """
  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    Artists.update_artist(artist, attrs)
  end

  @doc """
  Marks an artist as removed (soft, reversible). See Artists.soft_delete_artist/1.
  """
  def soft_delete_artist(%Artist{} = artist) do
    Artists.soft_delete_artist(artist)
  end

  @doc """
  Reverses soft_delete_artist/1. See Artists.restore_artist/1.
  """
  def restore_artist(%Artist{} = artist) do
    Artists.restore_artist(artist)
  end

  @doc """
  Permanently deletes an artist and everything that depends on them. See
  Artists.hard_delete_artist/1.
  """
  def hard_delete_artist(%Artist{} = artist) do
    Artists.hard_delete_artist(artist)
  end
end
