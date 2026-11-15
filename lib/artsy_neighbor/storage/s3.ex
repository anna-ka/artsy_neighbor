defmodule ArtsyNeighbor.Storage.S3 do
  @moduledoc """
  Storage backend for S3-compatible object storage; we use Tigris on
  Fly (see `docs/tigris.md`).

  Two buckets, kept apart on purpose:

    * the **public** bucket holds the display sizes (`thumb.webp`,
      `medium.webp`, `large.webp`); browsers load them straight from
      Tigris at `<public_base_url>/<key>`;
    * the **private** bucket holds `source.webp` (the copy kept for
      re-making sizes); only our server, signing in with its key, can
      read it.

  Config (set in `config/runtime.exs` from environment variables):

      config :artsy_neighbor, ArtsyNeighbor.Storage.S3,
        public_bucket: "an-preview-photos",
        private_bucket: "an-preview-originals",
        public_base_url: "https://an-preview-photos.t3.tigrisfiles.io",
        ex_aws: [...]

  `ex_aws` is optional: settings passed on to every `ExAws.request/2`
  (tests use it to swap in a fake S3, see `ArtsyNeighbor.FakeS3`).
  The endpoint and the key are ex_aws's own config (`:ex_aws, :s3`).
  """

  @behaviour ArtsyNeighbor.Storage

  # Every photo has its own UUID folder and its files are never changed
  # in place (a new photo gets a new folder), so browsers and Tigris'
  # caches may keep public files for a year without asking again.
  @public_cache_control "public, max-age=31536000, immutable"

  @impl true
  def put(local_file, key, visibility) do
    with {:ok, contents} <- File.read(local_file) do
      options = [content_type: content_type(key)] ++ cache_options(visibility)

      bucket(visibility)
      |> ExAws.S3.put_object(key, contents, options)
      |> request()
      |> only_ok()
    end
  end

  @impl true
  def url(key), do: config!(:public_base_url) <> "/" <> key

  @impl true
  def read(key, visibility) do
    case request(ExAws.S3.get_object(bucket(visibility), key)) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _response}} -> {:error, :enoent}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  # S3 has no real folders: "inside the folder" means every key that
  # starts with `prefix <> "/"`. List those keys in each bucket, then
  # delete them. Deleting keys that aren't there is not an error.
  def delete_prefix(prefix) do
    folder = prefix <> "/"

    with :ok <- delete_all_under(bucket(:public), folder) do
      delete_all_under(bucket(:private), folder)
    end
  end

  defp delete_all_under(bucket, folder) do
    case list_keys(bucket, folder) do
      {:ok, []} ->
        :ok

      {:ok, keys} ->
        bucket
        |> ExAws.S3.delete_multiple_objects(keys)
        |> request()
        |> only_ok()

      {:error, reason} ->
        {:error, reason}
    end
  end

  # One image folder holds only a handful of files, far below S3's
  # 1000 keys per listing, so a single listing is enough. If S3 ever
  # says the list was cut short, we refuse instead of half-deleting.
  defp list_keys(bucket, folder) do
    case request(ExAws.S3.list_objects_v2(bucket, prefix: folder)) do
      {:ok, %{body: %{is_truncated: "true"}}} ->
        {:error, {:too_many_files, folder}}

      {:ok, %{body: %{contents: contents}}} ->
        keys = Enum.map(contents, fn object -> object.key end)
        {:ok, keys}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(operation) do
    ExAws.request(operation, Keyword.get(config(), :ex_aws, []))
  end

  defp only_ok({:ok, _response}), do: :ok
  defp only_ok({:error, reason}), do: {:error, reason}

  defp bucket(:public), do: config!(:public_bucket)
  defp bucket(:private), do: config!(:private_bucket)

  defp cache_options(:public), do: [cache_control: @public_cache_control]
  defp cache_options(:private), do: []

  # All our stored files are WebP today; anything else gets the generic
  # "some bytes" type rather than a wrong guess.
  defp content_type(key) do
    if String.ends_with?(key, ".webp"), do: "image/webp", else: "application/octet-stream"
  end

  defp config!(name), do: Keyword.fetch!(config(), name)

  defp config, do: Application.get_env(:artsy_neighbor, __MODULE__, [])
end
