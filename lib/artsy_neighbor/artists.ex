defmodule ArtsyNeighbor.Artists do
  @moduledoc """
  The Artists context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo
  alias Ecto.Multi

  alias ArtsyNeighbor.Artists.Artist
  alias ArtsyNeighbor.Artists.ArtistImage
  alias ArtsyNeighbor.Products.ProductCollection

  @doc """
  Returns the list of all artists. Associations not preloaded by default.
   Artists are ordered by their main medium (first element in the medium array) and then by

  ## Examples

      iex> list_artists()
      [%Artist{}, ...]

  """
  def list_artists do
    Artist
    |> order_by([a], fragment("?[1]", a.medium))
    |> order_by(asc: :area_code)
    |> Repo.all()
  end


  @doc """
    Returns the list of all artists with their associated images preloaded.
    Artists are ordered by their main medium (first element in the medium array) and then by area code.
    ## Examples

        iex> list_artists_with_images()
        [%Artist{artist_images: [%ArtistImage{}, ...]}, ...]

   """
  def list_artists_with_images do
    Artist
    |> order_by([a], fragment("?[1]", a.medium))
    |> order_by(asc: :area_code)
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  @doc """
  Returns the list of artists filtered by the given status.
  If status is nil, returns all artists.
  """
  def with_status(query, nil), do: query
  def with_status(query, status), do: where(query, [a], a.status == ^status)

  @doc """
  Filters artists by the given area code.
  """
  def filter_artists_by_area(area_code) do
    Artist
    |> where([a], a.area_code == ^area_code)
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end

  @doc """
  Filters artists by the given medium.
  """
  def filter_artists_by_medium(medium) do
    search_term = "%#{medium}%"
    Artist
    |> where([a], fragment("EXISTS (SELECT 1 FROM unnest(?) AS m WHERE m ILIKE ?)", a.medium, ^search_term))
    |> Repo.all()
    |> Repo.preload([:artist_images])
  end





  @doc """
  Filters artists based on provided parameters.
  It shows only active artists by default, but can be extended to include other statuses if needed.

  Suported parameters:
    - "q_name": filters by artist nickname
    - "q_medium": filters by medium
  ## Examples

      iex> filter_artists(%{"q_name" => "Elena", "q_medium" => "Oil"})
      [%Artist{}, ...]
  """
  def filter_artists(filter_params ) do

    q_name = String.trim( filter_params["q_name"] || "")
    q_medium = String.trim( filter_params["q_medium"] || "")
    sort_term = String.trim( filter_params["sort_by"] || "" )

    Artist
    |> with_status(:active)
    |> with_nickname(q_name)
    |> with_medium(q_medium)
    |> sort_by(sort_term)
    |> Repo.all()
    |> Repo.preload([:artist_images])

  end

  @doc """
  Filters artists by medium if provided.
  """
  def with_medium(query, q_medium)
    when (is_binary(q_medium) and q_medium != "") do
      search_term = "%#{q_medium}%"

      query
      |> where([a], fragment("EXISTS (SELECT 1 FROM unnest(?) AS m WHERE m ILIKE ?)", a.medium, ^search_term))
  end

  def with_medium(query, _), do: query


  @doc """
  Filters artists by nickname if provided.
  """
  def with_nickname(query, nickname)
    when (is_binary(nickname) and nickname != "") do
      search_term = "%#{nickname}%"

      query
      |> where([a], ilike(a.nickname, ^search_term))
  end

  def with_nickname(query, _), do: query

  def sort_by(query, "area_code")  do
    query
    |> order_by(asc: :area_code)
  end

  def sort_by(query, "nickname")  do
    query
    |> order_by(asc: :nickname)
  end

  def sort_by(query, "main_medium")  do
    query
    |> order_by([a], fragment("?[1]", a.medium))
  end

  def sort_by(query, _), do: query

  @doc """
  Gets a single artist by ID.

  ## Examples

      iex> get_artist(123)
      %Artist{}

      iex> get_artist(456)
      nil

  """
  def get_artist(id) do
    Repo.get(Artist, id)
    |> Repo.preload([:artist_images])
  end


  @doc """
  Gets a single artist by artist ID, bang version.
  Throws `Ecto.NoResultsError` if the Artist does not exist.
  """
  def get_artist!(id) do
    Repo.get!(Artist, id)
    |> Repo.preload([:artist_images])
  end

  @doc """
  Gets a single artist by user ID.
  Returns nil if the Artist does not exist.
  Needed for associating artists with user accounts.
  """
  def get_artist_by_user_id(user_id) do
    Repo.get_by(Artist, user_id: user_id)
  end

  @doc """
  Creates a new artist with the given attributes, and atomically inserts a
  default "Uncategorized" collection for the new artist.
  Returns {:ok, %{artist: artist, collection: collection}} or {:error, step, changeset, _}.
  """
  def create_artist(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:artist, Artist.changeset(%Artist{}, attrs))
    |> Multi.insert(:collection, fn %{artist: artist} ->
      ProductCollection.changeset(%ProductCollection{}, %{
        name: "Uncategorized",
        position: 1,
        artist_id: artist.id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{artist: artist}} -> {:ok, artist}
      {:error, :artist, changeset, _} -> {:error, changeset}
      {:error, :collection, _changeset, _} -> {:error, :collection_creation_failed}
    end
  end

  @doc """
  A helper function to get a changeset for an artist.
  Does not make any changes to DB.
  """
  def change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.changeset(artist, attrs)
  end

  @doc """
  Updates an existing artist with the given attributes.
  """
  def update_artist(%Artist{} = artist, attrs \\ %{}) do
    artist
    |> change_artist(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an artist.
  """
  def delete_artist(%Artist{} = artist) do
    Repo.delete(artist)
  end

  @doc """
  Creates a new ArtistImage for the given artist.
  artist_id is injected from the Artist struct — never from form params.
  """
  def create_artist_image(%Artist{} = artist, attrs \\ %{}) do
    %ArtistImage{}
    |> ArtistImage.changeset(Map.put(attrs, :artist_id, artist.id))
    |> Repo.insert()
  end

  @doc """
  Returns all images for the given artist, ordered by position ascending.
  """
  def get_images_for_artist(%Artist{} = artist) do
    ArtistImage
    |> where(artist_id: ^artist.id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  Swaps the position values of two ArtistImage records atomically.
  Used for reordering images up/down in the profile form.
  """
  def swap_image_positions(%ArtistImage{} = img1, %ArtistImage{} = img2) do
    Repo.transaction(fn ->
      {:ok, _} = update_artist_image(img1, %{position: img2.position})
      {:ok, _} = update_artist_image(img2, %{position: img1.position})
    end)
  end

  @doc """
  Updates an ArtistImage with the given attributes.
  """
  def update_artist_image(%ArtistImage{} = artist_image, attrs \\ %{}) do
    artist_image
    |> ArtistImage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an ArtistImage record.
  """
  def delete_artist_image(%ArtistImage{} = artist_image) do
    Repo.delete(artist_image)
  end



end
