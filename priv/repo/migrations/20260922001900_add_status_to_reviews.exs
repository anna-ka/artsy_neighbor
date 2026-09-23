defmodule ArtsyNeighbor.Repo.Migrations.AddStatusToReviews do
  use Ecto.Migration

  def change do
    for table_name <- [:vendors_reviewed, :buyers_reviewed, :product_reviews] do
      alter table(table_name) do
        add :status, :string, default: "active", null: false
        add :status_changed_at, :utc_datetime
      end
    end
  end
end
