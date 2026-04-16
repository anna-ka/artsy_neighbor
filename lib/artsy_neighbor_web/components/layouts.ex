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
  attr :variant, :string, default: "public", values: ["public", "admin", "vendor"], doc: "the layout variant to render, which can be used to conditionally show/hide elements based on user role"
  attr :nav_categories, :list, default: [], doc: "list of categories for the nav category bar"
  attr :current_scope, :map, default: nil
  attr :has_unread, :boolean, default: false
  slot :inner_block, required: true

  def navlayout(assigns) do
    ~H"""
    <!-- Site-wide announcement banner -->
    <ArtsyNeighborWeb.CustomComponents.site_wide_banner show={true} variant="test">
      Special Holiday Sale! Get 20% off all artwork until December 25th.
    </ArtsyNeighborWeb.CustomComponents.site_wide_banner>

    <header class={["px-4 sm:px-6 lg:px-8",
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
            <.icon name="hero-bars-4" class="size-4 mr-1" />
            Explore
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
            <button class="btn btn-ghost btn-sm px-1 flex-none" data-scroll-dir="-1" aria-label="Scroll left">
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
                <a href={~p"/products"} class="btn btn-ghost btn-sm whitespace-nowrap">Purchase art</a>
              </li>
              <li :if={@current_scope && @current_scope.user} class="flex-none">
                <.link navigate={~p"/messages"} class="btn btn-ghost btn-sm whitespace-nowrap relative">
                  Messages
                  <span :if={@has_unread} class="badge badge-error badge-xs absolute -top-0.5 -right-0.5"></span>
                </.link>
              </li>
              <li :if={!(@current_scope && @current_scope.user)} class="flex-none">
                <a href={~p"/users/log-in"} class="btn btn-ghost btn-sm whitespace-nowrap">Log in</a>
              </li>
              <li :if={!(@current_scope && @current_scope.user)} class="flex-none">
                <a href={~p"/users/register"} class="btn btn-ghost btn-sm whitespace-nowrap">Sign up</a>
              </li>
              <li class="flex-none">
                <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost btn-sm whitespace-nowrap">Our mission</a>
              </li>
              <li class="flex-none">
                <.theme_toggle />
              </li>
            </ul>

            <button class="btn btn-ghost btn-sm px-1 flex-none" data-scroll-dir="1" aria-label="Scroll right">
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
  attr :variant, :string, default: "public", values: ["public", "admin", "vendor"], doc: "the layout variant to render, which can be used to conditionally show/hide elements based on user role. This is passed down to navlayout to allow for styling adjustments based on user role."
  attr :nav_categories, :list, default: []
  attr :has_unread, :boolean, default: false

  slot :inner_block, required: true

  def artsy_main(assigns) do
    ~H"""
    <.navlayout flash={@flash} variant={@variant} nav_categories={@nav_categories} current_scope={@current_scope} has_unread={@has_unread}>
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
  attr :variant, :string, default: "public", values: ["public", "admin", "vendor"], doc: "the layout variant to render, which can be used to conditionally show/hide elements based on user role. This is passed down to navlayout to allow for styling adjustments based on user role."
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
            <.theme_toggle />
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
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
