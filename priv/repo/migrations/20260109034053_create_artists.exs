defmodule ArtsyNeighbor.Repo.Migrations.CreateArtists do
  use Ecto.Migration

  def change do
    create table(:artists) do
      add :nickname, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :middle_name, :string
      add :street, :string, null: false
      add :street_number, :string, null: false
      add :apt_info, :string
      add :area_code, :string, null: false
      add :phone, :string, null: false
      add :email, :string, null: false
      add :bio, :text, null: false
      add :medium, {:array, :string}
      add :main_img, :string
      add :img2, :string
      add :img3, :string
      add :img4, :string
      add :img5, :string

      timestamps(type: :utc_datetime)
    end
  end
end
