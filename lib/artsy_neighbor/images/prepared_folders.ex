defmodule ArtsyNeighbor.Images.PreparedFolders do
  @moduledoc """
  Temporary folders for photos prepared as soon as they're picked, one
  folder per open page, and their clean-up.

  The photo forms process each photo when it has finished uploading
  (`Images.prepare_upload/4`, called from `ArtsyNeighborWeb.PhotoUploads`)
  and keep the result in their page's folder until the artist saves.
  If the artist leaves or closes the page, nothing will ever save those
  files, so they must be deleted:

    * `page_folder/1` makes a new folder for a page and starts
      **watching the page's process** (a monitor). When the process
      ends, for whatever reason, this server is told and deletes the
      folder a little later (see "Why later" below).
    * Each folder holds a small `.owner` file naming its page's
      process (and the operating system's id of this running server, so
      folders of another server on the same computer, e.g. a test run
      next to the dev server, are never mistaken for ours). If this
      server process restarts (it would forget what it was watching),
      it reads those files and watches the pages that are still open
      again.
    * In case something gets past all that (e.g. the server stopped
      mid-photo), at start-up and then once an hour it deletes any
      folder older than a day that no open page is using.

  **Why later:** when a page ends, a photo it was preparing may still be
  in the middle of a libvips step, which finishes before its process
  can stop, and could write a file (or remake the photo's folder) just
  after the page's folder was deleted. A minute later that's over.

  The deleting runs in separate processes, so a big folder doesn't hold
  up other pages asking for theirs.

  It's a small server process (a `GenServer`) started with the app.
  Plan: "3b" in `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`.
  """

  use GenServer

  require Logger

  @sweep_every_ms 60 * 60 * 1000
  @max_age_seconds 24 * 60 * 60
  @default_delete_after_ms 60_000

  # The file in each page folder naming the page's process.
  @owner_file ".owner"

  # --- Public functions ----------------------------------------------

  @doc """
  Starts the server. Options (only passed by tests; `:delete_after_ms`
  can also be set in config): `:name`, `:base_dir` (where the page
  folders go), `:max_age_seconds`, `:delete_after_ms` (how long after a
  page ends its folder is deleted).
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Makes a new, empty folder for the page process `page_pid` and returns
  `{:ok, folder}`, or `{:error, reason}` if it couldn't be made. The
  folder is deleted after `page_pid` ends. `server` is only passed by
  tests.
  """
  def page_folder(page_pid, server \\ __MODULE__) do
    GenServer.call(server, {:page_folder, page_pid})
  end

  @doc """
  Where the page folders go (the app's own server): `:base_dir` in
  config (the tests use their own), else a folder in the system's
  temporary folder.
  """
  def default_base_dir do
    :artsy_neighbor
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:base_dir, Path.join(System.tmp_dir!(), "artsy_neighbor_prepared"))
  end

  # --- The server ----------------------------------------------------

  # State:
  #   base_dir        — where the page folders go;
  #   max_age_seconds — how old an unused folder must be to be swept;
  #   delete_after_ms — how long after its page ended a folder goes;
  #   folders         — %{monitor reference => folder}, one per open
  #                     page; the reference comes back in the :DOWN
  #                     message when the page ends.

  @impl true
  def init(opts) do
    config = Application.get_env(:artsy_neighbor, __MODULE__, [])

    state = %{
      base_dir: Keyword.get(opts, :base_dir, default_base_dir()),
      max_age_seconds: Keyword.get(opts, :max_age_seconds, @max_age_seconds),
      delete_after_ms:
        Keyword.get(opts, :delete_after_ms) ||
          Keyword.get(config, :delete_after_ms, @default_delete_after_ms),
      folders: %{}
    }

    state = watch_existing_folders(state)

    # Sweep straight away (leftovers from before a restart) and then
    # once an hour. A message to ourselves, so start-up isn't held up.
    send(self(), :sweep)

    {:ok, state}
  end

  @impl true
  def handle_call({:page_folder, page_pid}, _from, state) do
    folder = Path.join(state.base_dir, Ecto.UUID.generate())

    with :ok <- File.mkdir_p(folder),
         :ok <- File.write(Path.join(folder, @owner_file), owner_contents(page_pid)) do
      {:reply, {:ok, folder}, watch(state, page_pid, folder)}
    else
      {:error, reason} ->
        Logger.error("Couldn't create the photo folder #{folder}: #{inspect(reason)}")
        delete_in_background(folder)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  # A page ended: its prepared photos can go, a little later.
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {folder, folders} = Map.pop(state.folders, ref)

    if folder do
      Process.send_after(self(), {:delete, folder}, state.delete_after_ms)
    end

    {:noreply, %{state | folders: folders}}
  end

  def handle_info({:delete, folder}, state) do
    delete_in_background(folder)
    {:noreply, state}
  end

  def handle_info(:sweep, state) do
    sweep(state)
    Process.send_after(self(), :sweep, @sweep_every_ms)
    {:noreply, state}
  end

  defp watch(state, page_pid, folder) do
    ref = Process.monitor(page_pid)
    %{state | folders: Map.put(state.folders, ref, folder)}
  end

  # After a restart of this server: watch again the folders whose page
  # is still open. Folders of pages that have ended are deleted (later,
  # like any other); folders without a readable `.owner` file are left
  # to the sweep's age rule.
  defp watch_existing_folders(state) do
    Enum.reduce(Path.wildcard(Path.join(state.base_dir, "*")), state, fn folder, state ->
      case owner(folder) do
        {:ok, pid} ->
          if local_process_alive?(pid) do
            watch(state, pid, folder)
          else
            Process.send_after(self(), {:delete, folder}, state.delete_after_ms)
            state
          end

        :unknown ->
          state
      end
    end)
  end

  # {this server's operating-system process id, the page's process}.
  defp owner_contents(page_pid) do
    :erlang.term_to_binary({System.pid(), page_pid})
  end

  # {:ok, page process} if the folder belongs to a page of this running
  # server, else :unknown (another server, an earlier run of this one,
  # or no readable .owner file).
  defp owner(folder) do
    with {:ok, binary} <- File.read(Path.join(folder, @owner_file)),
         {:ok, pid} <- decode_owner(binary) do
      {:ok, pid}
    else
      _ -> :unknown
    end
  end

  # [:safe] refuses anything that would create new atoms or functions;
  # a damaged file just counts as unknown.
  defp decode_owner(binary) do
    os_pid = System.pid()

    case :erlang.binary_to_term(binary, [:safe]) do
      {^os_pid, pid} when is_pid(pid) -> {:ok, pid}
      _other -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp local_process_alive?(pid) do
    node(pid) == node() and Process.alive?(pid)
  end

  # Deletes the folders in base_dir that are older than max_age_seconds
  # and not used by an open page.
  defp sweep(state) do
    in_use = Map.values(state.folders)
    oldest_allowed = System.os_time(:second) - state.max_age_seconds

    for folder <- Path.wildcard(Path.join(state.base_dir, "*")),
        folder not in in_use,
        changed_before?(folder, oldest_allowed) do
      Logger.info("Deleting a leftover photo folder: #{folder}")
      delete_in_background(folder)
    end

    :ok
  end

  defp delete_in_background(folder) do
    Task.start(fn -> File.rm_rf(folder) end)
  end

  # True if `path` was last changed before `time` (seconds since 1970).
  defp changed_before?(path, time) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime < time
      {:error, _reason} -> false
    end
  end
end
