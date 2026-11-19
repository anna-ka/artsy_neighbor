defmodule ArtsyNeighbor.ImagesStoreFailureTest do
  @moduledoc """
  A photo's four files are written to storage at the same time
  (`Images.store_files/2`). If one of them fails, whether storage
  returns an error or crashes, the artist gets the "something went
  wrong" message, nothing of that photo is left in storage, and the
  local work folder (with the private source.webp) is removed.

  This swaps the storage backend for the whole app for a moment, so
  it's in its own module with `async: false`: no other test runs at the
  same time.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Storage.Local

  @photo "priv/static/images/cat-sculpture.jpg"

  # Stands in for Storage.Local: stores like it, except that writing a
  # photo's medium.webp fails, in the way the test asks for.
  defmodule FailingStorage do
    alias ArtsyNeighbor.Storage.Local

    def put(local_file, key, visibility) do
      if String.ends_with?(key, "/medium.webp") do
        case Application.fetch_env!(:artsy_neighbor, :failing_storage_mode) do
          :error -> {:error, :storage_said_no}
          :raise -> raise "storage exploded"
        end
      else
        Local.put(local_file, key, visibility)
      end
    end

    def delete_prefix(prefix), do: Local.delete_prefix(prefix)
    def url(key), do: Local.url(key)
    def read(key, visibility), do: Local.read(key, visibility)
  end

  setup do
    previous = Application.fetch_env!(:artsy_neighbor, ArtsyNeighbor.Storage)
    Application.put_env(:artsy_neighbor, ArtsyNeighbor.Storage, backend: FailingStorage)

    on_exit(fn ->
      Application.put_env(:artsy_neighbor, ArtsyNeighbor.Storage, previous)
      Application.delete_env(:artsy_neighbor, :failing_storage_mode)
    end)

    # A folder of its own, so the test can check it ends up empty.
    folder = "products/#{System.unique_integer([:positive])}"
    %{folder: folder}
  end

  # The files (public and private) under `folder`, at any depth.
  defp files_under(folder) do
    for visibility <- [:public, :private],
        path <- Path.wildcard(Path.join(Local.path_for(folder, visibility), "**/*.*")) do
      path
    end
  end

  # The local work folders process_upload makes (and should remove).
  defp work_folders do
    Path.wildcard(Path.join(System.tmp_dir!(), "artsy_neighbor_image_*"))
  end

  for mode <- [:error, :raise] do
    test "storage that #{if mode == :error, do: "returns an error", else: "crashes"} " <>
           "for one file: plain message, nothing left behind",
         %{folder: folder} do
      Application.put_env(:artsy_neighbor, :failing_storage_mode, unquote(mode))
      work_folders_before = work_folders()

      log =
        capture_log(fn ->
          assert {:error, "Something went wrong while saving your photo." <> _} =
                   Images.process_upload(@photo, "cat.jpg", folder)
        end)

      assert log =~ "Storing image #{folder}/"
      # The three files that were stored have been deleted again.
      assert files_under(folder) == []
      assert work_folders() -- work_folders_before == []
    end
  end
end
