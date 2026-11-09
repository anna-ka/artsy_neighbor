defmodule ArtsyNeighbor.Repo.Migrations.DefaultProductStatusToDraft do
  use Ecto.Migration

  # New products now start as :draft (hidden) until they have a photo and
  # are published — see Products.publish_product/1. The column is a plain
  # string, so the new :draft value needs no migration; only the database
  # default changes, to match the schema's default. Existing rows keep
  # their status.
  def change do
    alter table(:products) do
      modify :status, :string,
        default: "draft",
        null: false,
        from: {:string, default: "available", null: false}
    end
  end
end
