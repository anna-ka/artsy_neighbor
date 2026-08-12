defmodule ArtsyNeighbor.Repo.Migrations.AddOnboardingCompleteToArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :onboarding_complete, :boolean, default: false, null: false
    end
  end
end
