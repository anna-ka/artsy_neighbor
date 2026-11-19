defmodule ArtsyNeighbor.Images.TimingTest do
  @moduledoc """
  The photo timing run (`ArtsyNeighbor.Images.Timing`): it processes
  and stores the photos like real uploads, reports both times, and
  leaves no files behind. Storage is `Storage.Local` in a temporary
  folder (see `config/test.exs`). Small sizes keep it quick.

  Not async: the run goes through the app's one photo limiter (2 photos
  at a time) and reads the server-wide CPU counter, so photos processed
  by other tests at the same moment would make it wait and blur its
  numbers.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias ArtsyNeighbor.Images.Timing
  alias ArtsyNeighbor.Storage.Local

  test "times each photo, prints a summary and deletes what it stored" do
    output =
      capture_io(fn ->
        results = Timing.run(count: 2, long_side: 1000)
        send(self(), {:results, results})
      end)

    assert_received {:results, results}
    assert length(results) == 2

    for result <- results do
      assert {:ok, key} = result.outcome
      assert String.starts_with?(key, "timing/")
      # Enlarged (or shrunk) to 1000 px on the long side first.
      assert max(result.width, result.height) == 1000
      # Processing a real photo takes measurable time and CPU.
      assert result.wall_ms > 0
      assert result.cpu_ms > 0

      assert result.deleted
      refute File.exists?(Local.path_for(key, :public))
      refute File.exists?(Local.path_for(key, :private))
    end

    assert output =~ "Prepared 2 photos using"
    assert output =~ "Done: 2 photos"
    assert output =~ "CPU time per photo"
    # Photo 1 is left out of the numbers to compare.
    assert output =~ "Photo 2, the same photos in every run <- the numbers to compare"
    assert output =~ "All files stored by this run have been deleted again."
  end

  test "refuses options that can't give a useful run" do
    assert_raise ArgumentError, ~r/count must be/, fn -> Timing.run(count: 0) end
    assert_raise ArgumentError, ~r/count must be/, fn -> Timing.run(count: -1) end
    assert_raise ArgumentError, ~r/long_side must be/, fn -> Timing.run(long_side: 600) end
    assert_raise ArgumentError, fn -> Timing.run(cuont: 5) end
  end
end
