defmodule ArtsyNeighbor.Artists.Artist do
  use Ecto.Schema
  import Ecto.Changeset

  schema "artists" do
    field :nickname, :string
    field :first_name, :string
    field :last_name, :string
    field :middle_name, :string
    field :street, :string
    field :street_number, :string
    field :apt_info, :string
    field :area_code, :string
    field :phone, :string
    field :email, :string
    field :bio, :string
    field :medium, {:array, :string}
    field :main_img, :string
    field :img2, :string
    field :img3, :string
    field :img4, :string
    field :img5, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(artist, attrs) do
    artist
    |> cast(attrs, [:nickname, :first_name, :last_name, :middle_name, :email, :street, :street_number, :apt_info, :area_code, :phone, :bio, :medium, :main_img, :img2, :img3, :img4, :img5])
    |> validate_required([:nickname, :first_name, :last_name, :phone, :bio, :main_img, :email, :street, :street_number, :area_code, :medium])
  end
end
