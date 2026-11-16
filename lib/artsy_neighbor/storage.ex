defmodule ArtsyNeighbor.Storage do
  @moduledoc """
  Where uploaded image files are kept.

  This module only says *what* a storage backend must be able to do
  (the `@callback`s below, together called a "behaviour") and passes
  each call on to the backend chosen in config:

      config :artsy_neighbor, ArtsyNeighbor.Storage,
        backend: ArtsyNeighbor.Storage.Local

  Today the only backend is `ArtsyNeighbor.Storage.Local` (files on the
  server's own disk). Step c of the image-storage plan adds an S3 one
  for Tigris; the rest of the app won't notice the switch.

  Files are addressed by a **key**, a relative path such as
  `"products/12/0b6c…/thumb.webp"`. Each file is either:

    * `:public` — meant to be shown on the site; has a stable URL;
    * `:private` — only read by our own server (e.g. `source.webp`,
      the copy kept for re-making sizes); never served.

  See `docs/plans/2026-10-28-image-storage-and-resizing.md`.
  """

  @type key :: String.t()
  @type visibility :: :public | :private

  @doc "Copies the file at `local_file` into storage under `key`."
  @callback put(local_file :: Path.t(), key, visibility) :: :ok | {:error, term()}

  @doc "The web address of a public file."
  @callback url(key) :: String.t()

  @doc "Reads a stored file's contents (for the server's own use)."
  @callback read(key, visibility) :: {:ok, binary()} | {:error, term()}

  @doc """
  Deletes everything **inside the folder** `prefix`, public and private:
  every key that starts with `prefix <> "/"`. The slash matters: with
  plain string matching, `"products/1"` would also match
  `"products/10/..."`, and a backend must never do that.

  Deleting something that isn't there is not an error.
  """
  @callback delete_prefix(prefix :: key) :: :ok | {:error, term()}

  def put(local_file, key, visibility) when visibility in [:public, :private] do
    validate_key!(key)
    backend().put(local_file, key, visibility)
  end

  def url(key) do
    validate_key!(key)
    backend().url(key)
  end

  def read(key, visibility) when visibility in [:public, :private] do
    validate_key!(key)
    backend().read(key, visibility)
  end

  @doc """
  Deletes one whole image: everything inside the folder `prefix` (see
  the callback above).

  As a safety net, `prefix` must end in a UUID, i.e. be one image's
  folder such as `"products/12/0b6c5e1a-…"`. A call like
  `delete_prefix("products")` (a bug passing the wrong thing) raises
  instead of deleting every product image.
  """
  def delete_prefix(prefix) do
    validate_key!(prefix)

    if image_folder?(prefix) do
      backend().delete_prefix(prefix)
    else
      raise ArgumentError,
            "delete_prefix only deletes one image's folder (ending in a UUID), " <>
              "got: #{inspect(prefix)}"
    end
  end

  @doc """
  True if `key` is a safe key (see `validate_key!/1`) that ends in a
  UUID, i.e. one image's folder such as `"products/12/0b6c5e1a-…"`.
  Never raises; used to check a value from the database before
  deleting it.
  """
  def image_folder?(key) when is_binary(key) do
    last_part = key |> String.split("/") |> List.last()

    safe_key?(key) and Ecto.UUID.cast(last_part) != :error
  end

  def image_folder?(_not_a_string), do: false

  defp backend do
    config = Application.fetch_env!(:artsy_neighbor, __MODULE__)
    Keyword.fetch!(config, :backend)
  end

  @doc """
  Raises unless `key` is a safe relative path: letters, digits, `-`,
  `_`, `.` and `/` only, not starting with `/`, and no `..` part.

  Our own code builds every key, so this should never fire; it's a
  second line of defence against a key ever pointing outside the
  storage folder (e.g. `"../../config/prod.exs"`).
  """
  def validate_key!(key) when is_binary(key) do
    if safe_key?(key) do
      :ok
    else
      raise ArgumentError, "invalid storage key: #{inspect(key)}"
    end
  end

  # The rules of validate_key!/1, as a true/false answer.
  defp safe_key?(key) do
    parts = String.split(key, "/")

    key != "" and
      String.match?(key, ~r{\A[A-Za-z0-9_\-./]+\z}) and
      not String.starts_with?(key, "/") and
      not Enum.any?(parts, fn part -> part in ["", ".", ".."] end)
  end
end
