defmodule ArtsyNeighbor.Repo.Migrations.AddDimensionsAndMaterialsToProducts do
  use Ecto.Migration

  def change do
  alter table(:products) do
    add :width,     :decimal, null: true
    add :length,    :decimal, null: true
    add :height,    :decimal, null: true
    add :units,     :string,  null: false, default: "cm"
    add :materials, :text,    null: true
  end

  create constraint(:products, :valid_units, check: "units IN ('cm', 'in')")
end

end
