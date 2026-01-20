defmodule ArtsyNeighbor.Artists.Artist do
  use Ecto.Schema
  import Ecto.Changeset

  schema "artists" do
    field :nickname, :string
    field :first_name, :string
    field :last_name, :string
    field :middle_name, :string
    field :street_address, :string
    field :apt_info, :string
    field :area_code, :string
    field :phone, :string
    field :email, :string
    field :bio, :string
    field :medium, {:array, :string}
    field :main_img, :string, default: "/images/avatar-placeholder.png"
    field :img2, :string
    field :img3, :string
    field :img4, :string
    field :img5, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(artist, attrs) do
    artist
    |> cast(attrs, [:nickname,
        :first_name,
        :last_name,
        :middle_name,
        :email,
        :street_address,
        :apt_info,
        :area_code,
        :phone,
        :bio,
        :medium,
        :main_img,
        :img2,
        :img3,
        :img4,
        :img5])
    |> validate_required([:nickname, :first_name, :last_name, :phone, :bio, :main_img, :email, :street_address, :area_code, :medium])
    |> validate_length(:bio, min: 75, message: "Bio must be at least 75 characters long.")
    |> validate_length(:first_name, min: 2, message: "First name must be at least 2 characters long.")
    |> validate_length(:last_name, min: 2, message: "Last name must be at least 2 characters long.")
    |> validate_email()
    |> validate_phone()
    |> validate_canadian_postal_code()
  end

  # Validates email format
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
  end

  # Validates North American phone number format
  # Accepts formats like: (416) 555-1234, 416-555-1234, 4165551234, +1-416-555-1234
  defp validate_phone(changeset) do
    changeset
    |> validate_format(:phone, ~r/^(\+?1[-.\s]?)?(\(?\d{3}\)?[-.\s]?)?\d{3}[-.\s]?\d{4}$/,
        message: "must be a valid phone number (e.g., 250-555-1234 or (238) 555-1234)")
  end

  # Validates Canadian postal code format (e.g., M5H 2N2, m5h2n2, M5H2N2)
  defp validate_canadian_postal_code(changeset) do
    changeset
    |> validate_format(:area_code, ~r/^[A-Za-z]\d[A-Za-z][\s]?\d[A-Za-z]\d$/,
        message: "must be a valid Canadian postal code (e.g., M5H 2N2)")
  end
end
