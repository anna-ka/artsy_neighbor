defmodule ArtsyNeighbor.Repo.Migrations.AddOnboardingStepToArtists do
  use Ecto.Migration

  def change do
    alter table(:artists) do
      add :onboarding_step, :integer, default: -1, null: false
    end
  end
end
