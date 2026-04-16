defmodule ArtsyNeighborWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use ArtsyNeighborWeb, :controller
      use ArtsyNeighborWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images uploads favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: ArtsyNeighborWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())

      # Inject fallback handle_info clauses for inbox badge PubSub messages.
      # @before_compile runs after the module body is compiled, so these clauses
      # appear LAST and only fire when no earlier clause matched.
      # LiveViews with their own logic for these messages (e.g. ConversationLive.Index)
      # define clauses before this and match first — the fallbacks are never reached there.
      @before_compile {ArtsyNeighborWeb, :__inject_badge_handlers__}
    end
  end

  @doc false
  defmacro __inject_badge_handlers__(_env) do
    quote do
      # These messages are sent to subscribed LiveViews by the :load_unread_badge
      # on_mount hook (via {:cont, socket}) after it updates has_unread_messages.
      # Returning {:noreply, socket} completes the handle_info cycle so Phoenix
      # LiveView pushes the diff to the client.
      def handle_info({:conversation_updated, _}, socket), do: {:noreply, socket}
      def handle_info({:marked_read, _}, socket), do: {:noreply, socket}
      def handle_info({:new_conversation, _}, socket), do: {:noreply, socket}
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: ArtsyNeighborWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import ArtsyNeighborWeb.CoreComponents

      # Common modules used in templates
      alias Phoenix.LiveView.JS
      alias ArtsyNeighborWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: ArtsyNeighborWeb.Endpoint,
        router: ArtsyNeighborWeb.Router,
        statics: ArtsyNeighborWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
