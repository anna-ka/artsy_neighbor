defmodule ArtsyNeighbor.Storage.Local do
  @moduledoc """
  Storage backend that keeps files on the server's own disk (dev, and
  the private preview until step c moves files to Tigris).

    * public files: `priv/static/uploads/<key>`, served by Phoenix at
      `/uploads/<key>`;
    * private files: `priv/private_uploads/<key>`, never served.

  Tests point both folders somewhere temporary (`config/test.exs`):

      config :artsy_neighbor, ArtsyNeighbor.Storage.Local,
        public_dir: "...", private_dir: "..."
  """

  @behaviour ArtsyNeighbor.Storage

  @impl true
  def put(local_file, key, visibility) do
    destination = path_for(key, visibility)

    with :ok <- File.mkdir_p(Path.dirname(destination)) do
      File.cp(local_file, destination)
    end
  end

  @impl true
  def url(key), do: "/uploads/" <> key

  @impl true
  def read(key, visibility), do: File.read(path_for(key, visibility))

  @impl true
  # On disk a key prefix is a real folder, so removing that folder
  # deletes exactly the keys starting with `prefix <> "/"`.
  def delete_prefix(prefix) do
    public_result = File.rm_rf(Path.join(public_dir(), prefix))
    private_result = File.rm_rf(Path.join(private_dir(), prefix))

    case {public_result, private_result} do
      {{:ok, _}, {:ok, _}} -> :ok
      {{:error, reason, path}, _} -> {:error, {reason, path}}
      {_, {:error, reason, path}} -> {:error, {reason, path}}
    end
  end

  @doc "Where a file lives on disk (used by tests too)."
  def path_for(key, :public), do: Path.join(public_dir(), key)
  def path_for(key, :private), do: Path.join(private_dir(), key)

  # The defaults are looked up when called, not at compile time:
  # `Application.app_dir/2` points into the running build, which is
  # also right inside a release.
  defp public_dir do
    config()[:public_dir] || Application.app_dir(:artsy_neighbor, "priv/static/uploads")
  end

  defp private_dir do
    config()[:private_dir] || Application.app_dir(:artsy_neighbor, "priv/private_uploads")
  end

  defp config, do: Application.get_env(:artsy_neighbor, __MODULE__, [])
end
