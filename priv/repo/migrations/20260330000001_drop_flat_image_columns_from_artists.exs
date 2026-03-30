defmodule ArtsyNeighbor.Repo.Migrations.DropFlatImageColumnsFromArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      remove :main_img
      remove :img2
      remove :img3
      remove :img4
      remove :img5
    end
  end
end
