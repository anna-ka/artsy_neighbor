defmodule ArtsyNeighborWeb.PhotoUploads do
  @moduledoc """
  Photo uploading shared by the four forms that take photos (vendor
  product form, vendor profile form, admin product form, admin artist
  form).

  ## How a save with photos works

  1. The form saves its text fields as usual.
  2. It calls `start_processing/5`. The photos the artist picked are
     processed (checked, resized, stored — `ArtsyNeighbor.Images`) in a
     **background task** (LiveView's `start_async/3`), and right after
     each photo is stored the task makes its database row (the form's
     `create_row` function). The page stays responsive meanwhile and
     shows "Saving your photos…".

     Why in the background: the browser waits at most 30 seconds for
     the answer to a button press and then reloads the page. Processing
     up to 5 photos, each possibly waiting for its turn
     (`ArtsyNeighbor.Images.Limiter`), can take longer than that.

     Why the row is made in the task, straight after the files: if the
     page closes in between, stored files with no row pointing to them
     would be left behind, and nothing would ever clean them up.
  3. When the task is done, LiveView calls the form's
     `handle_async(:process_photos, result, socket)`, which calls
     `finish_processing/3` here. Each stored photo leaves the upload
     box; a refused one **stays in the upload box** with its message,
     so the artist can see what went wrong and remove it or try again.
     Then the form decides where to go next: on as usual if all went
     well, or stay on the page if a photo was refused.

  ## Assigns this module adds to a form's socket

    * `:photo_errors` — `%{entry_ref => message}`, the message for each
      refused photo still in the upload box;
    * `:photo_problem` — a summary sentence shown in red next to the
      save button(s), or `nil`;
    * `:saving_photos` — true while the background task runs. The
      file picker, the ✕ buttons and the buttons of the stored photos
      are disabled meanwhile, and the forms ignore save presses;
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
  need to. Plan:
  `docs/plans/2026-11-19-browser-shrinking-and-early-processing.md`.
  """

  use Phoenix.Component

  import Phoenix.LiveView,
    only: [
      allow_upload: 3,
      attach_hook: 4,
      cancel_upload: 3,
      consume_uploaded_entry: 3,
      start_async: 3,
      uploaded_entries: 2
    ]

  require Logger

  alias ArtsyNeighbor.Images
  alias ArtsyNeighbor.Storage

  # Everything is converted to WebP on our side, so the uploaded format
  # doesn't matter after processing. See the plan doc for why GIF,
  # camera RAW, SVG, PDF and BMP are not accepted.
  @accept ~w(.jpg .jpeg .png .webp .heic .heif .tif .tiff .avif)

  # Phone photos are big; we shrink them anyway.
  @max_file_size 25_000_000
  @max_entries 5

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
          auto_upload: true
        ],
        opts
      )

    socket
    |> allow_upload(name, upload_opts)
    |> assign(
      photo_errors: %{},
      photo_problem: nil,
      saving_photos: false,
      photos_preparing: false,
      refused_in_browser: [],
      problem_from_browser: false
    )
    |> attach_hook(:photo_picker_state, :handle_event, fn event, params, socket ->
      handle_picker_state(event, params, socket)
    end)
  end

  # The browser's PhotoShrink hook sends its state whenever it changes:
  # %{"preparing" => true/false, "refused" => [file names]}. The event is
  # always handled here ({:halt, ...}), whatever its contents, so a
  # malformed one can't reach the form (which has no clause for it).
  # Every other event goes on to the form ({:cont, ...}).
  defp handle_picker_state("photo_picker_state", params, socket) do
    socket =
      socket
      |> assign(:photos_preparing, params["preparing"] == true)
      |> assign(:refused_in_browser, refused_names(params["refused"]))
      |> clear_browser_problem()

    {:halt, socket}
  end

  defp handle_picker_state(_event, _params, socket), do: {:cont, socket}

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

  @doc """
  Starts processing the photos in upload slot `name` in the background,
  storing them under `folder` (e.g. `"products/12"`).

  `create_row` makes a stored photo's database row. It is called (in the
  background task) as `create_row.(key, position)`, with positions
  counting up from `first_position`, and must return `{:ok, _}` or
  `{:error, _}`.

  Returns one of:

    * `{:started, socket}` — the form's
      `handle_async(:process_photos, ...)` will be called when done;
    * `{:no_photos, socket}` — nothing to process; the form carries on;
    * `{:not_ready, socket}` — a picked file was already refused in the
      browser (too large, wrong type), or is still being prepared or
      uploading.
      Nothing is processed and `:photo_problem` says why; the form
      should stay on the page, as when a photo is refused.
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
            {entry.client_name, browser_check_reason(socket.assigns.uploads[name], entry)}
          end

        {:not_ready, assign(socket, :photo_problem, problem_summary(failures))}

      done == [] ->
        {:no_photos, socket}

      true ->
        # {:postpone, ...} gives us each temporary file's path but keeps
        # the photo in the upload box (and its file on disk) for now. A
        # photo leaves the box only once it is stored
        # (finish_processing/3).
        files =
          for entry <- done do
            consume_uploaded_entry(socket, entry, fn %{path: path} ->
              {:postpone, %{ref: entry.ref, client_name: entry.client_name, path: path}}
            end)
          end

        socket =
          socket
          |> assign(:saving_photos, true)
          |> assign(:photos_in_progress, files)
          |> start_async(:process_photos, fn ->
            process_all(files, folder, first_position, create_row)
          end)

        {:started, socket}
    end
  end

  # Runs in the background task, one photo after another. Returns
  # {ref, :stored} or {ref, {:error, message}} for each photo.
  defp process_all(files, folder, first_position, create_row) do
    {results, _next_position} =
      Enum.map_reduce(files, first_position, fn file, position ->
        case process_one(file, folder, position, create_row) do
          :stored -> {{file.ref, :stored}, position + 1}
          {:error, message} -> {{file.ref, {:error, message}}, position}
        end
      end)

    results
  end

  # Processes and stores one photo, then makes its row.
  defp process_one(file, folder, position, create_row) do
    case Images.process_upload(file.path, file.client_name, folder) do
      {:ok, key} ->
        case create_row.(key, position) do
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

  @doc """
  Handles the background task's result (the form's `handle_async`
  passes it on): stored photos leave the upload box, refused ones stay
  with their messages.

  Returns `{socket, outcome}`, where `outcome` is
  `%{stored: count, failed: count}`.
  """
  def finish_processing(socket, name, async_result) do
    files = socket.assigns.photos_in_progress

    results =
      case async_result do
        {:ok, results} ->
          results

        # The task crashed. Every photo counts as failed; it stays in the
        # upload box for another try. (A photo stored just before the
        # crash keeps its row and shows up under the stored photos.)
        {:exit, reason} ->
          Logger.error("Processing photos crashed: #{inspect(reason)}")

          for file <- files do
            {file.ref, {:error, @msg_save_failed}}
          end
      end

    {socket, errors, stored} =
      Enum.reduce(results, {socket, %{}, 0}, fn {ref, result}, {socket, errors, stored} ->
        case result do
          :stored -> {remove_from_upload_box(socket, name, ref), errors, stored + 1}
          {:error, message} -> {socket, Map.put(errors, ref, message), stored}
        end
      end)

    # {file name, reason} for each refused photo, in the order picked.
    failures =
      for file <- files, Map.has_key?(errors, file.ref) do
        {file.client_name, errors[file.ref]}
      end

    # Photos picked while the others were being saved weren't part of
    # this save. (The picker is disabled meanwhile, so this is a rare
    # case.) Say so, rather than letting the form move on without them.
    batch_refs = Enum.map(files, fn file -> file.ref end)

    late_entries =
      Enum.reject(socket.assigns.uploads[name].entries, fn entry -> entry.ref in batch_refs end)

    late_errors =
      Map.new(late_entries, fn entry -> {entry.ref, @msg_picked_late} end)

    late_failures =
      Enum.map(late_entries, fn entry -> {entry.client_name, @msg_picked_late} end)

    all_failures = failures ++ late_failures

    socket =
      assign(socket,
        saving_photos: false,
        photos_in_progress: [],
        photo_errors: Map.merge(errors, late_errors),
        photo_problem: problem_summary(all_failures)
      )

    {socket, %{stored: stored, failed: length(all_failures)}}
  end

  # The photo is stored, so its temporary upload file can go.
  defp remove_from_upload_box(socket, name, ref) do
    entry = Enum.find(socket.assigns.uploads[name].entries, fn entry -> entry.ref == ref end)

    if entry do
      consume_uploaded_entry(socket, entry, fn _meta -> {:ok, nil} end)
    end

    socket
  end

  # The text for the red box (and the flash, see problem_flash/2):
  # which photos weren't saved, why, and what to do. `failures` is a
  # list of {file name, reason}.
  defp problem_summary([]), do: nil

  defp problem_summary([{file_name, reason}]) do
    "Your photo #{file_name} was NOT saved: #{reason} " <>
      "Remove it with ✕ and pick another photo, or save again to try once more."
  end

  defp problem_summary(failures) do
    reasons =
      for {file_name, reason} <- failures do
        "#{file_name}: #{reason}"
      end

    "#{length(failures)} photos were NOT saved. " <>
      Enum.join(reasons, " ") <>
      " Remove them with ✕ and pick other photos, or save again to try once more."
  end

  # The text for the red box when the browser refused photos without
  # uploading them (over the size limit). Saving again doesn't help
  # here, so unlike problem_summary/1 it only says to remove them.
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
  Removes one photo from the upload box (its ✕ button). Ignored while
  photos are being saved: the photo may be the one being processed.
  """
  def cancel_photo(%{assigns: %{saving_photos: true}} = socket, _name, _ref), do: socket

  def cancel_photo(socket, name, ref) do
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
  progress, ✕, and any message about it.
  """
  attr :upload, :any, required: true, doc: "e.g. @uploads.images"
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
            Map.has_key?(@photo_errors, entry.ref) && "border-2 border-error bg-error/10"
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
            <progress value={entry.progress} max="100" class="progress progress-primary w-full" />
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
          <%!-- Problems found on the server while processing. --%>
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

  @doc """
  Goes next to the save button(s): "Saving your photos…" while the
  background task runs, and a red box if a photo was refused. (The
  flash says the same, but is easy to miss.)
  """
  attr :saving_photos, :boolean, required: true
  attr :photo_problem, :string, default: nil

  def photo_status(assigns) do
    ~H"""
    <div :if={@saving_photos} id="saving-photos" class="alert alert-info mt-4" role="status">
      <span class="loading loading-spinner"></span>
      <span>
        Saving your photos… This usually takes a few seconds per photo, a little longer
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
