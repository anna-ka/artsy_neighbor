defmodule ArtsyNeighbor.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :title, :string
    field :descr, :string
    field :details, :string
    field :price, :decimal

    field :width, :decimal
    field :length, :decimal
    field :height, :decimal
    field :units, :string, default: "cm"
    field :materials, :string

    field :position, :integer
    field :unique_work, :boolean, default: false
    # :draft — not finished yet (e.g. no photo); hidden from the public.
    # New products start here. Only Products.publish_product/2 makes a
    # product :available, and it refuses while it has no photos.
    field :status, Ecto.Enum,
      values: [:draft, :available, :unavailable, :archived],
      default: :draft

    belongs_to :category, ArtsyNeighbor.Categories.Category
    belongs_to :artist, ArtsyNeighbor.Artists.Artist
    belongs_to :collection, ArtsyNeighbor.Products.ProductCollection
    has_many :product_images, ArtsyNeighbor.Products.ProductImage
    has_many :product_options, ArtsyNeighbor.Products.ProductOption

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :title,
      :descr,
      :details,
      :price,
      # Not :artist_id: the owner is set on the struct by the server
      # (Products.create_product/2), or by admin_changeset/2 for the
      # admin form, which picks it on purpose (audit S-3).
      :category_id,
      :collection_id,
      # Not :position: the order of works changes only through
      # Products.swap_product_positions/3 (position_changeset/2).
      :width,
      :length,
      :height,
      :units,
      :materials,
      :unique_work
      # Not :status: the forms send their fields straight here, so a
      # hand-made request could otherwise set any status. Status changes
      # only through Products.publish_product/2, soft_delete_product/2,
      # restore_product/2 and delete_product_image/2, which apply the
      # rules (see status_changeset/2).
    ])
    |> validate_required([:title, :descr, :details, :price, :artist_id, :category_id])
    |> validate_length(:title,
      min: 3,
      max: 100,
      min_message: "Title must be at least 3 characters long.",
      max_message: "Title must be at most 100 characters long."
    )
    |> validate_length(:descr,
      min: 10,
      max: 2000,
      min_message: "Description must be at least 10 characters long.",
      max_message: "Description must be at most 2000 characters long."
    )
    |> validate_number(:price, greater_than: 0, message: "Price must be greater than zero.")
    |> validate_inclusion(:units, ["cm", "in"])
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:length, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
  end

  @doc """
  Like `changeset/2`, but also takes the owner (`artist_id`) from
  `attrs`. Only for the admin product form, which picks the artist on
  purpose, through `ArtsyNeighbor.Admin.AdminProducts`. Never use it
  with a vendor's form params (audit S-3).
  """
  def admin_changeset(product, attrs) do
    # artist_id is cast first, so that changeset/2's validate_required
    # sees it.
    product
    |> cast(attrs, [:artist_id])
    |> changeset(attrs)
    |> assoc_constraint(:artist)
  end

  @doc """
  Changeset for status-only updates (e.g. Products.soft_delete_product/2). Scoped
  to just :status so archiving/restoring a product never risks re-running
  the full-profile validations above against fields that aren't changing.
  """
  def status_changeset(product, attrs) do
    product
    |> cast(attrs, [:status])
    |> validate_required([:status])
  end

  @doc """
  Changes only the position, for reordering works on the vendor
  dashboard (`Products.swap_product_positions/3`).
  """
  def position_changeset(product, attrs) do
    cast(product, attrs, [:position])
  end
end
