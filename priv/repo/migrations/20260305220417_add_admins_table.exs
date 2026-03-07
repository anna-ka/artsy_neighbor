defmodule ArtsyNeighbor.Repo.Migrations.AddAdminsTable do
  use Ecto.Migration

  def change do
     create table(:admins) do
       add :user_id, references(:users, on_delete: :delete_all)
       timestamps(updated_at: false)
     end

     create unique_index(:admins, [:user_id])

  end
end
