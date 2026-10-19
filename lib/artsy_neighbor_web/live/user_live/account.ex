defmodule ArtsyNeighborWeb.UserLive.Account do
  # The "Account" page from the header: who is logged in, a way to the
  # settings page, and "Log out".
  #
  # It exists because the settings page asks people to log in again
  # unless they did so in the last 10 minutes (a safety rule for changing
  # email or password, :require_sudo_mode). Putting "Log out" there would
  # mean logging in again just to log out. This page has no such rule.
  use ArtsyNeighborWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Your account")}
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
      <div class="max-w-xl space-y-8">
        <h1 class="text-4xl">Your account</h1>

        <dl class="space-y-3">
          <div>
            <dt class="text-sm text-muted">Name</dt>
            <dd id="account-username">{@current_scope.user.username}</dd>
          </div>
          <div>
            <dt class="text-sm text-muted">Email</dt>
            <dd id="account-email">{@current_scope.user.email}</dd>
          </div>
        </dl>

        <div>
          <.link navigate={~p"/users/settings"} class="text-link">
            Change your email or password
          </.link>
          <p class="mt-1 text-sm text-muted">
            You may be asked to log in again first, to keep your account safe.
          </p>
        </div>

        <.button id="log-out" href={~p"/users/log-out"} method="delete">Log out</.button>
      </div>
    </Layouts.artsy_main>
    """
  end
end
