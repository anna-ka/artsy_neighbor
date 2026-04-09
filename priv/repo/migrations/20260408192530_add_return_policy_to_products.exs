defmodule ArtsyNeighbor.Repo.Migrations.AddReturnPolicyToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :return_policy, :string,
        default: "All sales final unless item is significantly not as described."
    end

  end
end
