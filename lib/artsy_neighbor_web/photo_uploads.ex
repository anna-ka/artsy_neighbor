defmodule ArtsyNeighborWeb.PhotoUploads do
  @moduledoc """
  Photo uploading shared by the four forms that take photos (vendor
  product form, vendor profile form, admin product form, admin artist
  form).

  ## The life of a picked photo

  1. **Uploading.** The photo is sent to the server as soon as it's
     picked (`auto_upload`), with a progress bar. (Big photos are first
     shrunk in the browser, see below.)
  2. **"Checking the photo…"** As soon as it has arrived, the server
     checks it and makes the files we keep (`Images.prepare_upload/4`)
     in the background, into a temporary folder for this page
     (`ArtsyNeighbor.Images.PreparedFolders`), **not into storage yet**.
     One photo at a time per page, each taking a slot in
     `ArtsyNeighbor.Images.Limiter`. The artist meanwhile fills in the
     rest of the form. A big photo (`Images.big_photo?/3`) says "Large
     photo — this one takes a little longer…" instead, and a moving
     image (or a TIFF with several pages) gets a note that only its
     first picture will be shown (NOTES #43, #44).
  3. **"Ready ✓"**, or the problem in red: a photo that can't be used
     (too small, not a photo, ...) says so and has to be removed with
     ✕; a problem on our side (the site was busy, ...) gets a **Try
     again** button.
  4. **Save.** The form saves its text fields, then calls
     `start_processing/5`. That only **stores** the ready photos and
     makes their database rows (the form's `create_row` function), in a
     background task (LiveView's `start_async/3`), which is quick. If a
     photo is still being checked, Save waits for it by itself
     ("Saving your photos…" meanwhile), so the artist presses only
     once; photos with a problem on our side are tried once more.
  5. When the task is done, LiveView calls the form's
     `handle_async(:process_photos, result, socket)`, which calls
     `finish_processing/3` here. Each stored photo leaves the upload
     box; one that couldn't be used **stays in the upload box** with
     its message, so the artist can see what went wrong. Then the form
     decides where to go next: on as usual if all went well, or stay on
     the page if a photo was refused.

  The photo stays in LiveView's own upload list the whole time (it's
  taken with `{:postpone, ...}`, which leaves it there and only tells us
  where its file is), so previews, ✕ and the 5-photo limit work as
  LiveView does them. This module only adds a status per photo
  (`:photo_prep`). It catches the "upload finished" (the `progress:`
  callback) and "photo checked" (an `attach_hook/4` on `:handle_async`)
  signals itself, so the forms don't need to.

  Why the background: the browser waits at most 30 seconds for the
  answer to a button press and then reloads the page. Why the row is
  made in the task, straight after the files: if the page closes in
  between, stored files with no row pointing to them would be left
  behind, and nothing would ever clean them up.

  Plan: "3b" in `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`.

  ## Assigns this module adds to a form's socket

    * `:photo_prep` — `%{entry_ref => photo}`, one per uploaded photo,
      where `photo` is `%{name: file name, upload_path: its uploaded file,
      big: big photo?, pictures: :one | :moving_image | :several_pages,
      status: status}` (`big` and `pictures` are known once checking has
      started, false until then), and `status` is `:queued` (waiting for this
      page's turn), `:checking`, `{:ready, prepared}`, `{:refused,
      message}` (the photo can't be used), `{:failed, message}` (a
      problem on our side; can be tried again), `:stored` (stored by a
      save still under way) or `:removed` (removed with ✕ while being
      checked; gone once its task has ended);
    * `:photo_checking` — the ref of the photo being checked right now,
      or `nil` (also kept for a photo removed while being checked, so
      the next one waits until it's done);
    * `:photo_folder` — this page's temporary folder, made at the first
      photo;
    * `:pending_save` — set while a save waits for photos still being
      checked: what to store where;
    * `:photo_errors` — `%{entry_ref => message}` for photos picked
      while the others were being saved (rare; see finish_processing/3);
    * `:photo_problem` — a summary sentence shown in red next to the
      save button(s), or `nil`;
    * `:saving_photos` — true while a save stores photos or waits for
      them. The file picker, the ✕ buttons and the buttons of the
      stored photos are disabled meanwhile, and the forms ignore save
      presses;
    * `:photos_preparing` — true while the browser is still shrinking
      picked photos (see below). A save then waits, as it does for
      photos still uploading;
    * `:refused_in_browser` — names of photos the browser refused
      without uploading (over the size limit), whose red rows are still
      shown. A save then stays on the page and says why, until the
      artist removes them with ✕;
    * `:problem_from_browser` — true when `:photo_problem` was set for
      one of the two reasons above, so it can be cleared as soon as the
      browser's state changes.

  ## Shrinking in the browser

  Before a photo is uploaded, the picker's browser code
  (`assets/js/photo_shrink.js`, the `PhotoShrink` hook) shrinks photos
  bigger than the private copy we keep (`Images.source_max_side/0`) to
  a JPEG of that size, so big phone photos upload faster and cost the
  server less. It's only a shortcut: whatever it can't shrink, it
  uploads as it is, and the server checks and processes every photo
  the same way either way. It keeps the server informed (the
  `"photo_picker_state"` event: still preparing? which photos were
  refused?), handled here through `attach_hook/4`, so the forms don't
  need to.
  """

  use Phoenix.Component

  import Phoenix.LiveView,
    only: [
      allow_upload: 3,
      attach_hook: 4,
      cancel_async: 3,
      cancel_upload: 3,
      consume_uploaded_entry: 3,
      start_async: 3,
      uploaded_entries: 2
    ]

  require Logger

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Images.PreparedFolders
  alias ArtsyNeighbor.Storage

  # Everything is converted to WebP on our side, so the uploaded format
  # doesn't matter after processing. See the plan doc for why GIF,
  # camera RAW, SVG, PDF and BMP are not accepted.
  @accept ~w(.jpg .jpeg .png .webp .heic .heif .tif .tiff .avif)

  # Phone photos are big; we shrink them anyway.
  @max_file_size 25_000_000
  @max_entries 5

  # How long a photo checked on pick may wait for a free Limiter slot.
  # Longer than the Limiter's usual 30 s: no button press is waiting for
  # an answer here. Can be set in config (the tests make it short):
  #   config :artsy_neighbor, ArtsyNeighborWeb.PhotoUploads, prepare_wait_ms: 180_000
  @default_prepare_wait_ms 180_000

  # Formats most browsers can show as a preview before upload. HEIC and
  # TIFF usually can't be shown, so they get a plain placeholder instead
  # of a broken image.
  @previewable ~w(.jpg .jpeg .png .webp .avif)

  @msg_save_failed "Something went wrong while saving this photo. Please try again."
  @msg_picked_late "This photo was picked while the others were being saved, so it " <>
                     "isn't saved yet. Please save again to add it."
  @msg_preparing "Your photos are still being prepared. Please wait until they show a bar, " <>
                   "then save again."

  # Limits on what the browser may tell us about refused photos: the
  # message comes from the visitor's browser, so it can't be trusted.
  @max_refused_names 20
  @max_name_length 255

  @doc """
  Sets up the upload slot `name` (e.g. `:images`) and this module's
  assigns. Call it in `mount/3`. `opts` are passed on to
  `Phoenix.LiveView.allow_upload/3` and override the defaults below.
  """
  def allow_photos(socket, name, opts \\ []) do
    upload_opts =
      Keyword.merge(
        [
          accept: @accept,
          max_entries: @max_entries,
          max_file_size: @max_file_size,
          # Send each photo to the server as soon as it's picked, not
          # only when the form is saved: the photo sections sit near the
          # top of the forms, so the sending happens while the artist
          # fills in the rest.
          auto_upload: true,
          # Called as each photo's upload goes on; we start checking the
          # photo when it's done.
          progress: fn upload_name, entry, socket ->
            handle_progress(upload_name, entry, socket)
          end
        ],
        opts
      )

    socket
    |> allow_upload(name, upload_opts)
    |> assign(
      photo_prep: %{},
      photo_checking: nil,
      photo_folder: nil,
      pending_save: nil,
      photos_in_progress: [],
      photo_errors: %{},
      photo_problem: nil,
      saving_photos: false,
      photos_preparing: false,
      refused_in_browser: [],
      problem_from_browser: false
    )
    |> attach_hook(:photo_picker_events, :handle_event, fn event, params, socket ->
      handle_picker_event(name, event, params, socket)
    end)
    |> attach_hook(:photo_checked, :handle_async, fn key, result, socket ->
      handle_photo_checked(key, result, socket)
    end)
    |> attach_hook(:photo_stored, :handle_info, fn message, socket ->
      handle_photo_stored(message, socket)
    end)
    |> attach_hook(:photo_header, :handle_info, fn message, socket ->
      handle_photo_header(message, socket)
    end)
  end

  # --- Events from the page --------------------------------------------
  #
  # Each is always handled here ({:halt, ...}), whatever its contents,
  # so a malformed one can't reach the form (which has no clause for
  # it). Every other event goes on to the form ({:cont, ...}).

  # The browser's PhotoShrink hook sends its state whenever it changes:
  # %{"preparing" => true/false, "refused" => [file names]}.
  defp handle_picker_event(_name, "photo_picker_state", params, socket) do
    socket =
      socket
      |> assign(:photos_preparing, params["preparing"] == true)
      |> assign(:refused_in_browser, refused_names(params["refused"]))
      |> clear_browser_problem()

    {:halt, socket}
  end

  # The "Try again" button of a photo that failed on our side. It tries
  # every such photo again, not just the one whose button was pressed:
  # when one fails on our side (e.g. the site was busy), the photos
  # waiting after it are given the same message without being tried
  # (see handle_photo_checked/3), so they all need another go.
  defp handle_picker_event(name, "retry_photo", _params, socket) do
    if socket.assigns.saving_photos do
      {:halt, socket}
    else
      socket =
        socket
        |> queue_failed_again(Map.keys(socket.assigns.photo_prep))
        |> check_next_photo(name)

      {:halt, socket}
    end
  end

  defp handle_picker_event(_name, _event, _params, socket), do: {:cont, socket}

  # Only strings, a limited number, each of limited length.
  defp refused_names(names) when is_list(names) do
    names
    |> Enum.filter(fn name -> is_binary(name) end)
    |> Enum.take(@max_refused_names)
    |> Enum.map(fn name -> String.slice(name, 0, @max_name_length) end)
  end

  defp refused_names(_not_a_list), do: []

  # A message about the browser's state ("still being prepared", "not
  # uploaded") is out of date once that state changes: the artist
  # simply saves again.
  defp clear_browser_problem(%{assigns: %{problem_from_browser: true}} = socket) do
    assign(socket, photo_problem: nil, problem_from_browser: false)
  end

  defp clear_browser_problem(socket), do: socket

  # --- Checking each photo as soon as it has arrived -------------------

  # LiveView calls this as a photo's upload goes on. Once it's done, we
  # take note of where its file is ({:postpone, ...} keeps the photo in
  # the upload box and its file on disk) and queue it for checking.
  defp handle_progress(name, entry, socket) do
    if entry.done? and not Map.has_key?(socket.assigns.photo_prep, entry.ref) do
      socket =
        socket
        |> add_photo(entry)
        |> check_next_photo(name)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp add_photo(socket, entry) do
    path = consume_uploaded_entry(socket, entry, fn %{path: path} -> {:postpone, path} end)

    photo = %{
      name: entry.client_name,
      upload_path: path,
      big: false,
      pictures: :one,
      status: :queued
    }

    assign(socket, :photo_prep, Map.put(socket.assigns.photo_prep, entry.ref, photo))
  end

  # Where the photo's files are being made, so they can be deleted if
  # the photo is removed while it's being checked.
  defp put_work_dir(socket, ref, work_dir) do
    photo_prep =
      Map.update!(socket.assigns.photo_prep, ref, fn photo ->
        Map.put(photo, :work_dir, work_dir)
      end)

    assign(socket, :photo_prep, photo_prep)
  end

  defp put_status(socket, ref, status) do
    photo_prep =
      Map.update!(socket.assigns.photo_prep, ref, fn photo -> %{photo | status: status} end)

    assign(socket, :photo_prep, photo_prep)
  end

  # Starts checking the next queued photo (in the order they're listed),
  # unless one is being checked already: one at a time per page. When
  # nothing is left to check and a save is waiting, the save goes on.
  #
  # While a save waits, only its own photos are checked: a photo picked
  # after Save mustn't hold it up. (It's checked once the save is done,
  # see finish_processing/3.)
  defp check_next_photo(%{assigns: %{photo_checking: ref}} = socket, _name) when ref != nil do
    socket
  end

  defp check_next_photo(socket, name) do
    candidate_refs =
      case socket.assigns.pending_save do
        nil -> Enum.map(socket.assigns.uploads[name].entries, fn entry -> entry.ref end)
        pending -> pending.refs
      end

    queued_ref =
      Enum.find(candidate_refs, fn ref ->
        match?(%{status: :queued}, socket.assigns.photo_prep[ref])
      end)

    if queued_ref do
      start_checking(socket, name, queued_ref)
    else
      continue_waiting_save(socket)
    end
  end

  defp start_checking(socket, name, ref) do
    case page_folder(socket) do
      {:ok, socket, page_folder} ->
        photo = socket.assigns.photo_prep[ref]
        work_dir = Path.join(page_folder, Ecto.UUID.generate())
        wait_ms = prepare_wait_ms()
        page = self()

        # Called by prepare_upload/4 in the background task as soon as
        # it has read the photo's header, before the photo waits for its
        # turn: tells this page whether it's big, and how many pictures it holds
        # (handle_photo_header/2).
        on_header = fn header_info -> send(page, {:photo_header, ref, header_info}) end

        socket
        |> put_status(ref, :checking)
        |> put_work_dir(ref, work_dir)
        |> assign(:photo_checking, ref)
        |> start_async({:check_photo, name, ref}, fn ->
          Images.prepare_upload(photo.upload_path, photo.name, work_dir,
            wait_ms: wait_ms,
            on_header: on_header
          )
        end)

      {:error, socket} ->
        socket
        |> put_status(ref, {:failed, @msg_save_failed})
        |> check_next_photo(name)
    end
  end

  # This page's temporary folder, made the first time it's needed.
  defp page_folder(%{assigns: %{photo_folder: folder}} = socket) when folder != nil do
    {:ok, socket, folder}
  end

  defp page_folder(socket) do
    case PreparedFolders.page_folder(self()) do
      {:ok, folder} -> {:ok, assign(socket, :photo_folder, folder), folder}
      {:error, _reason} -> {:error, socket}
    end
  end

  defp prepare_wait_ms do
    :artsy_neighbor
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:prepare_wait_ms, @default_prepare_wait_ms)
  end

  # A photo has been checked (the background task started in
  # start_checking/3 is done). Other async results go on to the form.
  defp handle_photo_checked({:check_photo, name, ref}, result, socket) do
    status =
      case result do
        {:ok, {:ok, prepared}} ->
          {:ready, prepared}

        {:ok, {:error, {:refused, message}}} ->
          {:refused, message}

        {:ok, {:error, {:failed, message}}} ->
          {:failed, message}

        # Stopped by cancel_photo/3: not a crash.
        {:exit, {:shutdown, :photo_removed}} ->
          :stopped

        {:exit, reason} ->
          Logger.error("Checking photo #{inspect(ref)} crashed: #{inspect(reason)}")
          {:failed, @msg_save_failed}
      end

    socket = assign(socket, :photo_checking, nil)

    socket =
      case socket.assigns.photo_prep[ref] do
        # Removed with ✕ while it was being checked (cancel_photo/3). Its
        # task has ended now, so nothing more can be written into its
        # folder: delete it, with whatever was made.
        %{status: :removed} = photo ->
          discard_status(status)
          File.rm_rf(photo.work_dir)
          assign(socket, :photo_prep, Map.delete(socket.assigns.photo_prep, ref))

        %{} ->
          socket
          |> put_status(ref, status)
          |> fail_waiting_photos(status)
      end

    {:halt, check_next_photo(socket, name)}
  end

  defp handle_photo_checked(_key, _result, socket), do: {:cont, socket}

  # A photo failed on our side (e.g. it waited minutes for its turn and
  # the site is still busy). The photos queued after it would most
  # likely wait just as long, one after another, so they aren't started:
  # they get the same message and a "Try again" too.
  defp fail_waiting_photos(socket, {:failed, message}) do
    Enum.reduce(socket.assigns.photo_prep, socket, fn {ref, photo}, socket ->
      if photo.status == :queued do
        put_status(socket, ref, {:failed, message})
      else
        socket
      end
    end)
  end

  defp fail_waiting_photos(socket, _status), do: socket

  defp discard_status({:ready, prepared}), do: Images.discard_prepared(prepared)
  defp discard_status(_other), do: :ok

  # --- Saving ------------------------------------------------------------

  @doc """
  Stores the photos in upload slot `name` under `folder` (e.g.
  `"products/12"`), in the background, once they're all checked.

  `create_row` makes a stored photo's database row. It is called (in the
  background task) as `create_row.(key, position)`, with positions
  counting up from `first_position`, and must return `{:ok, _}` or
  `{:error, _}`.

  Returns one of:

    * `{:started, socket}` — the form's
      `handle_async(:process_photos, ...)` will be called when done
      (after waiting for photos still being checked, if any);
    * `{:no_photos, socket}` — nothing to store; the form carries on;
    * `{:not_ready, socket}` — a picked file was already refused in the
      browser (too large, wrong type), or is still being prepared there
      or still uploading.
      Nothing is stored and `:photo_problem` says why; the form should
      stay on the page, as when a photo is refused.
  """
  def start_processing(socket, name, folder, first_position, create_row) do
    socket = assign(socket, photo_errors: %{}, photo_problem: nil, problem_from_browser: false)
    {done, in_progress} = uploaded_entries(socket, name)
    # Entries refused by LiveView's own check (too large, wrong type)
    # never finish uploading, so they are in `in_progress` too.
    {refused, still_uploading} = Enum.split_with(in_progress, fn entry -> not entry.valid? end)

    cond do
      # The two browser-side cases come first: those photos aren't in
      # the upload box, so a save now would quietly leave them out.
      socket.assigns.photos_preparing ->
        {:not_ready, assign(socket, photo_problem: @msg_preparing, problem_from_browser: true)}

      socket.assigns.refused_in_browser != [] ->
        problem = refused_in_browser_summary(socket.assigns.refused_in_browser)
        {:not_ready, assign(socket, photo_problem: problem, problem_from_browser: true)}

      still_uploading != [] ->
        problem =
          "Your photos are still uploading. Please wait until their bars are full, " <>
            "then save again."

        {:not_ready, assign(socket, :photo_problem, problem)}

      refused != [] ->
        failures =
          for entry <- refused do
            {entry.client_name, :refused,
             browser_check_reason(socket.assigns.uploads[name], entry)}
          end

        {:not_ready, assign(socket, :photo_problem, problem_summary(failures))}

      done == [] ->
        {:no_photos, socket}

      true ->
        pending = %{
          refs: Enum.map(done, fn entry -> entry.ref end),
          folder: folder,
          first_position: first_position,
          create_row: create_row
        }

        socket =
          socket
          |> make_sure_all_known(done)
          |> queue_failed_again(pending.refs)
          |> assign(saving_photos: true, pending_save: pending)
          |> check_next_photo(name)

        {:started, socket}
    end
  end

  # Every finished upload has a status already (handle_progress/3); this
  # is only a safety net, so no photo can be left out of a save.
  defp make_sure_all_known(socket, done_entries) do
    Enum.reduce(done_entries, socket, fn entry, socket ->
      if Map.has_key?(socket.assigns.photo_prep, entry.ref) do
        socket
      else
        add_photo(socket, entry)
      end
    end)
  end

  # Save tries photos that failed on our side once more.
  defp queue_failed_again(socket, refs) do
    Enum.reduce(refs, socket, fn ref, socket ->
      case socket.assigns.photo_prep[ref] do
        %{status: {:failed, _message}} -> put_status(socket, ref, :queued)
        _other -> socket
      end
    end)
  end

  # Called when nothing is left to check. If a save is waiting, its
  # photos are all checked now: store them.
  defp continue_waiting_save(%{assigns: %{pending_save: nil}} = socket), do: socket

  defp continue_waiting_save(socket) do
    pending = socket.assigns.pending_save

    # What to do with each photo of the save, in the order picked.
    photos =
      for ref <- pending.refs, photo = socket.assigns.photo_prep[ref], photo != nil do
        %{ref: ref, client_name: photo.name, status: photo.status}
      end

    page = self()

    socket
    |> assign(pending_save: nil, photos_in_progress: photos)
    |> start_async(:process_photos, fn ->
      store_all(photos, pending.folder, pending.first_position, pending.create_row, page)
    end)
  end

  # Runs in the background task, one photo after another. Returns
  # {ref, :stored}, {ref, {:refused, message}} or {ref, {:failed,
  # message}} for each photo.
  #
  # Tells the page (`page`) as soon as each photo is stored, so that even
  # if this task died halfway, the page would know which photos already
  # have their row and mustn't be stored again (finish_processing/3).
  defp store_all(photos, folder, first_position, create_row, page) do
    {results, _next_position} =
      Enum.map_reduce(photos, first_position, fn photo, position ->
        case photo.status do
          {:ready, prepared} ->
            case store_one_safely(prepared, folder, position, create_row) do
              :stored ->
                send(page, {:photo_stored, photo.ref})
                {{photo.ref, :stored}, position + 1}

              {:error, message} ->
                {{photo.ref, {:failed, message}}, position}
            end

          # Refused or failed when checked: passed on as it is.
          other ->
            {{photo.ref, other}, position}
        end
      end)

    results
  end

  # Stores one checked photo, then makes its row. Its temporary files go
  # either way: if storing failed, trying again checks the photo afresh.
  #
  # Anything that raises (or exits) here counts as this photo failing, so
  # one photo's crash can't take the others down with it.
  defp store_one_safely(prepared, folder, position, create_row) do
    try do
      store_one(prepared, folder, position, create_row)
    catch
      kind, reason ->
        Logger.error("Storing photo #{prepared.client_name} crashed: #{inspect({kind, reason})}")
        {:error, @msg_save_failed}
    after
      Images.discard_prepared(prepared)
    end
  end

  defp store_one(prepared, folder, position, create_row) do
    case Images.store_prepared(prepared, folder) do
      {:ok, key} ->
        case create_row_safely(create_row, key, position) do
          {:ok, _row} ->
            :stored

          {:error, reason} ->
            Logger.error("Saving the row for photo #{key} failed: #{inspect(reason)}")
            # No row points to the stored files; remove them.
            Storage.delete_prefix(key)
            {:error, @msg_save_failed}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  # The form's create_row function, with a raise counted as an error,
  # so the stored files are removed again (store_one/4).
  defp create_row_safely(create_row, key, position) do
    try do
      create_row.(key, position)
    rescue
      exception -> {:error, exception}
    end
  end

  # The background task stored a photo (store_all/5). Other messages go
  # on to the form.
  defp handle_photo_stored({:photo_stored, ref}, socket) do
    socket =
      if Map.has_key?(socket.assigns.photo_prep, ref) do
        put_status(socket, ref, :stored)
      else
        socket
      end

    {:halt, socket}
  end

  defp handle_photo_stored(_message, socket), do: {:cont, socket}

  # The background task checking a photo has read its header (see
  # start_checking/3): whether it's big, and how many pictures it holds
  # (Images.prepare_upload/4). The photo may have
  # been removed meanwhile. Other messages go on to the form.
  defp handle_photo_header({:photo_header, ref, %{big: big, pictures: pictures}}, socket) do
    socket =
      case socket.assigns.photo_prep[ref] do
        nil ->
          socket

        photo ->
          photo = %{photo | big: big, pictures: pictures}
          assign(socket, :photo_prep, Map.put(socket.assigns.photo_prep, ref, photo))
      end

    {:halt, socket}
  end

  defp handle_photo_header(_message, socket), do: {:cont, socket}

  @doc """
  Handles the background task's result (the form's `handle_async`
  passes it on): stored photos leave the upload box, the others stay
  with their messages.

  Returns `{socket, outcome}`, where `outcome` is
  `%{stored: count, failed: count}`.
  """
  def finish_processing(socket, name, async_result) do
    photos = socket.assigns.photos_in_progress

    results =
      case async_result do
        {:ok, results} ->
          results

        # The task died. (Each photo is protected on its own in
        # store_all/5, so this needs something unusual, e.g. the task
        # being killed.) The page was told about each photo stored before
        # that, so those count as stored and won't be stored twice. A
        # photo that was ready but not stored yet counts as failed (its
        # files are deleted; trying again checks it afresh); refused and
        # failed photos keep their messages.
        {:exit, reason} ->
          Logger.error("Storing photos crashed: #{inspect(reason)}")

          for photo <- photos do
            {photo.ref, result_after_crash(socket.assigns.photo_prep[photo.ref])}
          end
      end

    {socket, stored} =
      Enum.reduce(results, {socket, 0}, fn {ref, result}, {socket, stored} ->
        case result do
          :stored -> {remove_from_upload_box(socket, name, ref), stored + 1}
          not_stored -> {put_status(socket, ref, not_stored), stored}
        end
      end)

    # {file name, kind, reason} for each photo not stored, in the order
    # picked. (A result that isn't :stored is {:refused or :failed,
    # message}.)
    results_by_ref = Map.new(results)

    failures =
      for photo <- photos, results_by_ref[photo.ref] != :stored do
        {kind, message} = results_by_ref[photo.ref]
        {photo.client_name, kind, message}
      end

    # Photos picked while the others were being saved weren't part of
    # this save. (The picker is disabled meanwhile, so this is a rare
    # case.) Say so, rather than letting the form move on without them.
    batch_refs = Enum.map(photos, fn photo -> photo.ref end)

    late_entries =
      Enum.reject(socket.assigns.uploads[name].entries, fn entry -> entry.ref in batch_refs end)

    late_errors =
      Map.new(late_entries, fn entry -> {entry.ref, @msg_picked_late} end)

    late_failures =
      Enum.map(late_entries, fn entry -> {entry.client_name, :failed, @msg_picked_late} end)

    all_failures = failures ++ late_failures

    # A photo picked during the save may still be waiting to be checked
    # (check_next_photo/2 keeps to the save's own photos meanwhile).
    socket =
      socket
      |> assign(
        saving_photos: false,
        photos_in_progress: [],
        photo_errors: late_errors,
        photo_problem: problem_summary(all_failures)
      )
      |> check_next_photo(name)

    {socket, %{stored: stored, failed: length(all_failures)}}
  end

  # What a photo counts as when the storing task died (see
  # finish_processing/3): `photo` is its entry in :photo_prep.
  defp result_after_crash(%{status: :stored}), do: :stored

  defp result_after_crash(%{status: {:ready, prepared}}) do
    Images.discard_prepared(prepared)
    {:failed, @msg_save_failed}
  end

  defp result_after_crash(%{status: {kind, message}}) when kind in [:refused, :failed] do
    {kind, message}
  end

  defp result_after_crash(_other), do: {:failed, @msg_save_failed}

  # The photo is stored, so its temporary upload file can go.
  defp remove_from_upload_box(socket, name, ref) do
    entry = Enum.find(socket.assigns.uploads[name].entries, fn entry -> entry.ref == ref end)

    if entry do
      consume_uploaded_entry(socket, entry, fn _meta -> {:ok, nil} end)
    end

    assign(socket, :photo_prep, Map.delete(socket.assigns.photo_prep, ref))
  end

  # The text for the red box (and the flash, see problem_flash/2):
  # which photos weren't saved, why, and what to do. `failures` is a
  # list of {file name, kind, reason}, kind being :refused (the photo
  # can't be used: only removing it helps) or :failed (trying again
  # may work).
  defp problem_summary([]), do: nil

  defp problem_summary([{file_name, kind, reason}]) do
    "Your photo #{file_name} was NOT saved: #{reason} " <> what_to_do([kind], :one)
  end

  defp problem_summary(failures) do
    reasons =
      for {file_name, _kind, reason} <- failures do
        "#{file_name}: #{reason}"
      end

    kinds = Enum.map(failures, fn {_file_name, kind, _reason} -> kind end)

    "#{length(failures)} photos were NOT saved. " <>
      Enum.join(reasons, " ") <> " " <> what_to_do(kinds, :several)
  end

  defp what_to_do(kinds, :one) do
    if :refused in kinds do
      "Remove it with ✕ and pick another photo, then save again."
    else
      "Press Try again next to it, or save again."
    end
  end

  defp what_to_do(kinds, :several) do
    if :refused in kinds do
      "Remove the ones that can't be used with ✕ and pick other photos, then save again."
    else
      "Press Try again next to them, or save again."
    end
  end

  # The text for the red box when the browser refused photos without
  # uploading them (over the size limit). Saving again doesn't help
  # here, so it only says to remove them.
  defp refused_in_browser_summary([file_name]) do
    "Your photo #{file_name} was NOT uploaded: #{Images.too_large_message()} " <>
      "Remove it with ✕ and pick another photo, then save again."
  end

  defp refused_in_browser_summary(file_names) do
    "#{length(file_names)} photos were NOT uploaded: #{Enum.join(file_names, ", ")}. " <>
      "They are too large. Please use smaller versions: remove them with ✕ and " <>
      "pick other photos, then save again."
  end

  # Why LiveView's own check refused `entry` (too large, wrong kind).
  defp browser_check_reason(upload_config, entry) do
    upload_config
    |> upload_errors(entry)
    |> Enum.map(fn error -> error_to_string(error) end)
    |> Enum.join(" ")
  end

  @doc """
  The flash message after a photo was refused: `saved_text` (e.g.
  "Your work is saved.") followed by the full reason, the same text as
  the red box next to the save button.
  """
  def problem_flash(socket, saved_text) do
    saved_text <> " " <> socket.assigns.photo_problem
  end

  @doc """
  The message to show after photos were stored, reminding the artist to
  check their order, or `nil` when there's nothing to order (fewer than
  two photos in total).
  """
  def order_reminder(%{stored: stored}, total_photos) when stored > 0 and total_photos >= 2 do
    "Your photos are saved. Please check their order with the ↑ ↓ arrow buttons: " <>
      "the first photo is the one people see first."
  end

  def order_reminder(_outcome, _total_photos), do: nil

  @doc """
  Removes one photo from the upload box (its ✕ button), with its
  temporary files. Ignored while photos are being saved: the photo may
  be the one being stored.

  A photo still being checked has its background task stopped (it may
  only be waiting for its turn, which can take minutes). The photo
  stays in `:photo_prep` as `:removed` until the task has really ended
  (handle_photo_checked/3 gets told), and only then are its files
  deleted: a task stopped in the middle of writing a file finishes that
  file first.
  """
  def cancel_photo(%{assigns: %{saving_photos: true}} = socket, _name, _ref), do: socket

  def cancel_photo(socket, name, ref) do
    socket =
      case socket.assigns.photo_prep[ref] do
        %{status: :checking} ->
          socket
          |> cancel_async({:check_photo, name, ref}, {:shutdown, :photo_removed})
          |> put_status(ref, :removed)

        %{status: status} ->
          discard_status(status)
          assign(socket, :photo_prep, Map.delete(socket.assigns.photo_prep, ref))

        nil ->
          socket
      end

    socket
    |> cancel_upload(name, ref)
    |> assign(:photo_errors, Map.delete(socket.assigns.photo_errors, ref))
  end

  # --- Components ------------------------------------------------------

  @doc "One line saying which photos are accepted."
  def accepted_help(assigns) do
    ~H"""
    <span>
      Photos from your phone or camera: JPEG, PNG, HEIC, WebP, TIFF or AVIF · up to 25 MB each · up to 5 at a time
    </span>
    """
  end

  @doc """
  The file picker plus one row per picked photo: preview, name,
  progress or status, ✕, and any message about it.
  """
  attr :upload, :any, required: true, doc: "e.g. @uploads.images"
  attr :photo_prep, :map, required: true, doc: "the :photo_prep assign"
  attr :photo_errors, :map, required: true
  attr :saving_photos, :boolean, required: true

  def photo_picker(assigns) do
    ~H"""
    <%!-- The PhotoShrink hook (assets/js/photo_shrink.js) catches the
         picked files before LiveView does, shrinks the big ones and then
         hands them to LiveView. The data-* attributes give it the
         server's limits and wording. --%>
    <div
      id={"photo-picker-#{@upload.ref}"}
      phx-hook="PhotoShrink"
      data-max-pixels={Images.max_pixels()}
      data-long-side={Images.source_max_side()}
      data-too-large-message={Images.too_large_message()}
    >
      <%!-- live_file_input is the LiveView-aware file picker: it sends the
         file to the server in chunks as soon as it is picked. --%>
      <.live_file_input
        upload={@upload}
        class="file-input file-input-bordered w-full"
        disabled={@saving_photos}
      />

      <div class="space-y-3 mt-3">
        <div
          :for={entry <- @upload.entries}
          id={"photo-entry-#{entry.ref}"}
          class={[
            "flex flex-wrap items-center gap-3 rounded-lg p-2",
            has_problem?(@photo_prep[entry.ref], @photo_errors[entry.ref]) &&
              "border-2 border-error bg-error/10"
          ]}
        >
          <.live_img_preview
            :if={previewable?(entry)}
            entry={entry}
            class="w-16 h-16 object-cover rounded-lg border border-base-300"
          />
          <div
            :if={not previewable?(entry)}
            class="w-16 h-16 rounded-lg border border-base-300 flex items-center justify-center text-xs text-base-content/60 text-center"
          >
            no preview
          </div>

          <div class="flex-1 min-w-0">
            <p class="text-sm truncate">{entry.client_name}</p>
            <.photo_state entry={entry} photo={@photo_prep[entry.ref]} />
          </div>

          <button
            :if={not @saving_photos}
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            class="btn btn-ghost btn-xs text-error"
            aria-label={"Remove #{entry.client_name}"}
          >
            ✕
          </button>

          <%!-- Problems found in the browser: too big, wrong type. --%>
          <p
            :for={err <- upload_errors(@upload, entry)}
            class="w-full text-error text-sm font-semibold"
          >
            {error_to_string(err)}
          </p>
          <%!-- A moving image, or a TIFF with several pages (NOTES #44). --%>
          <.pictures_note photo={@photo_prep[entry.ref]} />
          <%!-- Problems found on the server when checking the photo. --%>
          <.check_problem
            photo={@photo_prep[entry.ref]}
            ref={entry.ref}
            saving_photos={@saving_photos}
          />
          <%!-- Picked while the others were being saved. --%>
          <p :if={@photo_errors[entry.ref]} class="w-full text-error text-sm font-semibold">
            Not saved: {@photo_errors[entry.ref]}
          </p>
        </div>
      </div>

      <%!-- Photos the hook is still preparing ("Preparing photo…"), and
         photos it refused without uploading. The hook fills this list
         itself; phx-update="ignore" tells LiveView to leave it alone.
         empty:hidden (no gap while there's nothing in it) needs a truly
         empty element, so the hook removes the line break below when it
         starts (the formatter puts it back here). --%>
      <div
        id={"photo-preparing-#{@upload.ref}"}
        phx-update="ignore"
        data-preparing-list
        aria-live="polite"
        class="space-y-3 mt-3 empty:hidden"
      >
      </div>

      <%!-- Problems with the whole selection, e.g. too many files. --%>
      <p :for={err <- upload_errors(@upload)} class="text-error text-sm font-semibold mt-2">
        {error_to_string(err)}
      </p>
    </div>
    """
  end

  defp has_problem?(%{status: {:refused, _}}, _late_error), do: true
  defp has_problem?(%{status: {:failed, _}}, _late_error), do: true
  defp has_problem?(_photo, late_error), do: late_error != nil

  # Under the photo's name: the upload's progress bar until it has
  # arrived, then what the server is doing with it. `data-photo-checking`
  # marks "still being checked", whatever the wording (the tests wait
  # for it to go: PhotoUploadHelpers.wait_for_photo_work/2).
  attr :entry, :any, required: true
  attr :photo, :map, default: nil

  defp photo_state(%{photo: nil} = assigns) do
    ~H"""
    <progress value={@entry.progress} max="100" class="progress progress-primary w-full" />
    """
  end

  # A big photo waits for the big photos' slot and takes several times
  # longer (NOTES #43): say so, so the artist doesn't think it's stuck.
  defp photo_state(%{photo: %{status: :checking, big: true}} = assigns) do
    ~H"""
    <p class="text-sm text-base-content/70 flex items-center gap-2" role="status" data-photo-checking>
      <span class="loading loading-spinner loading-xs"></span>
      Large photo — this one takes a little longer…
    </p>
    """
  end

  defp photo_state(%{photo: %{status: status}} = assigns) when status in [:queued, :checking] do
    ~H"""
    <p class="text-sm text-base-content/70 flex items-center gap-2" role="status" data-photo-checking>
      <span class="loading loading-spinner loading-xs"></span> Checking the photo…
    </p>
    """
  end

  defp photo_state(%{photo: %{status: {:ready, _prepared}}} = assigns) do
    ~H"""
    <p class="text-sm text-success font-semibold">Ready ✓</p>
    """
  end

  # Refused or failed: the message goes on its own line (photo_problem/1).
  defp photo_state(assigns), do: ~H""

  # Only the first picture of a moving image, or the first page of a TIFF
  # with several, is kept: see Images.prepare_upload/4. Not shown for a
  # photo that can't be used anyway.
  attr :photo, :map, default: nil

  defp pictures_note(assigns) do
    ~H"""
    <p
      :if={show_pictures_note?(@photo) and @photo.pictures == :moving_image}
      class="w-full text-sm text-base-content/80"
    >
      This is a moving image. Only its first picture will be shown on the site.
    </p>
    <p
      :if={show_pictures_note?(@photo) and @photo.pictures == :several_pages}
      class="w-full text-sm text-base-content/80"
    >
      This file has several pages. Only the first page will be shown on the site.
    </p>
    """
  end

  defp show_pictures_note?(%{status: {:ready, _prepared}}), do: true
  defp show_pictures_note?(%{status: :checking}), do: true
  defp show_pictures_note?(%{status: :stored}), do: true
  defp show_pictures_note?(_photo), do: false

  # The server's message about a photo it couldn't use, or couldn't
  # check because of a problem on our side (then with "Try again").
  attr :photo, :map, default: nil
  attr :ref, :string, required: true
  attr :saving_photos, :boolean, required: true

  defp check_problem(%{photo: %{status: {:refused, message}}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <p class="w-full text-error text-sm font-semibold">{@message}</p>
    """
  end

  defp check_problem(%{photo: %{status: {:failed, message}}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="w-full flex flex-wrap items-center gap-3">
      <p class="text-error text-sm font-semibold">{@message}</p>
      <button
        :if={not @saving_photos}
        type="button"
        phx-click="retry_photo"
        phx-value-ref={@ref}
        class="btn btn-sm btn-outline"
      >
        Try again
      </button>
    </div>
    """
  end

  defp check_problem(assigns), do: ~H""

  @doc """
  Goes next to the save button(s): "Saving your photos…" while the
  photos are stored (or a save waits for them), and a red box if a
  photo was refused. (The flash says the same, but is easy to miss.)
  """
  attr :saving_photos, :boolean, required: true
  attr :photo_problem, :string, default: nil

  def photo_status(assigns) do
    ~H"""
    <div :if={@saving_photos} id="saving-photos" class="alert alert-info mt-4" role="status">
      <span class="loading loading-spinner"></span>
      <span>
        Saving your photos… This usually takes a few seconds, a little longer
        when the site is busy. Please keep this page open.
      </span>
    </div>

    <div :if={@photo_problem} id="photo-problem" class="alert alert-error mt-4" role="alert">
      <span class="font-semibold">{@photo_problem}</span>
    </div>
    """
  end

  @doc """
  The photos already stored, in order, each with ↑ ↓ buttons to change
  the order and a Remove button. The buttons send the events
  `"move_image_up"`, `"move_image_down"` and `"delete_image"`, with the
  photo's id as `"imageid"`; each form handles them. The buttons are
  hidden while photos are being saved, so the order doesn't change
  under the photos being added.
  """
  attr :images, :list, required: true, doc: "ProductImage or ArtistImage rows, in order"
  attr :saving_photos, :boolean, required: true

  def stored_photos(assigns) do
    ~H"""
    <div :if={@images != []} class="mb-4">
      <p class="text-sm text-base-content/60 mb-2">Already uploaded:</p>
      <div class="flex flex-col gap-3">
        <div :for={{img, index} <- Enum.with_index(@images)} class="flex items-center gap-3">
          <img
            src={Images.url(img.path, :thumb)}
            alt={"Photo #{index + 1}"}
            class="w-24 h-24 object-cover rounded-lg border border-base-300"
          />
          <div :if={not @saving_photos} class="flex flex-col gap-1">
            <%!-- ↑ hidden on the first photo, ↓ on the last --%>
            <button
              :if={index > 0}
              type="button"
              phx-click="move_image_up"
              phx-value-imageid={img.id}
              class="btn btn-ghost btn-xs"
              aria-label={"Move photo #{index + 1} up"}
            >
              ↑
            </button>
            <button
              :if={index < length(@images) - 1}
              type="button"
              phx-click="move_image_down"
              phx-value-imageid={img.id}
              class="btn btn-ghost btn-xs"
              aria-label={"Move photo #{index + 1} down"}
            >
              ↓
            </button>
          </div>
          <button
            :if={not @saving_photos}
            type="button"
            phx-click="delete_image"
            phx-value-imageid={img.id}
            data-confirm="Remove this photo? This can't be undone."
            class="btn btn-ghost btn-sm text-error"
          >
            Remove
          </button>
        </div>
      </div>
      <p :if={length(@images) > 1} class="text-xs text-base-content/60 mt-2">
        Use the ↑ ↓ arrows to change the order. The first photo is the one people see first.
      </p>
    </div>
    """
  end

  defp previewable?(entry) do
    extension = entry.client_name |> Path.extname() |> String.downcase()
    extension in @previewable
  end

  @doc "LiveView's upload error atoms in plain words."
  def error_to_string(:too_large), do: "This file is larger than 25 MB. Please use a smaller one."
  def error_to_string(:too_many_files), do: "Please pick at most 5 photos at a time."

  def error_to_string(:not_accepted) do
    "This kind of file isn't accepted. Please use a JPEG, PNG, HEIC, WebP, TIFF or AVIF photo."
  end

  def error_to_string(other), do: "This file couldn't be uploaded (#{inspect(other)})."
end
