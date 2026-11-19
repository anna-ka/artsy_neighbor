defmodule ArtsyNeighbor.Images.Timing do
  @moduledoc """
  Measures how long photo processing takes on this machine, for the
  photo speed work (`NOTES.md`, step 2). It processes a series of
  sample photos exactly as an upload would (`Images.process_upload/3`,
  limiter and storage included), one after another like an artist
  adding many photos, and prints the time each one took. Each photo's
  files are deleted again right after it's measured.

  Run it through `ArtsyNeighbor.Release.time_photos/1` (on Fly) or
  `run/1` (on the Mac, in `iex -S mix`).

  ## Two times per photo

    * **wall time** — how long the photo took from start to stored,
      i.e. what an artist waits. On Fly's shared CPU this grows once
      the CPU's burst allowance is used up, and it includes storing
      on Tigris, which is waiting for the network, not work.
    * **CPU time** — the work the machine did: every thread of the
      server, libvips' own threads included (`:erlang.statistics(:runtime)`
      counts them all, checked 2026-11-17). It's the number for
      comparing before and after a change, and for working out how
      many photos an hour a machine can take, **but only for photos
      that ran at full speed**.

  ## Comparing runs: photos 2–8

  On Fly, photos slowed down by the shared CPU's limit show *more* CPU
  time than they used, most likely because the server can't tell when
  Fly pauses its CPU and counts part of the pause as work: ~6.5 s
  instead of ~3.9 s when heavily slowed down (2026-11-17), and 3.5–4.7 s
  instead of ~1.5 s when mildly slowed down (2026-11-19). Mild slowing
  down can't be told apart from a slow photo, so the summary doesn't
  guess which photos ran at full speed. It reports **photos 2–8**
  instead: the same photos in every run (as long as the sample data
  doesn't change), early enough to usually run before the burst
  allowance is used up. Photo 1 is left out because the first photo
  of a run is always slower. On Fly, run it on a Machine that has been
  idle for a while, so the allowance has built up. If photos 2–8 were
  clearly slowed down (wall time over twice the CPU time), the summary
  says so: run again later.

  The CPU time is the whole server's, so it also counts, besides the
  photo itself:

    * anything else the server does at the same moment, so run it
      when the site is quiet;
    * the Erlang schedulers' short "busy waiting" when they run out of
      work (they keep the CPU for a moment in case new work comes).
      This adds a little to each photo, about the same before and
      after a change, so comparisons still hold; the "photos an hour"
      estimate is, if anything, on the low side.

  ## Phone-sized photos

  The sample photos are small (mostly about 1 MP), while a phone saves
  12 MP or more, and the cost grows with the pixels. So by default each
  sample is first enlarged to 4032 px on the long side (an iPhone photo
  is 4032×3024) and saved as a JPEG, like a phone would. An enlarged
  photo has less fine detail than a real one and encodes a little
  faster, so the times are, if anything, on the low side.

  This preparation happens before the timing starts and isn't counted
  in the photos' times, but it does use the CPU: on Fly's shared CPU
  it uses up part of the burst allowance (a Machine that has just
  started has only a few seconds of it). So the run prints how much
  CPU the preparation took, and the first photos' wall times may
  already be slowed down.
  """

  require Logger

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.SampleData
  alias ArtsyNeighbor.Storage

  @default_count 20
  @default_long_side 4032

  # The same minimum as in Images (smaller photos are refused as "too
  # small"), so a run can't consist of nothing but refusals.
  @min_long_side 800

  # The storage folder the photos go into; each photo gets its own
  # folder inside it, as usual (`"timing/<uuid>"`).
  @folder "timing"

  @doc """
  Times a series of photos. Options:

    * `:count` — how many photos (default #{@default_count}); if there
      are fewer sample photos, it starts over from the first;
    * `:long_side` — enlarge each sample photo to this many pixels on
      its long side first (default #{@default_long_side}, at least
      #{@min_long_side}); `nil` uses the samples as they are.

  Prints a line per photo and a summary, and returns the results as a
  list of maps (used by the tests). Raises `ArgumentError` for an
  unknown option or a value out of range.
  """
  def run(opts \\ []) do
    {count, long_side} = read_options!(opts)

    run_id = Ecto.UUID.generate()
    work_dir = Path.join(System.tmp_dir!(), "artsy_neighbor_timing_" <> run_id)
    File.mkdir_p!(work_dir)

    try do
      IO.puts("Preparing the photos (#{size_text(long_side)})...")

      {prepare_cpu_ms, prepared} =
        cpu_timed(fn -> prepare_photos(count, long_side, work_dir) end)

      IO.puts(
        "Prepared #{length(prepared)} photos using #{prepare_cpu_ms} ms of CPU " <>
          "(not counted below, but on a shared CPU it uses part of the burst allowance)."
      )

      # Starts over from the first prepared photo if `count` is bigger
      # than the number of samples.
      photos = prepared |> Stream.cycle() |> Enum.take(count)

      IO.puts("Timing #{count} photos one after another:")
      results = time_each(photos)

      print_summary(results)
      results
    after
      File.rm_rf(work_dir)
    end
  end

  defp read_options!(opts) do
    opts = Keyword.validate!(opts, count: @default_count, long_side: @default_long_side)
    count = Keyword.fetch!(opts, :count)
    long_side = Keyword.fetch!(opts, :long_side)

    if not (is_integer(count) and count >= 1) do
      raise ArgumentError, "count must be a whole number of at least 1, got: #{inspect(count)}"
    end

    if not (is_nil(long_side) or (is_integer(long_side) and long_side >= @min_long_side)) do
      raise ArgumentError,
            "long_side must be nil or a whole number of at least #{@min_long_side}, " <>
              "got: #{inspect(long_side)}"
    end

    {count, long_side}
  end

  # --- Preparing the photos ------------------------------------------

  # Prepares each sample photo the run needs once (at most `count`):
  # returns [%{name: "seed/demo/maren/shore-2.jpg", path: local_file}, ...].
  defp prepare_photos(count, long_side, work_dir) do
    sample_photo_files()
    |> Enum.take(count)
    |> Enum.with_index(1)
    |> Enum.map(fn {sample, number} ->
      prepare_photo(sample, number, long_side, work_dir)
    end)
  end

  # Every photo file of the sample data, once each (the older seed
  # artists share some files), as {name, file path}. The newer demo
  # artists and the studio come first: their photos are real artworks
  # of varied sizes, the older seed images are mostly portraits.
  defp sample_photo_files do
    entries = SampleData.all_artist_entries()
    {older, newer} = Enum.split_with(entries, fn entry -> entry.photo_dir == "images" end)

    files =
      for entry <- newer ++ older, photo <- SampleData.photos_of(entry) do
        name = String.replace_prefix(Path.join(entry.photo_dir, photo), "images/", "")
        {name, SampleData.photo_file(entry.photo_dir, photo)}
      end

    Enum.uniq_by(files, fn {_name, file} -> file end)
  end

  defp prepare_photo({name, file}, _number, nil, _work_dir) do
    %{name: name, path: file}
  end

  defp prepare_photo({name, file}, number, long_side, work_dir) do
    # Numbered, because two samples in different folders can have the
    # same file name.
    enlarged_path = Path.join(work_dir, "#{number}.jpg")

    with {:ok, image} <- Image.open(file),
         {:ok, enlarged} <- Image.thumbnail(image, long_side, resize: :both),
         {:ok, _} <- Image.write(enlarged, enlarged_path, quality: 90) do
      %{name: name, path: enlarged_path}
    else
      {:error, reason} -> raise "Couldn't prepare #{name}: #{inspect(reason)}"
    end
  end

  # --- Timing --------------------------------------------------------

  defp time_each(photos) do
    total = length(photos)

    photos
    |> Enum.with_index(1)
    |> Enum.map(fn {photo, number} ->
      result = time_one(photo)
      IO.puts("  #{number}/#{total}  " <> result_line(result))
      result
    end)
  end

  # Processes one photo, then deletes its stored files straight away
  # (after the clock has stopped), so a run that is interrupted leaves
  # at most one photo's folder behind.
  defp time_one(photo) do
    {width, height} = dimensions(photo.path)

    started_at = System.monotonic_time(:millisecond)

    {cpu_ms, upload_result} =
      cpu_timed(fn -> Images.process_upload_with_timings(photo.path, photo.name, @folder) end)

    wall_ms = System.monotonic_time(:millisecond) - started_at

    # `storing_ms` is the part of the wall time spent writing the files
    # to storage, i.e. mostly waiting for the network (nil if it failed).
    {outcome, storing_ms, deleted} =
      case upload_result do
        {:ok, key, timings} -> {{:ok, key}, timings.storing_ms, delete_folder(key)}
        {:error, message} -> {{:error, message}, nil, true}
      end

    %{
      name: photo.name,
      width: width,
      height: height,
      wall_ms: wall_ms,
      cpu_ms: cpu_ms,
      storing_ms: storing_ms,
      outcome: outcome,
      deleted: deleted
    }
  end

  # Runs `fun` and returns {CPU milliseconds the whole server used
  # meanwhile, its result}. Uses the running total of
  # :erlang.statistics(:runtime), not its "since the last call" part:
  # that part is shared by the whole server, so anything else asking
  # for it (e.g. a monitoring page) would reset it mid-measurement.
  defp cpu_timed(fun) do
    {total_before, _since_last_call} = :erlang.statistics(:runtime)
    result = fun.()
    {total_after, _since_last_call} = :erlang.statistics(:runtime)
    {total_after - total_before, result}
  end

  defp dimensions(path) do
    case Image.open(path) do
      {:ok, image} -> {Image.width(image), Image.height(image)}
      {:error, _} -> {0, 0}
    end
  end

  # Returns true if the folder is gone. Never raises: a failed delete
  # mustn't stop the run; the summary lists what's left.
  defp delete_folder(key) do
    Storage.delete_prefix(key) == :ok
  rescue
    error ->
      Logger.error("Photo timing: deleting #{key} raised: #{Exception.message(error)}")
      false
  end

  # --- Printing ------------------------------------------------------

  defp result_line(result) do
    base =
      "#{result.name}  #{result.width}×#{result.height}  " <>
        "wall #{result.wall_ms} ms  CPU #{result.cpu_ms} ms"

    case result.outcome do
      {:ok, _key} -> base <> "  (storing #{result.storing_ms} ms)"
      {:error, message} -> base <> "  FAILED: " <> message
    end
  end

  defp print_summary(results) do
    stored = Enum.filter(results, fn result -> match?({:ok, _key}, result.outcome) end)
    failed_count = length(results) - length(stored)
    total_wall_s = Float.round(sum_of(results, :wall_ms) / 1000, 1)

    IO.puts("")
    IO.puts("Done: #{length(results)} photos in #{total_wall_s} s.")

    if failed_count > 0 do
      IO.puts("  #{failed_count} failed (see above); they're left out below.")
    end

    if stored != [] do
      print_averages(stored)
      print_comparison(results)
    end

    print_cleanup(stored)
  end

  defp print_averages(stored) do
    first = Enum.take(stored, 5)
    last = Enum.take(stored, -5)

    IO.puts(
      "  Wall time per photo: average #{average_of(stored, :wall_ms)} ms " <>
        "(first 5: #{average_of(first, :wall_ms)} ms, last 5: #{average_of(last, :wall_ms)} ms)"
    )

    IO.puts(
      "  CPU time per photo:  average #{average_of(stored, :cpu_ms)} ms " <>
        "(first 5: #{average_of(first, :cpu_ms)} ms, last 5: #{average_of(last, :cpu_ms)} ms)"
    )
  end

  # The numbers to compare between runs: photos 2–8 (see the moduledoc).
  # A shorter run uses what it has: photos 2 onwards, or photo 1 alone.
  defp print_comparison(results) do
    {label, picked} =
      cond do
        length(results) >= 8 -> {"Photos 2–8", Enum.slice(results, 1..7)}
        length(results) >= 3 -> {"Photos 2–#{length(results)}", Enum.drop(results, 1)}
        length(results) == 2 -> {"Photo 2", Enum.drop(results, 1)}
        true -> {"Photo 1", results}
      end

    compared = Enum.filter(picked, fn result -> match?({:ok, _key}, result.outcome) end)

    if compared != [] do
      cpu_ms = average_of(compared, :cpu_ms)
      wall_ms = average_of(compared, :wall_ms)

      IO.puts("")
      IO.puts("  #{label}, the same photos in every run <- the numbers to compare:")
      IO.puts("    CPU time: average #{cpu_ms} ms; wall time: average #{wall_ms} ms")

      IO.puts(
        "    (" <>
          Enum.map_join(compared, ", ", fn result -> Path.basename(result.name) end) <> ")"
      )

      if cpu_ms > 0 do
        IO.puts(
          "    At that CPU time, one full CPU core can process about " <>
            "#{div(3_600_000, cpu_ms)} photos an hour."
        )
      end

      if wall_ms > 2 * cpu_ms do
        IO.puts(
          "    WARNING: these photos were slowed down (wall time over twice the CPU " <>
            "time), so their CPU time is too high. Run again after the Machine has " <>
            "been idle for a while."
        )
      end
    end
  end

  defp print_cleanup(stored) do
    not_deleted =
      for %{outcome: {:ok, key}, deleted: false} <- stored do
        key
      end

    if not_deleted == [] do
      IO.puts("All files stored by this run have been deleted again.")
    else
      IO.puts("Couldn't delete these folders, please delete them by hand:")

      for key <- not_deleted do
        IO.puts("  " <> key)
      end
    end
  end

  defp sum_of(results, field) do
    results
    |> Enum.map(fn result -> Map.fetch!(result, field) end)
    |> Enum.sum()
  end

  defp average_of(results, field) do
    div(sum_of(results, field), length(results))
  end

  defp size_text(nil), do: "the sample photos as they are"
  defp size_text(long_side), do: "enlarged to #{long_side} px on the long side"
end
