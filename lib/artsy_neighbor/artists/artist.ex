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
    field :delivery_options, {:array, :string}, default: ["pickup"]
    field :delivery_info, :map, default: %{}
    field :status, Ecto.Enum, values: [:active, :inactive, :removed], default: :inactive
    field :status_changed_at, :utc_datetime
    field :homepage, :string
    field :instagram, :string
    field :facebook, :string
    field :announcement, :string
    field :announcement_active, :boolean, default: false

    has_many :products, ArtsyNeighbor.Products.Product
    has_many :artist_images, ArtsyNeighbor.Artists.ArtistImage
    belongs_to :user, ArtsyNeighbor.Accounts.User

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
        :user_id,
        :delivery_options,
        :delivery_info,
        :status,
        :homepage,
        :instagram,
        :facebook,
        :announcement,
        :announcement_active])
    |> validate_required([:nickname, :first_name, :last_name, :phone, :bio, :email,
                        :street_address, :area_code, :medium])
    |> validate_length(:bio, min: 75, message: "Bio must be at least 75 characters long.")
    |> validate_length(:first_name, min: 2, message: "First name must be at least 2 characters long.")
    |> validate_length(:last_name, min: 2, message: "Last name must be at least 2 characters long.")
    |> validate_email()
    |> validate_phone()
    |> validate_canadian_postal_code()
    |> assoc_constraint(:user)
    |> maybe_set_status_changed_at()
    |> maybe_validate_delivery_options()
    |> validate_url(:homepage)
    |> validate_url(:instagram)
    |> validate_url(:facebook)
  end

  # If the status field has changed, update the status_changed_at timestamp
  defp maybe_set_status_changed_at(changeset) do
    if Ecto.Changeset.changed?(changeset, :status) do
      Ecto.Changeset.put_change(changeset, :status_changed_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end

  #Verifies that delivery options are valid if they have changed
  defp maybe_validate_delivery_options(changeset) do
    if Ecto.Changeset.changed?(changeset, :delivery_options) do
        changeset
          |> validate_inclusion( :delivery_options, ["pickup", "artist_delivery", "shipping", "other"],
            message: "Delivery options must be one of: pickup, local_delivery, shipping")
          |> maybe_validate_delivery_info()
    else
      changeset
    end
  end


  # Validates that delivery_info keys match the selected delivery_options and that notes are not too long.
  defp maybe_validate_delivery_info(changeset) do

    delivery_options = Ecto.Changeset.get_field(changeset, :delivery_options) || []
    delivery_info = Ecto.Changeset.get_field(changeset, :delivery_info) || %{}

    invalid_keys = Map.keys(delivery_info) -- delivery_options

    if invalid_keys == [] do
        changeset
        |> validate_delivery_notes_length()
    else
      Ecto.Changeset.add_error(changeset, :delivery_info,
        "contains notes for unknown delivery options: #{Enum.join(invalid_keys, ", ")}")
    end
  end

  # Checks that each delivery note value is not too long (max 500 chars).
  # Iterates map values since validate_length only works on strings/lists.
  defp validate_delivery_notes_length(changeset) do
    delivery_info = Ecto.Changeset.get_field(changeset, :delivery_info) || %{}

    Enum.reduce(delivery_info, changeset, fn {key, value}, acc ->
      if is_binary(value) && String.length(value) > 500 do
        Ecto.Changeset.add_error(acc, :delivery_info,
          "note for '#{key}' must be 500 characters or fewer")
      else
        acc
      end
    end)
  end



  # Validates that a field contains a properly formatted URL
  defp validate_url(changeset, field) do
    if Ecto.Changeset.changed?(changeset, field) do
      validate_format(changeset, field,
        ~r/^(https?:\/\/)?([\w\-]+\.)+[\w\-]+(\/[\w\-._~:\/?#\[\]@!$&'()*+,;=]*)?$/,
        message: "must be a valid URL (e.g., https://www.example.com)")
    else
      changeset
    end
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
