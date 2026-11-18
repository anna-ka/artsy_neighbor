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

  @doc """
  Fills the PREVIEW site with the sample artists, works and categories
  (see `ArtsyNeighbor.SampleData`). It only adds, so the admin account
  and anything made by hand stay, and running it twice is safe.

  On Fly (see `docs/deploy.md`):

      fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.add_sample_data()'"

  `rpc`, not `eval`: it runs inside the running site, which has the
  photo limiter and the storage settings the photos need (`eval` starts
  a separate, bare copy of the app). Its progress shows in the
  terminal; it takes a few minutes.

  It refuses to run unless the Fly app's name contains "preview", so
  it can't be run by mistake on a real site: the sample accounts share
  one known password.
  """
  def add_sample_data do
    app_name = System.get_env("FLY_APP_NAME", "")

    if not String.contains?(app_name, "preview") do
      raise "Not adding sample data: this app (#{inspect(app_name)}) is not a preview app."
    end

    ensure_running_site!()
    ArtsyNeighbor.SampleData.add_all()
  end

  @doc """
  Takes the sample data away again (see
  `ArtsyNeighbor.SampleData.remove_all/0`): hard-deletes the sample
  artists with their photos, and locks the sample accounts so their
  published password no longer works. The admin account and the
  categories stay.

      fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.remove_sample_data()'"

  `rpc` for the same reason as `add_sample_data/0`: deleting photo
  files happens in the running site.
  """
  def remove_sample_data do
    ensure_running_site!()
    ArtsyNeighbor.SampleData.remove_all()
  end

  @doc """
  Look-only check to run before a site is shown to anyone beyond the
  developer (testers, the public). For now it checks one thing: that
  no sample data is left (see `ArtsyNeighbor.SampleData.leftovers/0`).
  Prints what it finds; raises if something must be done first.

      fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.check_before_launch()'"
  """
  def check_before_launch do
    ensure_running_site!()

    case ArtsyNeighbor.SampleData.leftovers() do
      [] ->
        IO.puts("OK: no sample data left.")
        :ok

      problems ->
        for problem <- problems, do: IO.puts("  " <> problem)

        raise "NOT READY: sample data is still here. " <>
                "Run ArtsyNeighbor.Release.remove_sample_data() first."
    end
  end

  @doc """
  Times photo processing on this machine (see
  `ArtsyNeighbor.Images.Timing`): processes a series of sample photos,
  enlarged to phone size, as uploads would be; prints each photo's
  wall time and CPU time and a summary; and deletes what it stored.
  Changes nothing else. Options: `count:` (default 20) and
  `long_side:` (default 4032; `nil` = the samples as they are).

      fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.time_photos()'"
      fly ssh console -C "/app/bin/artsy_neighbor rpc 'ArtsyNeighbor.Release.time_photos(count: 40)'"

  `rpc` for the same reason as `add_sample_data/0`. It uses the CPU
  hard for a minute or more, so run it when nobody else is adding
  photos.
  """
  def time_photos(opts \\ []) do
    ensure_running_site!()
    ArtsyNeighbor.Images.Timing.run(opts)
    :ok
  end

  # These commands need the running site (the photo limiter, the
  # background tasks that delete photo files), so they must be run with
  # `rpc`, which runs inside it; `eval` starts a separate, bare copy.
  defp ensure_running_site! do
    if Process.whereis(ArtsyNeighbor.Images.Limiter) == nil do
      raise "The site isn't running here. Use `rpc`, not `eval`."
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
