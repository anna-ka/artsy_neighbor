defmodule ArtsyNeighbor.Images.LimiterTest do
  @moduledoc """
  Tests for `ArtsyNeighbor.Images.Limiter`, the limit on how many
  photos are processed at the same time.

  Each test starts its own limiter (with a unique name and small
  numbers), so the app's own limiter, used by other tests, isn't
  touched.

  "Holders" below are helper processes that take a slot and keep it
  until told to finish, so the tests decide exactly when slots free up.
  """
  use ExUnit.Case, async: true

  alias ArtsyNeighbor.Images.Limiter

  defp start_limiter(max_concurrent, wait_ms) do
    name = :"limiter_test_#{System.unique_integer([:positive])}"

    start_supervised!({Limiter, name: name, max_concurrent: max_concurrent, wait_ms: wait_ms})

    name
  end

  # Starts a process that takes a slot (waiting for one if needed),
  # tells the test `{:got_slot, pid}`, and keeps the slot until it is
  # sent `:finish`. It then tells the test `{:finished, pid, result}`.
  defp start_holder(limiter) do
    test_pid = self()

    spawn(fn ->
      result =
        Limiter.run(
          fn ->
            send(test_pid, {:got_slot, self()})

            receive do
              :finish -> :done
            end
          end,
          limiter
        )

      send(test_pid, {:finished, self(), result})
    end)
  end

  test "runs the function and returns its result" do
    limiter = start_limiter(2, 1_000)
    assert Limiter.run(fn -> 6 * 7 end, limiter) == 42
  end

  test "gives the slot back even if the function raises" do
    limiter = start_limiter(1, 100)

    assert_raise RuntimeError, fn ->
      Limiter.run(fn -> raise "boom" end, limiter)
    end

    # If the slot weren't given back, this would wait and get :busy.
    assert Limiter.run(fn -> :ok end, limiter) == :ok
  end

  test "lets at most max_concurrent run at once; the next waits for a free slot" do
    limiter = start_limiter(2, 5_000)

    first = start_holder(limiter)
    second = start_holder(limiter)
    assert_receive {:got_slot, ^first}
    assert_receive {:got_slot, ^second}

    third = start_holder(limiter)
    refute_receive {:got_slot, ^third}, 100

    send(first, :finish)
    assert_receive {:finished, ^first, :done}
    assert_receive {:got_slot, ^third}

    send(second, :finish)
    send(third, :finish)
    assert_receive {:finished, ^second, :done}
    assert_receive {:finished, ^third, :done}
  end

  test "waiting photos get their turn in the order they asked" do
    limiter = start_limiter(1, 5_000)

    holder = start_holder(limiter)
    assert_receive {:got_slot, ^holder}

    early = start_holder(limiter)
    # Make sure `early` is in line before `late` asks.
    Process.sleep(50)
    late = start_holder(limiter)

    send(holder, :finish)
    assert_receive {:got_slot, ^early}
    refute_receive {:got_slot, ^late}, 100

    send(early, :finish)
    assert_receive {:got_slot, ^late}
    send(late, :finish)
  end

  # The limiter logs a warning when it gives up; keep it out of the
  # test output.
  @tag capture_log: true
  test "gives up after wait_ms and returns {:error, :busy} without running the function" do
    limiter = start_limiter(1, 100)

    holder = start_holder(limiter)
    assert_receive {:got_slot, ^holder}

    assert Limiter.run(fn -> flunk("should not run") end, limiter) == {:error, :busy}

    send(holder, :finish)
  end

  test "frees the slot when the process holding it dies" do
    limiter = start_limiter(1, 5_000)

    holder = start_holder(limiter)
    assert_receive {:got_slot, ^holder}

    waiter = start_holder(limiter)
    refute_receive {:got_slot, ^waiter}, 100

    # E.g. the page processing the photo crashed.
    Process.exit(holder, :kill)
    assert_receive {:got_slot, ^waiter}

    send(waiter, :finish)
  end
end
