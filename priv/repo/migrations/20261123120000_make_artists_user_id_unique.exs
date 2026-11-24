defmodule ArtsyNeighbor.Repo.Migrations.MakeArtistsUserIdUnique do
  use Ecto.Migration

  # A user may own only one artist profile (audit S-2). With two, every
  # page they opened would crash: Accounts.Scope looks their profile up
  # with Repo.get_by/2 on every request, which raises when two rows match.
  #
  # Replaces the plain index from 20260305220504_add_user_to_artist_table.
  # Both have the same name (artists_user_id_index), which is the name
  # unique_constraint(:user_id) in Artist expects. Profiles without an
  # owner (user_id NULL) are still allowed, any number of them: Postgres
  # doesn't count NULLs as equal.
  #
  # Fails if some user already owns two profiles; checked on dev and on
  # the Fly preview on 2026-11-23 (none).
  def change do
    drop index(:artists, [:user_id])
    create unique_index(:artists, [:user_id])
  end
end
