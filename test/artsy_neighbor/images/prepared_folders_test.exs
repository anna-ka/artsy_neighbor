defmodule ArtsyNeighbor.Images.PreparedFoldersTest do
  @moduledoc """
  Tests for `ArtsyNeighbor.Images.PreparedFolders`, the temporary
  folders of photos checked on pick. Each test starts its own server
  with its own base folder, so the app's own one isn't touched.
  """
  use ExUnit.Case, async: true

  alias ArtsyNeighbor.Images.PreparedFolders

  setup do
    base_dir = Path.join(System.tmp_dir!(), "prepared_folders_test_" <> Ecto.UUID.generate())
    File.mkdir_p!(base_dir)
    on_exit(fn -> File.rm_rf(base_dir) end)
    %{base_dir: base_dir}
  end

  # delete_after_ms: 0 deletes a page's folder straight after the page
  # ends (the app waits a minute, see the moduledoc).
  defp start_server(base_dir) do
    name = :"prepared_folders_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {PreparedFolders, name: name, base_dir: base_dir, delete_after_ms: 0},
      id: name
    )

    name
  end

  # A process standing in for a page; it ends when sent :close.
  defp start_page do
    spawn(fn ->
      receive do
        :close -> :ok
      end
    end)
  end

  # True as soon as `check` returns true, within a second.
  defp eventually(check, tries \\ 50) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(20)
        eventually(check, tries - 1)
    end
  end

  test "makes a folder for a page and deletes it, with its files, when the page ends",
       %{base_dir: base_dir} do
    server = start_server(base_dir)
    page = start_page()

    assert {:ok, folder} = PreparedFolders.page_folder(page, server)
    assert File.dir?(folder)
    assert Path.dirname(folder) == base_dir
    File.mkdir_p!(Path.join(folder, "photo"))
    File.write!(Path.join(folder, "photo/source.webp"), "pixels")

    send(page, :close)
    assert eventually(fn -> not File.exists?(folder) end)
  end

  test "each page gets its own folder", %{base_dir: base_dir} do
    server = start_server(base_dir)
    {:ok, first} = PreparedFolders.page_folder(start_page(), server)
    {:ok, second} = PreparedFolders.page_folder(start_page(), server)
    assert first != second
  end

  @tag capture_log: true
  test "at start-up deletes old leftover folders, but keeps recent ones", %{base_dir: base_dir} do
    old = Path.join(base_dir, "old")
    recent = Path.join(base_dir, "recent")
    File.mkdir_p!(Path.join(old, "photo"))
    File.mkdir_p!(recent)
    two_days_ago = System.os_time(:second) - 2 * 24 * 60 * 60
    File.touch!(old, two_days_ago)

    _server = start_server(base_dir)

    # The deleting happens in the background.
    assert eventually(fn -> not File.exists?(old) end)
    assert File.dir?(recent)
  end

  @tag capture_log: true
  test "the sweep leaves the folder of a page that is still open, however old",
       %{base_dir: base_dir} do
    server = start_server(base_dir)
    {:ok, folder} = PreparedFolders.page_folder(start_page(), server)
    File.touch!(folder, System.os_time(:second) - 2 * 24 * 60 * 60)

    send(server, :sweep)
    :sys.get_state(server)

    assert File.dir?(folder)
  end

  test "after a restart of the server, the folders of open pages are watched again",
       %{base_dir: base_dir} do
    first_server = start_server(base_dir)
    page = start_page()
    {:ok, folder} = PreparedFolders.page_folder(page, first_server)

    # The server restarts (and forgets what it was watching).
    stop_supervised!(first_server)
    _second_server = start_server(base_dir)

    assert File.dir?(folder)
    send(page, :close)
    assert eventually(fn -> not File.exists?(folder) end)
  end

  test "a folder whose page ended while the server was down is deleted at start-up",
       %{base_dir: base_dir} do
    first_server = start_server(base_dir)
    page = start_page()
    {:ok, folder} = PreparedFolders.page_folder(page, first_server)
    stop_supervised!(first_server)

    ref = Process.monitor(page)
    send(page, :close)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}

    _second_server = start_server(base_dir)
    assert eventually(fn -> not File.exists?(folder) end)
  end

  test "a recent folder of another server on the same computer is left alone",
       %{base_dir: base_dir} do
    # Its .owner file names another operating-system process.
    other = Path.join(base_dir, "other-server")
    File.mkdir_p!(other)
    File.write!(Path.join(other, ".owner"), :erlang.term_to_binary({"99999999", self()}))

    server = start_server(base_dir)
    :sys.get_state(server)
    Process.sleep(50)

    assert File.dir?(other)
  end
end
