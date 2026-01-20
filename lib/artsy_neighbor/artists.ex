defmodule ArtsyNeighbor.Artists do
  @moduledoc """
  The Artists context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Artists.Artist

  @doc """
  Returns the list of all artists.

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
  Filters artists by the given area code.
  """
  def filter_artists_by_area(area_code) do
    Artist
    |> where([a], a.area_code == ^area_code)
    |> Repo.all()
  end

  @doc """
  Filters artists by the given medium.
  """
  def filter_artists_by_medium(medium) do
    search_term = "%#{medium}%"
    Artist
    |> where([a], fragment("EXISTS (SELECT 1 FROM unnest(?) AS m WHERE m ILIKE ?)", a.medium, ^search_term))
    |> Repo.all()
  end





  @doc """
  Filters artists based on provided parameters.

  Suported parameters:
    - "q_name": filters by artist nickname
    - "q_medium": filters by medium
  ## Examples

      iex> filter_artists(%{"q_name" => "Elena", "q_medium" => "Oil"})
      [%Artist{}, ...]
  """
  def filter_artists(filter_params) do

    q_name = String.trim( filter_params["q_name"] || "")
    q_medium = String.trim( filter_params["q_medium"] || "")
    sort_term = String.trim( filter_params["sort_by"] || "" )

    Artist
    |> with_nickname(q_name)
    |> with_medium(q_medium)
    |> sort_by(sort_term)
    |> Repo.all()

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
  end


  @doc """
  Creates a new artist with the given attributes.
  """
  def create_artist(attrs \\ %{}) do
    %Artist{
    nickname: attrs.nickname,
    first_name: attrs.first_name,
    last_name: attrs.last_name,
    middle_name: attrs.middle_name,
    email: attrs.email,
    street_address: attrs.street_address,
    apt_info: attrs.apt_info,
    area_code: attrs.area_code,
    phone: attrs.phone,
    bio: attrs.bio,
    medium: attrs.medium,
    main_img: attrs.main_img,
    img2: attrs.img2,
    img3: attrs.img3,
    img4: attrs.img4,
    img5: attrs.img5
  }
    |> Repo.insert()
  end

end
