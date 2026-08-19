defmodule ArtsyNeighbor.Repo.Migrations.AllowNullParticipantsInConversations do
  # buyer_id and artist_id were originally NOT NULL because every conversation
  # was between a buyer and an artist. System conversations (platform → user inbox)
  # have neither, so we drop the NOT NULL constraint.
  use Ecto.Migration

  def up do
    execute "ALTER TABLE conversations ALTER COLUMN buyer_id DROP NOT NULL"
    execute "ALTER TABLE conversations ALTER COLUMN artist_id DROP NOT NULL"
  end

  def down do
    execute "ALTER TABLE conversations ALTER COLUMN buyer_id SET NOT NULL"
    execute "ALTER TABLE conversations ALTER COLUMN artist_id SET NOT NULL"
  end
end
