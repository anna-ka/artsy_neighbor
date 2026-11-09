defmodule ArtsyNeighbor.Images.Limiter do
  @moduledoc """
  Limits how many photos this machine processes at the same time.

  Processing one photo can take a few hundred MB of memory for a
  second or two (see "Memory" in
  `docs/plans/2026-10-28-image-storage-and-resizing.md`), and the
  server has little memory. So at most `max_concurrent` photos are
  processed at once; the others wait in line for a free **slot**. A
  photo that waits longer than `wait_ms` is given up on, and the
  artist is told the site is busy.

      config :artsy_neighbor, ArtsyNeighbor.Images.Limiter,
        max_concurrent: 2,
        wait_ms: 30_000

  ## How it works

  This is a small server process (a `GenServer`) started with the app.
  It keeps two things: who holds a slot right now, and who is waiting.

    * `run/1` asks the server for a slot and waits for the answer.
      If a slot is free, the answer comes at once. If not, the request
      joins the waiting line, and the server answers later: either
      "here's your slot" when one frees up, or "busy" when the wait
      time is over.
    * When the work is done, `run/1` gives the slot back.
    * The server *monitors* every slot holder: if a holder process
      dies mid-photo (e.g. its page crashed), the server is told and
      frees the slot. So a crash can never use up a slot for good.
  """

  use GenServer

  require Logger

  @default_max_concurrent 2
  @default_wait_ms 30_000

  # --- Public functions ----------------------------------------------

  @doc """
  Starts the limiter. Options (all optional; otherwise read from
  config): `:name`, `:max_concurrent`, `:wait_ms`. Tests start their
  own limiter with a `:name` and small numbers.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Runs `fun` once a slot is free, and returns its result.

  Returns `{:error, :busy}` instead, without running `fun`, if no slot
  freed up within the wait time. `server` is only passed by tests.
  """
  def run(fun, server \\ __MODULE__) do
    # :infinity is safe here: the server always answers, at the latest
    # when the wait time is over (see handle_info({:give_up, ...}) below).
    case GenServer.call(server, :acquire, :infinity) do
      {:ok, slot} ->
        try do
          fun.()
        after
          GenServer.cast(server, {:release, slot})
        end

      :busy ->
        {:error, :busy}
    end
  end

  # --- The server ----------------------------------------------------

  # State:
  #   max_concurrent — how many slots there are;
  #   wait_ms        — how long a request may wait for one;
  #   holders        — %{slot => pid}; the slot is the monitor
  #                    reference, so a :DOWN message tells us directly
  #                    which slot to free;
  #   waiting        — the line, oldest first: a list of
  #                    {from, timer} (from = whom to answer, timer =
  #                    the "give up" timer to cancel when served).
  #                    A plain list is fine: it holds a handful at most.

  @impl true
  def init(opts) do
    config = Application.get_env(:artsy_neighbor, __MODULE__, [])

    state = %{
      max_concurrent:
        Keyword.get(opts, :max_concurrent) ||
          Keyword.get(config, :max_concurrent, @default_max_concurrent),
      wait_ms: Keyword.get(opts, :wait_ms) || Keyword.get(config, :wait_ms, @default_wait_ms),
      holders: %{},
      waiting: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:acquire, {pid, _tag} = from, state) do
    if map_size(state.holders) < state.max_concurrent do
      {slot, state} = give_slot(pid, state)
      {:reply, {:ok, slot}, state}
    else
      # No free slot: join the line, and set a timer to give up.
      # The reply is sent later, by GenServer.reply/2.
      timer = Process.send_after(self(), {:give_up, from}, state.wait_ms)
      {:noreply, %{state | waiting: state.waiting ++ [{from, timer}]}}
    end
  end

  @impl true
  def handle_cast({:release, slot}, state) do
    # :flush drops a :DOWN message for this slot if one is already in
    # our mailbox, so the slot isn't freed twice.
    Process.demonitor(slot, [:flush])
    {:noreply, free_slot(slot, state)}
  end

  @impl true
  # A slot holder died before giving its slot back.
  def handle_info({:DOWN, slot, :process, _pid, _reason}, state) do
    {:noreply, free_slot(slot, state)}
  end

  # A waiting request's time is up. If it's no longer in the line (it
  # got a slot just before its timer fired), there's nothing to do.
  def handle_info({:give_up, from}, state) do
    case List.keytake(state.waiting, from, 0) do
      {{^from, _timer}, rest} ->
        Logger.warning("A photo waited too long for a processing slot; told the artist to retry.")
        GenServer.reply(from, :busy)
        {:noreply, %{state | waiting: rest}}

      nil ->
        {:noreply, state}
    end
  end

  # Gives a slot to `pid`, watching it in case it dies.
  defp give_slot(pid, state) do
    slot = Process.monitor(pid)
    {slot, %{state | holders: Map.put(state.holders, slot, pid)}}
  end

  # Frees `slot` and, if someone is waiting, gives it to the first in
  # line.
  defp free_slot(slot, state) do
    state = %{state | holders: Map.delete(state.holders, slot)}

    case state.waiting do
      [] ->
        state

      [{{pid, _tag} = from, timer} | rest] ->
        Process.cancel_timer(timer)
        {new_slot, state} = give_slot(pid, %{state | waiting: rest})
        GenServer.reply(from, {:ok, new_slot})
        state
    end
  end
end
