defmodule ArtsyNeighbor.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :artsy_neighbor

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn started_repo ->
          Ecto.Migrator.run(started_repo, :up, all: true)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn started_repo ->
        Ecto.Migrator.run(started_repo, :down, to: version)
      end)
  end

  @doc """
  Look-only check that this machine's libvips can decode iPhone (HEIC)
  photos. Prints a short report; raises if decoding fails, so a script
  running it stops with an error.

  On Fly (see `docs/tigris.md`):

      fly ssh console -C "/app/bin/artsy_neighbor eval 'ArtsyNeighbor.Release.image_support()'"

  It decodes `priv/image_check/check.heic`, a tiny HEVC-encoded sample
  (made from a test picture, no location data). Decoding the pixels is
  what matters: a libvips without the HEVC decoder can still *open* a
  HEIC file and read its size, and only fails at this point.
  """
  def image_support do
    load_app()
    sample = Application.app_dir(@app, "priv/image_check/check.heic")

    IO.puts("libvips version: #{Vix.Vips.version()}")

    with {:ok, image} <- Image.open(sample),
         {:ok, webp_bytes} <- Image.write(image, :memory, suffix: ".webp") do
      IO.puts("HEIC decode: OK (#{byte_size(webp_bytes)} bytes of WebP)")
      :ok
    else
      {:error, reason} ->
        raise "HEIC decode FAILED: #{inspect(reason)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
