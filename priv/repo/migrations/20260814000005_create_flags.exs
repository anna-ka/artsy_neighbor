defmodule ArtsyNeighbor.Repo.Migrations.CreateFlags do
  use Ecto.Migration

  def change do
    create table(:flags) do
      add :reporter_id,   references(:users, on_delete: :restrict), null: false
      add :subject_type,  :string, null: false
      add :subject_id,    :integer, null: false
      add :reason,        :text, null: false
      add :status,        :string, null: false, default: "pending"
      add :reviewed_at,   :utc_datetime
      add :reviewed_by,   references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # One flag per reporter per subject — prevents spam flagging
    create unique_index(:flags, [:reporter_id, :subject_type, :subject_id])
    create index(:flags, [:subject_type, :subject_id])
    create index(:flags, [:status])
  end
end
