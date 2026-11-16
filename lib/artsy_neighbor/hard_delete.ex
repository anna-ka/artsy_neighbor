defmodule ArtsyNeighbor.HardDelete do
  @moduledoc """
  The shared transaction behind every `hard_delete_<entity>/1` that has to
  clean up `Flag` rows by hand: `Artists.hard_delete_artist/1`,
  `Products.hard_delete_product/1`, and the three
  `Reviews.hard_delete_*_review/1` functions.

  Why flags need cleaning up by hand: `Flag.subject_id` is a polymorphic
  reference — depending on `Flag.subject_type` it points at an artist, a
  product, a buyer, or one of three review tables. Postgres can't enforce a
  real foreign key on a column like that, so deleting the flagged row
  doesn't cascade to its flags; without this cleanup they'd be left behind
  pointing at an id that no longer exists.

  `delete_with_flags/2` runs four steps in one transaction:

    1. Re-read the row with `SELECT ... FOR UPDATE`, which locks it until
       the transaction ends. Postgres takes a `FOR KEY SHARE` lock on the
       referenced row for every FK-checked insert, so holding `FOR UPDATE`
       makes any concurrent insert of a row that references this one
       directly (an order, a review, an order item, a photo of this
       product, ...) wait until we're done. It also means we delete the
       current DB row, not whatever the caller's possibly-stale struct
       says. Rows that reference it only *indirectly* (a photo of one of
       an artist's products) aren't held up by this lock; the caller
       locks those parents itself in step 2 if it needs to.
    2. Ask the caller what goes away along with this row: the flag
       subjects, and the `path`s of photo rows (whose files must go too).
       This runs against the locked row and *before* the delete, because
       after the DB-level `on_delete` cascades run, the dependent ids (e.g.
       an artist's product ids) can no longer be looked up.
    3. Delete the flags for those subjects.
    4. Delete the row itself. DB-level cascades handle everything with a
       real foreign key, photo rows included.

  Then, only once the transaction has committed, the photos' files are
  deleted from storage (`Images.delete_files/1`, in the background).
  Storage isn't part of the database transaction, so doing it earlier
  could delete files of rows that a rollback brings back.

  Known, accepted gap: the lock in step 1 does *not* block a concurrent
  `Flag` insert, since Flag has no foreign key for Postgres to lock
  against. A flag inserted between steps 3 and 4 can outlive its subject.
  See `NOTES.md` ("Flag-cleanup delete paths have a narrow race").
  """

  import Ecto.Query, warn: false
  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Repo
  alias ArtsyNeighbor.Reviews.Flag
  alias Ecto.Multi

  @doc """
  Deletes `record` and every `Flag` reporting a subject that goes away with
  it, in one transaction (see the moduledoc for the steps).

  `going_away_fun` receives the repo and the locked, freshly-read row,
  and returns a map with:

    * `:flag_subjects` — a map from `Flag.subject_type` to the list of
      subject ids being removed, e.g.
      `%{"vendor" => [artist.id], "product" => [4, 5]}`;
    * `:photo_paths` (optional, default none) — the `path` values of the
      photo rows removed with it; their files are deleted after the
      commit. Records without photos (reviews) leave it out.

  Returns `{:ok, deleted_row}`, or `{:error, reason}` where `reason` is:

    * `:not_found` — the row no longer exists (e.g. already deleted from
      another tab)
    * `{:database_error, message}` — the database refused the delete. Most
      often a foreign key with `on_delete: :nothing`/`:restrict` still has
      rows pointing at this one (e.g. an order item pointing at a
      product), but it can be any Postgres error (a deadlock, a lock
      timeout, ...). These raise rather than coming back through the
      Multi's own error tuple, so they're rescued here and reported the
      same way — callers only ever handle `{:ok, _}` or `{:error, _}`.
    * whatever `Repo.delete/1` returned as its error, otherwise

  `error_message/1` turns any of these into text for an admin flash.
  """
  def delete_with_flags(record, going_away_fun) do
    schema = record.__struct__

    Multi.new()
    |> Multi.run(:locked, fn repo, _changes ->
      case repo.one(from(r in schema, where: r.id == ^record.id, lock: "FOR UPDATE")) do
        nil -> {:error, :not_found}
        locked -> {:ok, locked}
      end
    end)
    |> Multi.run(:going_away, fn repo, %{locked: locked} ->
      {:ok, going_away_fun.(repo, locked)}
    end)
    |> Multi.run(:deleted_flags, fn repo, %{going_away: going_away} ->
      flag_subjects = Map.fetch!(going_away, :flag_subjects)
      {count, _} = repo.delete_all(from(f in Flag, where: ^flags_matching(flag_subjects)))
      {:ok, count}
    end)
    |> Multi.run(:deleted, fn repo, %{locked: locked} ->
      repo.delete(locked)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{deleted: deleted, going_away: going_away}} ->
        # Committed: now the files can go too.
        Images.delete_files(Map.get(going_away, :photo_paths, []))
        {:ok, deleted}

      {:error, _failed_step, reason, _changes_so_far} ->
        {:error, reason}
    end
  rescue
    error in [Ecto.ConstraintError, Postgrex.Error] ->
      {:error, {:database_error, database_error_text(error)}}
  end

  @doc """
  Turns any `{:error, reason}` from `delete_with_flags/2` into one line of
  text for an admin flash message — the database's own words where there
  are some, rather than a guess at the cause. Hard delete is admin-only,
  so showing the raw reason is the most useful thing to do.
  """
  def error_message(:not_found) do
    "it no longer exists (already deleted, perhaps from another tab)"
  end

  def error_message({:database_error, text}), do: text

  def error_message(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)

  def error_message(other), do: inspect(other)

  # Ecto.ConstraintError's own message is mostly developer advice ("call
  # foreign_key_constraint/3 on your changeset..."); the useful part is the
  # constraint's name, which says which table blocked the delete — e.g.
  # "order_items_product_id_fkey". Postgrex.Error carries Postgres's own
  # message in its `postgres` field when the error came from the database.
  defp database_error_text(%Ecto.ConstraintError{} = error) do
    "#{error.type} constraint \"#{error.constraint}\" was violated"
  end

  defp database_error_text(%Postgrex.Error{postgres: %{message: message}}), do: message

  defp database_error_text(error), do: Exception.message(error)

  # Turns %{"vendor" => [1], "product" => [4, 5]} into the WHERE condition
  #
  #   (subject_type == "vendor" and subject_id in [1]) or
  #   (subject_type == "product" and subject_id in [4, 5])
  #
  # `dynamic/2` builds a query fragment piece by piece; each step ORs one
  # more subject type onto the fragment built so far. Starting from `false`
  # means an empty map matches no flags, rather than all of them.
  defp flags_matching(flag_subjects) do
    Enum.reduce(flag_subjects, dynamic(false), fn {subject_type, ids}, conditions_so_far ->
      dynamic(
        [f],
        ^conditions_so_far or (f.subject_type == ^subject_type and f.subject_id in ^ids)
      )
    end)
  end
end
