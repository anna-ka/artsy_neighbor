defmodule ArtsyNeighborWeb.DevLive.Styleguide do
  @moduledoc """
  The style guide page, `/dev/styleguide` (development only, like
  `/dev/mailbox`; the route is in the router's `:dev_routes` block).

  Shows every theme colour, font, text size and shared component on one
  page, so a change to the theme (`assets/css/app.css`) can be judged at
  a glance before looking at real pages. It also has buttons that show
  real flash messages, for deciding where messages should appear.

  Grows with each component built in Phase C of
  `docs/plans/2026-10-15-theme-and-components.md`.
  """
  use ArtsyNeighborWeb, :live_view

  # Every colour in the theme, in the order shown on the page:
  # {CSS name, Tailwind background class, what it is for}.
  # The hex values live only in assets/css/app.css, so they can't drift apart.
  @theme_colours [
    {"--color-base-100", "bg-base-100", "Page background"},
    {"--color-base-200", "bg-base-200", "Panels, cards"},
    {"--color-base-300", "bg-base-300", "Divider lines"},
    {"--color-base-content", "bg-base-content", "Text"},
    {"--color-primary", "bg-primary", "Main button"},
    {"--color-secondary", "bg-secondary", "Link underline, focus ring"},
    {"--color-success", "bg-success", "Success messages"},
    {"--color-info", "bg-info", "Information messages"},
    {"--color-warning", "bg-warning", "Warning messages"},
    {"--color-error", "bg-error", "Errors, danger buttons"}
  ]

  @extra_colours [
    {"--color-muted", "bg-muted", "Secondary text"},
    {"--color-soft", "bg-soft", "Chips, ordinary button mouse-over"},
    {"--color-field-edge", "bg-field-edge", "Form field edges, example text"}
  ]

  def mount(_params, _session, socket) do
    form = to_form(%{"title" => "", "category" => "", "pickup" => "true"})

    socket =
      assign(socket,
        page_title: "Style guide",
        theme_colours: @theme_colours,
        extra_colours: @extra_colours,
        form: form
      )

    {:ok, socket}
  end

  # Buttons in the "Messages" section. Each shows real flash messages,
  # exactly as the rest of the app does.
  def handle_event("flash", %{"kind" => "info"}, socket) do
    {:noreply, put_flash(socket, :info, "Your changes were saved.")}
  end

  def handle_event("flash", %{"kind" => "error"}, socket) do
    message = "We couldn't save your changes. Please check the form and try again."
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("flash", %{"kind" => "both"}, socket) do
    socket =
      socket
      |> put_flash(:info, "Your photo was uploaded.")
      |> put_flash(:error, "The second photo is too large (over 10 MB).")

    {:noreply, socket}
  end

  # Like saving a product and landing on the product list: the message
  # travels with the move to another page (here, the home page).
  def handle_event("flash", %{"kind" => "after_move"}, socket) do
    socket =
      socket
      |> put_flash(:info, "Product saved. (This message came from the style guide.)")
      |> push_navigate(to: ~p"/")

    {:noreply, socket}
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
      <div class="space-y-16">
        <header>
          <h1 class="text-4xl">Style guide</h1>
          <p class="mt-2 text-muted">
            Development only. Every colour, font and shared piece of the site on one page.
            The theme lives in <code>assets/css/app.css</code>; the plan in <code>docs/plans/2026-10-15-theme-and-components.md</code>.
          </p>
        </header>

        <.flash_buttons id="flash-buttons-top" />

        <section>
          <h2 class="text-2xl mb-4">Colours</h2>
          <p class="mb-4 text-muted">The theme's own colours (daisyUI names).</p>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
            <.swatch :for={{name, class, purpose} <- @theme_colours} name={name} class={class}>
              {purpose}
            </.swatch>
          </div>
          <p class="mt-8 mb-4 text-muted">Our extra colours.</p>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
            <.swatch :for={{name, class, purpose} <- @extra_colours} name={name} class={class}>
              {purpose}
            </.swatch>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-4">Fonts</h2>
          <dl class="space-y-6">
            <div>
              <dt class="text-sm text-muted">Sentient Light: titles (font-heading)</dt>
              <dd class="font-heading text-3xl font-light">Crow at Ross Bay, in winter light</dd>
            </div>
            <div>
              <dt class="text-sm text-muted">Switzer: everything else (the default font)</dt>
              <dd class="text-lg">
                Hand-thrown stoneware, glazed in the colours of the Salish Sea. <strong>Bold</strong>, <em>italic</em>.
              </dd>
            </div>
            <div>
              <dt class="text-sm text-muted">Spline Sans Mono: small labels (font-label)</dt>
              <dd class="font-label text-sm uppercase tracking-wider">Ceramics · Victoria</dd>
            </div>
            <div>
              <dt class="text-sm text-muted">Fraunces: the site name (font-wordmark)</dt>
              <dd
                class="font-wordmark text-2xl font-light"
                style="font-variation-settings: 'SOFT' 100, 'WONK' 1;"
              >
                Artsy Neighbor
              </dd>
            </div>
          </dl>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Text</h2>
          <p class="mb-6 text-muted">
            Body text is 16px, the browser's own default (decided 2026-10-15).
          </p>
          <div class="space-y-3 max-w-2xl">
            <p>
              Ordinary text. Acrylic on birch panel, 30 × 40 cm. Painted on a grey morning
              at Ross Bay, when the crows gather on the sea wall before a storm.
            </p>
            <p class="text-muted">
              Secondary text (text-muted). Pickup in Fernwood, weekday evenings.
            </p>
            <p class="text-sm text-muted">Small text (text-sm, 14px), for notes only.</p>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Titles</h2>
          <p class="mb-6 text-muted">Sentient Light, at today's sizes.</p>
          <div class="space-y-3">
            <h1 class="text-4xl">Page title (h1, 36px)</h1>
            <h2 class="text-2xl">Section title (h2, 24px)</h2>
            <h3 class="text-xl">Smaller title (h3, 20px)</h3>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Buttons</h2>
          <p class="mb-6 text-muted">
            Today's <code>&lt;.button&gt;</code>, not restyled yet (Phase C gives it the
            main / ordinary / quiet / danger kinds from the mockups).
          </p>
          <div class="flex flex-wrap gap-4">
            <.button variant="primary">Main</.button>
            <.button>Default</.button>
            <.button variant="primary" disabled>Not available</.button>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Form fields</h2>
          <p class="mb-6 text-muted">
            Today's <code>&lt;.input&gt;</code>, not restyled yet (Phase C).
            The price field shows an error.
          </p>
          <.form for={@form} id="styleguide-form" class="max-w-md">
            <.input field={@form[:title]} label="Title" placeholder="For example: Crow at Ross Bay" />
            <%!-- Given by name rather than field={...}: with a field, <.input> uses the
                 form's own errors and would ignore this example one. --%>
            <.input
              name="price"
              value="abc"
              label="Price"
              errors={["Please enter a number, like 120"]}
            />
            <.input
              field={@form[:category]}
              type="select"
              label="Category"
              prompt="Choose a category"
              options={["Ceramics", "Painting", "Jewellery"]}
            />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <.input field={@form[:pickup]} type="checkbox" label="Pickup in person" />
          </.form>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Messages</h2>
          <p class="mb-4 text-muted">
            The same message buttons as at the top of the page, to see whether a message is
            noticed when the page is scrolled down. Success and warning messages don't exist
            yet (Phase C adds them). To see "We can't find the internet", stop the server
            for a few seconds.
          </p>
          <.flash_buttons id="flash-buttons-bottom" />
        </section>
      </div>
    </Layouts.artsy_main>
    """
  end

  # One colour sample: a filled box, its CSS name and what it is for.
  attr :name, :string, required: true
  attr :class, :string, required: true
  slot :inner_block, required: true

  defp swatch(assigns) do
    ~H"""
    <div>
      <div class={["h-16 rounded-box border border-base-300", @class]}></div>
      <p class="mt-2 text-sm font-semibold">{@name}</p>
      <p class="text-sm text-muted">{render_slot(@inner_block)}</p>
    </div>
    """
  end

  # The row of buttons that show real flash messages. Appears twice
  # (top and bottom of the page), so each copy needs its own id.
  attr :id, :string, required: true

  defp flash_buttons(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap gap-3">
      <.button phx-click="flash" phx-value-kind="info">Show an information message</.button>
      <.button phx-click="flash" phx-value-kind="error">Show an error message</.button>
      <.button phx-click="flash" phx-value-kind="both">Show two at once</.button>
      <.button phx-click="flash" phx-value-kind="after_move">
        Show one after moving to the home page
      </.button>
    </div>
    """
  end
end
