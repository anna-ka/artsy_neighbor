defmodule ArtsyNeighbor.Repo.Migrations.AddDeliveryStatusSmediaToArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :delivery_options, {:array, :string}, default: []
      add :delivery_info, :map, default: %{}
      add :status, :string, default: "inactive"
      add :status_changed_at , :utc_datetime
      add :homepage, :string
      add :instagram, :string
      add :facebook, :string
    end

  end
end
