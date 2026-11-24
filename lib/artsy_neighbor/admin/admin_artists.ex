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

  @doc """
  Creates an artist profile with the owner the admin picked
  (`user_id` in `attrs`), plus its default collection
  (`Artists.create_artist/1`).

  The only function that creates a profile from a map of params with an
  owner in it, so it lives here, in the admin context: never call it
  from a vendor's page, where the owner is the logged-in user (audit
  S-2). The test fixtures use it too.
  """
  def create_artist(attrs \\ %{}) do
    %Artist{}
    |> change_artist(attrs)
    |> Artists.create_artist()
  end

  @doc """
  A changeset for the admin artist form. Unlike the vendor's own form,
  it takes the profile's owner (`user_id`): see `Artist.admin_changeset/2`.
  """
  def change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.admin_changeset(artist, attrs)
  end

  def get_artist!(id) do
    Artists.get_artist!(id)
  end

  @doc """
  Updates an artist's profile fields and its owner, for the admin form.
  Never changes the status (see `Artists.update_artist/2`): the form does
  that afterwards through `Artists.change_status/2`.
  """
  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    artist
    |> change_artist(attrs)
    |> Artists.update_artist()
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
