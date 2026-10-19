defmodule ArtsyNeighborWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ArtsyNeighborWeb, :html

  # <.placeholder> for header and footer links to things not built yet.
  import ArtsyNeighborWeb.CustomComponents, only: [placeholder: 1]

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
    <header class="site-header">
      <div class="site-header-row">
        <.link navigate={~p"/"} class="brand" aria-label="localpalette, home page">
          <%!-- The logo is still a draft (the final one is being made). --%>
          <img src={~p"/images/site/logo-draft.png"} alt="" class="brand-logo" />
          <.wordmark />
        </.link>

        <%!-- Search isn't built yet. The box can't be typed into
             (readonly), so nobody types a search that goes nowhere. --%>
        <.placeholder what="Search">
          <label class="header-search-box">
            <.icon name="hero-magnifying-glass" class="size-[18px] flex-none" />
            <input
              type="search"
              name="q"
              placeholder="What are you looking for?"
              aria-label="Search"
              readonly
            />
          </label>
          <button type="button" class="btn-base btn-ordinary header-search-button">Search</button>
        </.placeholder>

        <.header_links
          current_scope={@current_scope}
          has_unread={@has_unread}
          pending_reviews_as_buyer={@pending_reviews_as_buyer}
          pending_reviews_as_vendor={@pending_reviews_as_vendor}
        />
      </div>
    </header>

    <div :if={@variant == "admin"} class="admin-strip">Admin</div>

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

  # The header's links. Visitors: About us · Artists · Offer art · Log in ·
  # Register. Logged in: About us · Artists · Offer art (or "Your shop" for
  # artists) · Messages · Orders · Admin (admins only) · Account. Plain
  # links, no drop-down menus (decided in Phase D of
  # docs/plans/2026-10-15-theme-and-components.md). On phones "Log in"
  # and "Register" move to the front (header-first).
  attr :current_scope, :map, default: nil
  attr :has_unread, :boolean, default: false
  attr :pending_reviews_as_buyer, :integer, default: 0
  attr :pending_reviews_as_vendor, :integer, default: 0

  defp header_links(assigns) do
    user = assigns.current_scope && assigns.current_scope.user
    artist = assigns.current_scope && assigns.current_scope.artist
    admin = assigns.current_scope && assigns.current_scope.admin

    assigns =
      assign(assigns, logged_in: user != nil, artist?: artist != nil, admin?: admin == true)

    ~H"""
    <nav aria-label="Site" class="header-links">
      <.placeholder what="About us page">
        <a href="#">About us</a>
      </.placeholder>
      <.link navigate={~p"/artists"}>Artists</.link>
      <.link :if={!@artist?} navigate={~p"/offer-art"}>Offer art</.link>

      <%= if @logged_in do %>
        <.link navigate={~p"/messages"}>
          Messages
          <span :if={@has_unread} class="header-dot header-dot-unread" aria-hidden="true"></span>
          <span :if={@has_unread} class="sr-only">(new messages)</span>
        </.link>
        <.link navigate={~p"/orders"}>
          Orders
          <span
            :if={@pending_reviews_as_buyer > 0}
            class="header-dot header-dot-review"
            aria-hidden="true"
          >
          </span>
          <span :if={@pending_reviews_as_buyer > 0} class="sr-only">(a review to write)</span>
        </.link>
        <.link :if={@artist?} navigate={~p"/vendor"}>
          Your shop
          <span
            :if={@pending_reviews_as_vendor > 0}
            class="header-dot header-dot-review"
            aria-hidden="true"
          >
          </span>
          <span :if={@pending_reviews_as_vendor > 0} class="sr-only">(a review to write)</span>
        </.link>
        <.link :if={@admin?} navigate={~p"/admin"}>Admin</.link>
        <.link navigate={~p"/account"}>Account</.link>
      <% else %>
        <.link navigate={~p"/users/log-in"} class="header-first">Log in</.link>
        <.link navigate={~p"/users/register"} class="header-first">Register</.link>
      <% end %>
    </nav>
    """
  end

  # The site name, "localpalette", with each letter moved up or down along
  # one gentle wave (2px each way) and leaning 5° to the right, like letters
  # floating on water. Chosen in docs/design/mockups/wordmark.html; the
  # mockups do the same with a script (setUpWordmark in mockup.js), here
  # the server works out each letter's place. Screen readers get the
  # name from the link around it (aria-label), not letter by letter.
  defp wordmark(assigns) do
    letters = String.graphemes("localpalette")
    last_index = length(letters) - 1

    styled_letters =
      letters
      |> Enum.with_index()
      |> Enum.map(fn {letter, index} -> {letter, wave_letter_style(index, last_index)} end)

    assigns = assign(assigns, :letters, styled_letters)

    ~H"""
    <span class="wordmark" aria-hidden="true">
      <span
        :for={{letter, style} <- @letters}
        class="wave-letter"
        style={style}
      >
        {letter}
      </span>
    </span>
    """
  end

  # One letter's place on the wave: the word spans one full wave, from the
  # first letter (index 0) to the last.
  defp wave_letter_style(index, last_index) do
    angle = index / last_index * 2 * :math.pi()
    shift_up = Float.round(-2 * :math.sin(angle), 2)
    "transform: translateY(#{shift_up}px) skewX(-5deg)"
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
  attr :has_unread, :boolean, default: false
  attr :pending_reviews_as_buyer, :integer, default: 0
  attr :pending_reviews_as_vendor, :integer, default: 0

  slot :inner_block, required: true

  def artsy_wide(assigns) do
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

  The messages stay on screen even when the page is scrolled down, in one
  column centred across the window (`msg-column`), one under the other
  when there are several. The column has two groups: warnings and errors
  (`msg-alerts`) first, so they are seen first, then success and
  information. The column starts a quarter of the way down the window;
  warnings and errors are solid, success and information tinted (rules
  under "Messages" in `assets/css/app.css`).

  The empty space around the messages lets clicks through to the page
  (`pointer-events-none`); the messages themselves take clicks again
  (`pointer-events-auto` in `<.flash>`).

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      class="msg-column fixed inset-0 z-50 flex flex-col items-center gap-3 pointer-events-none"
    >
      <div aria-live="polite" class="msg-group msg-alerts">
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

      <div aria-live="polite" class="msg-group">
        <.flash kind={:success} flash={@flash} />
        <.flash kind={:info} flash={@flash} />
      </div>
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
