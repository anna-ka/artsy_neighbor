defmodule ArtsyNeighbor.Repo.Migrations.CreateVendorsReviewed do
  use Ecto.Migration

  def change do
    create table(:vendors_reviewed) do
      add :order_id,     references(:orders, on_delete: :restrict), null: false
      add :reviewer_id,  references(:users,   on_delete: :restrict), null: false
      add :artist_id,    references(:artists, on_delete: :restrict), null: false
      add :stars,        :integer, null: false
      add :body,         :text

      add :submitted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vendors_reviewed, [:order_id])
    create index(:vendors_reviewed, [:artist_id])
    create index(:vendors_reviewed, [:reviewer_id])
  end
end
