defmodule ArtsyNeighbor.Repo.Migrations.MakeFlagsUniqueIndexPendingOnly do
  use Ecto.Migration

  @moduledoc """
  The original unique_index(:flags, [:reporter_id, :subject_type, :subject_id])
  blocked a reporter from ever flagging the same subject twice, even long
  after the original flag was resolved. That's too strict: a reporter should
  be able to file a new report on the same subject once their earlier one
  has been reviewed or dismissed. Replace it with a partial unique index
  that only applies while a flag is :pending, so Postgres itself enforces
  "at most one open report per (reporter, subject) at a time" without
  blocking legitimate re-reports after resolution.
  """

  def up do
    drop unique_index(:flags, [:reporter_id, :subject_type, :subject_id])

    create unique_index(:flags, [:reporter_id, :subject_type, :subject_id],
             where: "status = 'pending'",
             name: :flags_reporter_subject_pending_index
           )
  end

  def down do
    drop unique_index(:flags, [:reporter_id, :subject_type, :subject_id],
           name: :flags_reporter_subject_pending_index
         )

    create unique_index(:flags, [:reporter_id, :subject_type, :subject_id])
  end
end
