defmodule ArtsyNeighbor.Repo.Migrations.AddSnapshotsToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :buyer_email,  :string, null: false, default: ""
      add :vendor_email, :string, null: false, default: ""
      add :artist_name,  :string, null: false, default: ""
    end
  end
end
