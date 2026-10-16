defmodule ArtsyNeighborWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ArtsyNeighborWeb, :html

  # alias ArtsyNeighborWeb.CustomComponents

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Base layout with navigation and footer.
  This is used as a wrapper by artsy_main and artsy_wide layouts.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :variant, :string,
    default: "public",
    values: ["public", "admin", "vendor"],
    doc:
      "the layout variant to render, which can be used to conditionally show/hide elements based on user role"

  attr :nav_categories, :list, default: [], doc: "list of categories for the nav category bar"
  attr :current_scope, :map, default: nil
  attr :has_unread, :boolean, default: false
  attr :pending_reviews_as_buyer, :integer, default: 0
  attr :pending_reviews_as_vendor, :integer, default: 0
  slot :inner_block, required: true

  def navlayout(assigns) do
    ~H"""
    <!-- Site-wide announcement banner -->
    <ArtsyNeighborWeb.CustomComponents.site_wide_banner show={true} variant="test">
      Special Holiday Sale! Get 20% off all artwork until December 25th.
    </ArtsyNeighborWeb.CustomComponents.site_wide_banner>

    <header class={[
      "px-4 sm:px-6 lg:px-8",
      @variant == "admin" && "bg-neutral text-neutral-content",
      @variant == "vendor" && "bg-info text-info-content "
    ]}>
      <!-- First row: Logo + Search + Actions -->
      <div class="navbar">
        <div class="flex-1 flex items-center gap-2">
          <a href="/" class="flex w-fit items-center gap-2">
            <%!-- <img src={~p"/images/bird_logos2.png"} width="88" /> --%>
            <%!-- <img src={~p"/images/coral-colors-logo.png"} width="128" /> --%>
            <img src={~p"/images/fish-logo-removebg-preview.png"} width="128" />
            <span class="text-sm font-semibold">Artsy Neighbor</span>
          </a>

          <.button navigate={~p"/products"}>
            <.icon name="hero-bars-4" class="size-4 mr-1" /> Explore
          </.button>

          <input
            type="search"
            placeholder="What are you looking for?"
            class="input input-sm input-bordered w-48 md:w-64 lg:w-96"
            name="q"
          />
        </div>
        <nav aria-label="Site navigation" class="flex-none flex items-center gap-2">
          <!-- Scrollable: nav links + theme toggle -->

          <!-- Scrollable: nav links + theme toggle -->
          <div
            class="relative flex items-center"
            id="site-nav-scroll"
            phx-hook="CategoryScroll"
          >
            <button
              class="btn btn-ghost btn-sm px-1 flex-none"
              data-scroll-dir="-1"
              aria-label="Scroll left"
            >
              <.icon name="hero-chevron-left" class="size-4" />
            </button>

            <ul
              data-scroll-inner
              class="flex flex-row flex-nowrap overflow-x-auto scroll-smooth gap-1 max-w-xs md:max-w-sm lg:max-w-lg [&::-webkit-scrollbar]:hidden [scrollbar-width:none]"
            >
              <li class="flex-none">
                <a href="/artists" class="btn btn-ghost btn-sm whitespace-nowrap">Artist Directory</a>
              </li>
              <li class="flex-none">
                <a href={~p"/offer-art"} class="btn btn-ghost btn-sm whitespace-nowrap">Offer art</a>
              </li>
              <li class="flex-none">
                <a href={~p"/products"} class="btn btn-ghost btn-sm whitespace-nowrap">
                  Purchase art
                </a>
              </li>
              <li :if={@current_scope && @current_scope.user} class="flex-none">
                <.link
                  navigate={~p"/messages"}
                  class="btn btn-ghost btn-sm whitespace-nowrap relative"
                >
                  Messages
                  <span
                    :if={@has_unread}
                    class="badge badge-error badge-xs absolute -top-0.5 -right-0.5"
                  >
                  </span>
                </.link>
              </li>
              <li :if={@current_scope && @current_scope.user} class="flex-none">
                <.link navigate={~p"/orders"} class="btn btn-ghost btn-sm whitespace-nowrap relative">
                  Orders
                  <span
                    :if={@pending_reviews_as_buyer > 0}
                    class="badge badge-warning badge-xs absolute -top-0.5 -right-0.5"
                  >
                  </span>
                </.link>
              </li>
              <li :if={@current_scope && @current_scope.artist} class="flex-none">
                <.link navigate={~p"/vendor"} class="btn btn-ghost btn-sm whitespace-nowrap relative">
                  Dashboard
                  <span
                    :if={@pending_reviews_as_vendor > 0}
                    class="badge badge-warning badge-xs absolute -top-0.5 -right-0.5"
                  >
                  </span>
                </.link>
              </li>
              <li :if={!(@current_scope && @current_scope.user)} class="flex-none">
                <a href={~p"/users/log-in"} class="btn btn-ghost btn-sm whitespace-nowrap">Log in</a>
              </li>
              <li :if={!(@current_scope && @current_scope.user)} class="flex-none">
                <a href={~p"/users/register"} class="btn btn-ghost btn-sm whitespace-nowrap">
                  Sign up
                </a>
              </li>
              <li class="flex-none">
                <a
                  href="https://github.com/phoenixframework/phoenix"
                  class="btn btn-ghost btn-sm whitespace-nowrap"
                >
                  Our mission
                </a>
              </li>
            </ul>

            <button
              class="btn btn-ghost btn-sm px-1 flex-none"
              data-scroll-dir="1"
              aria-label="Scroll right"
            >
              <.icon name="hero-chevron-right" class="size-4" />
            </button>
          </div>
        </nav>
      </div>
      
    <!-- Second row: Category links (scrollable) -->
      <nav
        aria-label="Category navigation"
        class="relative flex items-center w-full py-1"
        id="category-nav"
        phx-hook="CategoryScroll"
      >
        <button
          class="btn btn-ghost btn-sm px-1 flex-none"
          data-scroll-dir="-1"
          aria-label="Scroll categories left"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>

        <ul
          data-scroll-inner
          class="flex flex-row flex-nowrap overflow-x-auto scroll-smooth gap-1 flex-1 [&::-webkit-scrollbar]:hidden [scrollbar-width:none]"
        >
          <li class="flex-none">
            <a href={~p"/categories"} class="btn btn-ghost whitespace-nowrap">All categories</a>
          </li>
          <li :for={category <- @nav_categories} class="flex-none">
            <.link navigate={~p"/categories/#{category}"} class="btn btn-ghost whitespace-nowrap">
              {category.name}
            </.link>
          </li>
        </ul>

        <button
          class="btn btn-ghost btn-sm px-1 flex-none"
          data-scroll-dir="1"
          aria-label="Scroll categories right"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </button>
      </nav>
    </header>

    <!-- Main content area (customized by child layouts) -->
    {render_slot(@inner_block)}

    <!-- Footer -->
    <footer class="bg-gray-900 text-white py-12">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          
    <!-- Column 1: Company Info -->
          <div>
            <h3 class="text-lg font-semibold mb-4">Company</h3>
            <ul class="space-y-2">
              <li><a href="#" class="text-gray-400 hover:text-white">About Us</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Our Mission</a></li>
              <li>
                <.link href={~p"/contactus"}>
                  Contact
                </.link>
              </li>
              <li><a href="#" class="text-gray-400 hover:text-white">Careers</a></li>
            </ul>
          </div>
          
    <!-- Column 2: Legal -->
          <div>
            <h3 class="text-lg font-semibold mb-4">Legal</h3>
            <ul class="space-y-2">
              <li><a href="#" class="text-gray-400 hover:text-white">User Agreement</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Privacy Policy</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Cookie Policy</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Terms of Service</a></li>
            </ul>
          </div>
          
    <!-- Column 3: Social Media -->
          <div>
            <h3 class="text-lg font-semibold mb-4">Follow Us</h3>
            <ul class="space-y-2">
              <li><a href="#" class="text-gray-400 hover:text-white">Facebook</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Instagram</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Twitter</a></li>
              <li><a href="#" class="text-gray-400 hover:text-white">Pinterest</a></li>
            </ul>
          </div>
        </div>
        
    <!-- Row 2: Divider -->
        <div class="border-t border-gray-700 my-8"></div>
        
    <!-- Row 3: Copyright -->
        <div class="text-center text-gray-400">
          <p>&copy; 2025 Artsy Neighbor. All rights reserved.</p>
        </div>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Standard content layout with max-width constraint.
  Uses navlayout for navigation and footer.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :variant, :string,
    default: "public",
    values: ["public", "admin", "vendor"],
    doc:
      "the layout variant to render, which can be used to conditionally show/hide elements based on user role. This is passed down to navlayout to allow for styling adjustments based on user role."

  attr :nav_categories, :list, default: []
  attr :has_unread, :boolean, default: false
  attr :pending_reviews_as_buyer, :integer, default: 0
  attr :pending_reviews_as_vendor, :integer, default: 0

  slot :inner_block, required: true

  def artsy_main(assigns) do
    ~H"""
    <.navlayout
      flash={@flash}
      variant={@variant}
      nav_categories={@nav_categories}
      current_scope={@current_scope}
      has_unread={@has_unread}
      pending_reviews_as_buyer={@pending_reviews_as_buyer}
      pending_reviews_as_vendor={@pending_reviews_as_vendor}
    >
      <main class="flex justify-center">
        <div class="flex-1 max-w-7xl px-4 py-20 sm:px-6 lg:px-8 bg-base-100">
          {render_slot(@inner_block)}
        </div>
      </main>
    </.navlayout>
    """
  end

  @doc """
  Full-width content layout for admin tables and wide content.
  Uses navlayout for navigation and footer.

  Mostly used for redering very wide tables.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :variant, :string,
    default: "public",
    values: ["public", "admin", "vendor"],
    doc:
      "the layout variant to render, which can be used to conditionally show/hide elements based on user role. This is passed down to navlayout to allow for styling adjustments based on user role."

  attr :nav_categories, :list, default: []

  slot :inner_block, required: true

  def artsy_wide(assigns) do
    ~H"""
    <.navlayout flash={@flash} variant={@variant} nav_categories={@nav_categories}>
      <main class="w-full">
        <div class="w-full py-20 bg-base-100">
          {render_slot(@inner_block)}
        </div>
      </main>
    </.navlayout>
    """
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the page's messages ("flash"), plus the two built-in ones for a
  lost connection.

  The messages stay on screen at the top of the window, even when the page
  is scrolled down (decided in Phase 0 of
  `docs/plans/2026-10-15-theme-and-components.md`), centred, one under the
  other when there are several. The empty space around them lets clicks
  through to the page (`pointer-events-none`); the messages themselves
  take clicks again (`pointer-events-auto` in `<.flash>`).

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="fixed inset-x-0 top-4 z-50 mx-auto flex w-[min(36rem,calc(100%-32px))] flex-col gap-3 pointer-events-none"
    >
      <.flash kind={:success} flash={@flash} />
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet.")}
        phx-disconnected={
          show_message(".phx-client-error #client-error") |> JS.remove_attribute("hidden")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Trying to reconnect…")}
        <.icon name="hero-arrow-path" class="ml-1 size-4 align-[-3px] motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong on our side.")}
        phx-disconnected={
          show_message(".phx-server-error #server-error") |> JS.remove_attribute("hidden")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Trying to reconnect…")}
        <.icon name="hero-arrow-path" class="ml-1 size-4 align-[-3px] motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # Shows a hidden message, like CoreComponents.show/2 but as a row
  # (display: flex). JS.show on its own sets display: block, which would
  # stack the message's icon, words and "Close" on top of each other.
  defp show_message(selector) do
    JS.show(
      to: selector,
      display: "flex",
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end
end
