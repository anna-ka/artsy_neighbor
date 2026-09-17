defmodule ArtsyNeighborWeb.FlagLive.New do
  # Lets a signed-in buyer or vendor report a rogue vendor, product, or
  # buyer to admins. Reporting only — there is no moderation UI yet
  # (see CLAUDE.md); admin resolving/dismissing flags is a separate,
  # not-yet-built feature.
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Reviews
  import ArtsyNeighborWeb.CustomComponents, only: [back: 1]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, return_to: nil, return_label: nil)}
  end

  def handle_params(
        %{"subject_type" => subject_type, "subject_id" => subject_id} = params,
        _uri,
        socket
      ) do
    current_user = socket.assigns.current_scope.user
    return_to = Map.get(params, "return_to")
    return_label = Map.get(params, "return_label")
    fallback = return_to || ~p"/"

    socket =
      socket
      |> assign(:return_to, return_to)
      |> assign(:return_label, return_label)

    case Reviews.resolve_subject(subject_type, subject_id) do
      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "We couldn't find that to report.")
         |> push_navigate(to: fallback)}

      {:ok, resolved} ->
        cond do
          resolved.owner_user_id == current_user.id ->
            {:noreply,
             socket
             |> put_flash(:error, "You can't report yourself.")
             |> push_navigate(to: fallback)}

          subject_type == "buyer" and is_nil(socket.assigns.current_scope.artist) ->
            {:noreply,
             socket
             |> put_flash(:error, "Only vendors can report buyers.")
             |> push_navigate(to: fallback)}

          true ->
            pending_flag =
              Reviews.pending_flag_from(current_user.id, subject_type, resolved.record.id)

            {:noreply,
             socket
             |> assign(:subject_type, subject_type)
             |> assign(:resolved, resolved)
             |> assign(:pending_flag, pending_flag)
             |> assign(:reason, "")
             |> assign(:error, nil)
             |> assign(:page_title, "Report #{resolved.display_name}")}
        end
    end
  end

  # Keep :reason in sync as the user types so the character counter stays
  # live — not live validation (nothing in this codebase does
  # phx-change="validate"), just a display sync, same as OfVendorStep's
  # :body tracking.
  def handle_event("form_changed", params, socket) do
    {:noreply, assign(socket, :reason, Map.get(params, "reason", ""))}
  end

  def handle_event("submit", _params, socket) do
    current_user = socket.assigns.current_scope.user

    attrs = %{
      subject_type: socket.assigns.subject_type,
      subject_id: socket.assigns.resolved.record.id,
      reason: String.trim(socket.assigns.reason),
      reporter_id: current_user.id
    }

    case Reviews.create_flag(attrs) do
      {:ok, _flag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Thanks — a moderator will review this report.")
         |> push_navigate(to: socket.assigns.return_to || ~p"/")}

      {:error, changeset} ->
        if duplicate_flag_error?(changeset) do
          # Defensive path — the mount-time pending_flag check above should
          # already have caught this in practice. Only reachable if a flag
          # went pending in the moment between mount and this submit.
          {:noreply,
           assign(
             socket,
             :error,
             "You already have a pending report on this — no need to submit another."
           )}
        else
          msg =
            Ecto.Changeset.traverse_errors(changeset, fn {m, _opts} -> m end)
            |> Enum.map_join(", ", fn {f, msgs} -> "#{f} #{Enum.join(msgs, ", ")}" end)

          {:noreply, assign(socket, :error, msg)}
        end
    end
  end

  defp duplicate_flag_error?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {msg, _opts}} ->
      msg == "you have already flagged this"
    end)
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main
      flash={@flash}
      nav_categories={@nav_categories}
      current_scope={@current_scope}
      has_unread={@has_unread_messages}
      pending_reviews_as_buyer={@pending_reviews_as_buyer}
      pending_reviews_as_vendor={@pending_reviews_as_vendor}
    >
      <div class="max-w-lg mx-auto px-4 py-12">
        <.back :if={@return_to && @return_label} navigate={@return_to}>{@return_label}</.back>

        <div class="bg-base-200 rounded-xl p-6 flex flex-col gap-6 mt-4">
          <div>
            <p class="text-xs text-base-content/50 uppercase tracking-widest mb-2">
              Report a concern
            </p>
            <h1 class="text-2xl font-bold text-base-content">{@resolved.display_name}</h1>
          </div>

          <div :if={@pending_flag} class="flex flex-col gap-3">
            <p class="text-sm text-base-content/70">
              You already reported this on {Calendar.strftime(@pending_flag.inserted_at, "%b %-d")} —
              a moderator hasn't reviewed it yet.
            </p>
            <.link
              :if={@return_to}
              navigate={@return_to}
              class="btn btn-ghost btn-sm w-full"
            >
              {@return_label || "Go back"}
            </.link>
          </div>

          <form
            :if={!@pending_flag}
            phx-submit="submit"
            phx-change="form_changed"
            class="flex flex-col gap-4"
          >
            <div>
              <label class="text-sm font-medium text-base-content block mb-2">
                What's the concern?
              </label>
              <textarea
                name="reason"
                rows="5"
                maxlength="1000"
                class="textarea textarea-bordered w-full text-sm resize-none"
                placeholder="Describe what happened — at least 20 characters."
              >{@reason}</textarea>
              <p class="text-right text-xs text-base-content/40 mt-1">
                {String.length(@reason)}/1000
              </p>
            </div>

            <p :if={@error} class="text-sm text-error">{@error}</p>

            <button type="submit" class="btn btn-primary w-full">
              Submit report
            </button>
          </form>
        </div>
      </div>
    </Layouts.artsy_main>
    """
  end
end
