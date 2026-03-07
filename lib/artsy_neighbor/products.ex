defmodule ArtsyNeighbor.Products do
  @moduledoc """
  The Products context.
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Repo

  alias ArtsyNeighbor.Products.Product
  alias ArtsyNeighbor.Products.ProductOption
  alias ArtsyNeighbor.Products.ProductImage

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products()
      [%Product{}, ...]

  """
  def list_products do
    Repo.all(Product)
  end

  @doc """
  Returns the list of products with
  product_images, artist, and category associations preloaded.

  """
  def list_products_with_associations do
    Repo.all(from p in Product, preload: [:product_images,  :artist, :category])
  end


  @doc """
  Filters products based on the provided filter criteria.
  All products are loaded with associations.
  """
  def filter_products(filter) do
    Product
    |> join(:inner, [p], a in assoc(p, :artist), as: :artist)
    |> join(:inner, [p], c in assoc(p, :category), as: :category)
    |> with_category(filter["category_id"])
    |> with_artist(filter["artist"])
    |> with_string(filter["search"])
    |> sort_by(filter["sort_by"])
    |> preload([:product_images, :artist, :category])
    |> Repo.all()



  end

  # Returns the list of products that have particular category.
  defp with_category(query, nil), do: query
  defp with_category(query, ""), do: query
  defp with_category(query, category_id) do
    id = String.to_integer(category_id)
    where(query, [p], p.category_id == ^id)
  end

  # Returns the list of products that have a particular artist's nickname.
  defp with_artist(query, nil), do: query
  defp with_artist(query, ""), do: query
  defp with_artist(query, artist_name) do
    search = "%#{artist_name}%"
    where(query, [artist: a], ilike(a.nickname, ^search))
  end

  # Returns the list of products that have a particular string
  # in their title, or in their category name or description.
  defp with_string(query, nil), do: query
  defp with_string(query, ""), do: query
  defp with_string(query, string) do
    search = "%#{string}%"
    query
    |> where([p], ilike(p.title, ^search))
    |> or_where([category: c], ilike(c.name, ^search))
    |> or_where([category: c], ilike(c.description, ^search))
  end

  # Sorts the products. Supported: "price_asc", "price_desc", "artist", "category".
  # Defaults to title order.
  defp sort_by(query, "price_asc"), do: order_by(query, [p], asc: p.price)
  defp sort_by(query, "price_desc"), do: order_by(query, [p], desc: p.price)
  defp sort_by(query, "artist"), do: order_by(query, [artist: a], asc: a.nickname)
  defp sort_by(query, "category"), do: order_by(query, [category: c], asc: c.name)
  defp sort_by(query, _), do: order_by(query, [p], asc: p.title)



  @doc """
  Gets a single product.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %Product{}

      iex> get_product!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product!(id), do: Repo.get!(Product, id)


  @doc"""
  Gets a single product with all associations preloaded.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product_with_associations!(123)
      %Product{product_images: [...], artist: %Artist{}, category: %Category{}}

      iex> get_product_with_associations!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product_with_associations!(id) do
    Repo.get!(Product, id)
    |> Repo.preload([:product_images, :product_options, :artist, :category])
  end

  # Returns nil if product does not exist.
  def get_product_with_associations(id) do
    case Repo.get(Product, id) do
      nil -> nil
      product -> Repo.preload(product, [:product_images, :product_options, :artist, :category])
    end
  end


  @doc"""
  Gets products by a specific artist.

  ## Examples

      iex> get_products_by_artist(artist_id)
      [%Product{artist_id: artist_id, ...}, ...]

  """
  def get_products_by_artist(artist_id) do
    Product
    |> where([p], p.artist_id == ^artist_id)
    |> preload([:product_images, :artist, :category])
    |> Repo.all()
  end

  @doc """
  Returns products that have a specific category.
  ## Examples

      iex> get_products_by_category(category_id)
      [%Product{category_id: category_id, ...}, ...]

  """
  def get_products_by_category(category_id) do
    Product
    |> where([p], p.category_id == ^category_id)
    |> preload([:product_images, :artist, :category])
    |> Repo.all()
  end


  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{field: value})
      {:ok, %Product{}}

      iex> create_product(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(attrs) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %Product{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product.

  ## Examples

      iex> delete_product(product)
      {:ok, %Product{}}

      iex> delete_product(product)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{data: %Product{}}

  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end




  @doc """
  Returns all product images.
  """
  def list_product_images do
    Repo.all(ProductImage)
  end

  @doc """
  Returns the list of product images for a specific product, ordered by position.

  ## Examples

      iex> list_images_for_product(product_id)
      [%ProductImage{}, ...]

  """
  def list_images_for_product(product_id) do
    ProductImage
    |> where([i], i.product_id == ^product_id)
    |> order_by([i], asc: i.position)
    |> Repo.all()
  end





  @doc """
  Gets a single product_image.

  Raises `Ecto.NoResultsError` if the Product image does not exist.

  ## Examples

      iex> get_product_image!(123)
      %ProductImage{}

      iex> get_product_image!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product_image!(id), do: Repo.get!(ProductImage, id)

  @doc """
  Creates a product_image.

  ## Examples

      iex> create_product_image(%{field: value})
      {:ok, %ProductImage{}}

      iex> create_product_image(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product_image(attrs) do
    %ProductImage{}
    |> ProductImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product_image.

  ## Examples

      iex> update_product_image(product_image, %{field: new_value})
      {:ok, %ProductImage{}}

      iex> update_product_image(product_image, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product_image(%ProductImage{} = product_image, attrs) do
    product_image
    |> ProductImage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product_image.

  ## Examples

      iex> delete_product_image(product_image)
      {:ok, %ProductImage{}}

      iex> delete_product_image(product_image)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product_image(%ProductImage{} = product_image) do
    Repo.delete(product_image)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product_image changes.

  ## Examples

      iex> change_product_image(product_image)
      %Ecto.Changeset{data: %ProductImage{}}

  """
  def change_product_image(%ProductImage{} = product_image, attrs \\ %{}) do
    ProductImage.changeset(product_image, attrs)
  end

  @doc """
  Returns the list of product_options.

  ## Examples

      iex> list_product_options()
      [%ProductOption{}, ...]

  """
  def list_product_options do
    Repo.all(ProductOption)
  end

  @doc """
  Gets a single product_option.

  Raises `Ecto.NoResultsError` if the Product option does not exist.

  ## Examples

      iex> get_product_option!(123)
      %ProductOption{}

      iex> get_product_option!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product_option!(id), do: Repo.get!(ProductOption, id)

  @doc """
  Creates a product_option.

  ## Examples

      iex> create_product_option(%{field: value})
      {:ok, %ProductOption{}}

      iex> create_product_option(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product_option(attrs) do
    %ProductOption{}
    |> ProductOption.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product_option.

  ## Examples

      iex> update_product_option(product_option, %{field: new_value})
      {:ok, %ProductOption{}}

      iex> update_product_option(product_option, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product_option(%ProductOption{} = product_option, attrs) do
    product_option
    |> ProductOption.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product_option.

  ## Examples

      iex> delete_product_option(product_option)
      {:ok, %ProductOption{}}

      iex> delete_product_option(product_option)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product_option(%ProductOption{} = product_option) do
    Repo.delete(product_option)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product_option changes.

  ## Examples

      iex> change_product_option(product_option)
      %Ecto.Changeset{data: %ProductOption{}}

  """
  def change_product_option(%ProductOption{} = product_option, attrs \\ %{}) do
    ProductOption.changeset(product_option, attrs)
  end
end
