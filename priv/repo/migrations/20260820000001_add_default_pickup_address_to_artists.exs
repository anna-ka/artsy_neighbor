defmodule ArtsyNeighbor.Repo.Migrations.AddDefaultPickupAddressToArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :default_pickup_address, :string
    end
  end
end
