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

  import ArtsyNeighborWeb.CustomComponents,
    only: [
      artwork_card: 1,
      collection_card: 1,
      section_heading: 1,
      show_more: 1,
      quiet_link: 1,
      report_link: 1,
      chip: 1,
      filter_chip: 1,
      star_rating: 1,
      review: 1,
      placeholder: 1
    ]

  alias ArtsyNeighbor.Categories
  alias ArtsyNeighbor.Products

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
    form =
      to_form(%{
        "title" => "",
        "category" => "",
        "homepage" => "",
        "pickup" => "true",
        "delivery" => "false"
      })

    socket =
      assign(socket,
        page_title: "Style guide",
        theme_colours: @theme_colours,
        extra_colours: @extra_colours,
        form: form,
        sample_products: sample_products(),
        sample_categories: Enum.take(Categories.list_categories(), 4),
        bio_open: false,
        chosen_chip: "all"
      )

    {:ok, socket}
  end

  # Four real products for the "Cards" section, those with materials or a
  # size first, so the details line under the title has something to show.
  defp sample_products do
    Products.list_products_with_associations()
    |> Enum.sort_by(fn product -> is_nil(product.materials) and is_nil(product.width) end)
    |> Enum.take(4)
  end

  # Made-up reviews for the "Ratings and reviews" section, so it always
  # has something to show (the database may have no reviews that are
  # visible yet). The second is long, to check that the text wraps well.
  defp sample_reviews do
    [
      %{
        stars: 5,
        name: "Linda",
        date: ~D[2026-09-12],
        work: "Crow with Stones",
        text: "Even more beautiful in person. Maren showed me the studio when I picked it up."
      },
      %{
        stars: 4,
        name: "Graham",
        date: ~D[2026-08-03],
        work: "Crow Study",
        text:
          "Lovely painting and very easy pickup. The colours are a little cooler than " <>
            "in the photo, which I actually prefer. It took a couple of messages to " <>
            "find a time that suited us both, but Maren was patient and kind about it, " <>
            "and it now hangs above our piano."
      },
      %{stars: 3, name: "Teresa", date: ~D[2026-07-21], work: "Mother Otter", text: nil}
    ]
  end

  # Buttons in the "Messages" section. Each shows real flash messages,
  # exactly as the rest of the app does.
  def handle_event("flash", %{"kind" => "success"}, socket) do
    {:noreply, put_flash(socket, :success, "Saved. Your changes are on your page now.")}
  end

  def handle_event("flash", %{"kind" => "info"}, socket) do
    {:noreply, put_flash(socket, :info, "Your changes were saved.")}
  end

  def handle_event("flash", %{"kind" => "error"}, socket) do
    message = "We couldn't save your changes. Please check the form and try again."
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_event("flash", %{"kind" => "warning"}, socket) do
    message = "Your shop is paused. Buyers can't see your works until you turn it back on."
    {:noreply, put_flash(socket, :warning, message)}
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

  # The "Confirming" section: only reached after "Yes" in the box.
  def handle_event("confirmed", %{"what" => what}, socket) do
    {:noreply, put_flash(socket, :success, "You said yes: #{what}. (Nothing really changed.)")}
  end

  # The "Links and small pieces" section: "Show more" opens and closes a
  # sample text; the filter chips change which one is chosen.
  def handle_event("toggle_bio", _params, socket) do
    {:noreply, assign(socket, :bio_open, not socket.assigns.bio_open)}
  end

  def handle_event("choose_chip", %{"chip" => chip}, socket) do
    {:noreply, assign(socket, :chosen_chip, chip)}
  end

  # The "Working" buttons: wait two seconds, so the turning circle and the
  # changed words ("Saving…") can be seen. Development only.
  def handle_event("slow", _params, socket) do
    Process.sleep(2000)
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

        <section>
          <.message_trial />
          <.flash_buttons id="flash-buttons-top" />
        </section>

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
            <code>&lt;.button variant="..."&gt;</code>. One main button per area; danger
            for removing things; the solid red one only for the final "Yes, delete".
          </p>
          <div class="space-y-6">
            <div class="flex flex-wrap items-center gap-4">
              <.button variant="main">Save changes</.button>
              <.button>Send message</.button>
              <.button variant="quiet">Clear filters</.button>
              <.button variant="danger">Delete this work</.button>
              <.button variant="danger_final">Yes, delete</.button>
            </div>
            <div class="flex flex-wrap items-center gap-4">
              <.button variant="main" disabled>Not available</.button>
              <.button disabled>Not available</.button>
              <.button variant="quiet" disabled>Not available</.button>
              <.button variant="danger" disabled>Not available</.button>
            </div>
            <div>
              <p class="mb-3 text-sm text-muted">
                Working: press one; the server waits two seconds before answering.
              </p>
              <div class="flex flex-wrap items-center gap-4">
                <.button
                  id="slow-main"
                  variant="main"
                  phx-click="slow"
                  phx-disable-with="Saving…"
                >
                  Save changes
                </.button>
                <.button
                  id="slow-danger"
                  variant="danger"
                  phx-click="slow"
                  phx-disable-with="Deleting…"
                >
                  Delete this work
                </.button>
              </div>
            </div>
            <div>
              <p class="mb-3 text-sm text-muted">A link that looks like a button:</p>
              <.button navigate={~p"/"}>Go to the home page</.button>
            </div>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Confirming</h2>
          <p class="mb-6 text-muted">
            Any button or link with <code>data-confirm</code>
            asks first, in one shared box
            (<code>root.html.heex</code>; the script and its other <code>data-confirm-...</code>
            attributes are in <code>assets/js/app.js</code>).
            Esc or "No, keep it" closes it and nothing happens.
          </p>
          <div class="flex flex-wrap items-center gap-4">
            <.button
              id="confirm-demo-delete"
              variant="danger"
              phx-click="confirmed"
              phx-value-what="delete"
              data-confirm="Delete “Crow at Ross Bay”?"
              data-confirm-detail="It will no longer show in your shop. Past orders and reviews keep it. You can restore it later from your dashboard."
            >
              Delete this work
            </.button>
            <.button
              id="confirm-demo-restore"
              phx-click="confirmed"
              phx-value-what="restore"
              data-confirm="Restore “Crow at Ross Bay”?"
              data-confirm-detail="It will show in your shop again."
              data-confirm-yes="Yes, restore"
              data-confirm-kind="ordinary"
            >
              Restore
            </.button>
            <.button
              id="confirm-demo-short"
              variant="danger"
              phx-click="confirmed"
              phx-value-what="delete message"
              data-confirm="Delete this message?"
            >
              Question only
            </.button>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Form fields</h2>
          <p class="mb-6 text-muted">
            <code>&lt;.input&gt;</code>: label above, help text before the box,
            "(optional)" in words. The price field shows a mistake.
          </p>
          <.form for={@form} id="styleguide-form" class="max-w-md">
            <.input
              field={@form[:title]}
              label="Title"
              help="The name buyers will see. You can change it later."
              placeholder="For example: Crow at Ross Bay"
            />
            <%!-- Given by name rather than field={...}: with a field, <.input> uses the
                 form's own errors and would ignore this example one. --%>
            <.input
              name="price"
              value="abc"
              label="Price"
              help="In dollars, without the $ sign."
              errors={["Please enter a number, like 120"]}
            />
            <.input
              field={@form[:category]}
              type="select"
              label="Category"
              prompt="Choose a category"
              options={["Ceramics", "Painting", "Jewellery"]}
            />
            <.input
              field={@form[:homepage]}
              type="url"
              label="Website"
              optional
              placeholder="For example: marenholt.ca"
            />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <.input
              name="studio"
              value="Fernwood"
              label="Studio area"
              help="Not available: set by the site."
              disabled
            />
            <.input field={@form[:pickup]} type="checkbox" label="Pickup in person" />
            <.input
              field={@form[:delivery]}
              type="checkbox"
              label="Delivery"
              help="You bring the work to the buyer's door."
            />
          </.form>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Cards</h2>
          <p class="mb-6 text-muted">
            <code>&lt;.artwork_card&gt;</code>
            and <code>&lt;.collection_card&gt;</code>, in a <code>card-grid</code>
            (4 across on a wide window, 3 on a tablet, 2 on a phone). Real works and
            categories from the database. The photo is cropped to fill the card; the
            product page shows the whole work.
          </p>
          <p class="mb-3 text-sm text-muted">
            Artworks as on the home page: no price (<code>show_price={"{false}"}</code>).
          </p>
          <div class="card-grid mb-10">
            <.artwork_card
              :for={product <- @sample_products}
              product={product}
              show_price={false}
            />
          </div>
          <p class="mb-3 text-sm text-muted">
            Artworks as in an artist's shop: no artist name (<code>show_artist={"{false}"}</code>), with the price.
          </p>
          <div class="card-grid mb-10">
            <.artwork_card
              :for={product <- @sample_products}
              product={product}
              show_artist={false}
            />
          </div>
          <p class="mb-3 text-sm text-muted">
            With a neighbourhood (<code>location="Fernwood"</code>; artists have no
            such field yet) and no size (<code>show_size={"{false}"}</code>).
          </p>
          <div class="card-grid mb-10">
            <.artwork_card
              :for={product <- @sample_products}
              product={product}
              location="Fernwood"
              show_size={false}
            />
          </div>
          <p class="mb-3 text-sm text-muted">
            Collections: site categories here, an artist's own collections on their page.
          </p>
          <div class="card-grid">
            <.collection_card
              :for={category <- @sample_categories}
              name={category.name}
              image={category.main_img}
              navigate={~p"/products?#{[category_id: category.id]}"}
            />
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Links and small pieces</h2>
          <p class="mb-6 text-muted">
            <code>&lt;.section_heading&gt;</code>, <code>&lt;.show_more&gt;</code>, <code>&lt;.quiet_link&gt;</code>, <code>&lt;.report_link&gt;</code>,
            <code>&lt;.chip&gt;</code>
            and <code>&lt;.filter_chip&gt;</code>. Ordinary links get the <code>text-link</code>
            class for now; in Phase D it becomes the look of every link.
          </p>

          <div class="space-y-10 max-w-3xl">
            <div>
              <p class="mb-3 text-sm text-muted">A link in text and a link on its own:</p>
              <p>
                Pickup is arranged with the artist; see <.link href="#" class="text-link">how pickup works</.link>.
              </p>
              <p class="mt-2">
                <.link href="#" class="text-link">See all works by this artist ›</.link>
              </p>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">
                Section headings, with and without a link (the link stays on one line):
              </p>
              <.section_heading>
                Popular artists
                <:link>
                  <.link href="#" class="text-link">See all artists ›</.link>
                </:link>
              </.section_heading>
              <.section_heading>
                Popular categories
                <:link>
                  <.show_more>Show more categories ›</.show_more>
                </:link>
              </.section_heading>
              <.section_heading>New works</.section_heading>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">
                "Show more", under a shortened text (try it):
              </p>
              <p id="sample-bio">
                Maren paints the crows of Ross Bay and the animals of the shore, in oil
                and silver leaf, from a small studio in Fernwood.<span :if={@bio_open}>
                  She started painting at sixty, after thirty years of teaching, and
                  still walks the sea wall every morning to sketch.
                </span>
              </p>
              <.show_more
                phx-click="toggle_bio"
                aria-controls="sample-bio"
                aria-expanded={to_string(@bio_open)}
              >
                {if @bio_open, do: "Show less ‹", else: "Show full bio ›"}
              </.show_more>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">
                Quiet links, and a report link (here to the report form for one of the
                sample works; logged-in users only):
              </p>
              <p class="flex flex-wrap gap-x-6 gap-y-2">
                <.quiet_link href="#">Back to top</.quiet_link>
                <%!-- A plain "/dev/styleguide", not ~p: the dev pages don't
                     exist in the test build, so ~p would warn there. --%>
                <.report_link
                  :if={@sample_products != []}
                  subject="product"
                  id={hd(@sample_products).id}
                  return_to="/dev/styleguide"
                  return_label="Style guide"
                >
                  Report this listing
                </.report_link>
              </p>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">Chips: mediums and techniques, not clickable.</p>
              <div class="chip-row">
                <.chip>Oil painting</.chip>
                <.chip>Silver leaf</.chip>
                <.chip>Drawing</.chip>
              </div>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">
                Filter chips: large and clickable, the chosen one filled in (try them).
              </p>
              <div class="chip-row" role="group" aria-label="Show works from">
                <.filter_chip
                  :for={{key, name, count} <- sample_chips()}
                  pressed={key == @chosen_chip}
                  count={count}
                  phx-click="choose_chip"
                  phx-value-chip={key}
                >
                  {name}
                </.filter_chip>
              </div>
            </div>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Ratings and reviews</h2>
          <p class="mb-6 text-muted">
            <code>&lt;.star_rating&gt;</code>
            and <code>&lt;.review&gt;</code>. Made-up reviews, so this section always has
            something to show.
          </p>

          <div class="space-y-10 max-w-3xl">
            <div>
              <p class="mb-3 text-sm text-muted">
                The three looks: <code>short</code>
                (as a link to the reviews), <code>home</code>, <code>full</code>.
              </p>
              <div class="flex flex-col items-start gap-3">
                <.star_rating rating={4.4} count={25} href="#sample-reviews" />
                <.star_rating rating={4.8} count={31} look="home" />
                <.star_rating rating={4.8} count={31} look="full" />
              </div>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">Other ratings: 5, 3.5, 2 and one review.</p>
              <div class="flex flex-col items-start gap-3">
                <.star_rating rating={5} count={12} look="full" />
                <.star_rating rating={3.5} count={4} look="full" />
                <.star_rating rating={2} count={1} look="full" />
              </div>
            </div>

            <div id="sample-reviews">
              <p class="mb-3 text-sm text-muted">
                Reviews of an artist, each naming the work that was bought (the <code>:bought</code>
                slot). The third has no text. Report links lead nowhere here.
              </p>
              <.star_rating rating={4.0} count={3} look="full" />
              <ul class="review-list mt-2">
                <.review
                  :for={sample <- sample_reviews()}
                  stars={sample.stars}
                  name={sample.name}
                  date={sample.date}
                  text={sample.text}
                >
                  <:bought>
                    <.link href="#" class="text-link">{sample.work}</.link>
                  </:bought>
                  <:report>
                    <.quiet_link href="#">Report this review</.quiet_link>
                  </:report>
                </.review>
              </ul>
            </div>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Placeholders</h2>
          <p class="mb-6 text-muted">
            <code>&lt;.placeholder what="..."&gt;</code>
            around a feature that is shown but not built yet. It looks like the real thing;
            pressing it shows "Not built yet" just below. Each one is listed in <code>docs/design/placeholders.md</code>.
          </p>

          <div class="space-y-8 max-w-3xl">
            <div>
              <p class="mb-3 text-sm text-muted">A button.</p>
              <.placeholder what="Following artists">
                <.button id="placeholder-demo-follow">Follow</.button>
              </.placeholder>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">A link (it goes nowhere).</p>
              <.placeholder what="Commissions">
                <.link id="placeholder-demo-link" navigate="/" class="text-link">
                  Ask about a commission
                </.link>
              </.placeholder>
            </div>

            <div>
              <p class="mb-3 text-sm text-muted">A line of text, such as an artist's motto.</p>
              <.placeholder what="Artist's motto">
                <p id="placeholder-demo-motto" class="italic">
                  “Painting the coast one tide at a time.”
                </p>
              </.placeholder>
            </div>
          </div>
        </section>

        <section>
          <h2 class="text-2xl mb-2">Messages</h2>
          <p class="mb-4 text-muted">
            <code>&lt;.flash&gt;</code>, four kinds. Samples of each below (always tinted);
            the buttons show real messages, placed as chosen with the switches at the top
            of this page. Start a message with a few bold words saying what happened. To
            see "We can't find the internet", stop the server for a few seconds.
          </p>
          <div class="max-w-xl space-y-3 mb-8">
            <.flash id="sample-success" kind={:success} title="Saved.">
              Your changes are on your page now.
            </.flash>
            <.flash id="sample-info" kind={:info} title="Pickup is arranged in messages.">
              You and the artist agree on a time there.
            </.flash>
            <.flash id="sample-warning" kind={:warning} title="Your shop is paused.">
              Buyers can't see your works until you turn it back on.
            </.flash>
            <.flash id="sample-error" kind={:error} title="We couldn't save your changes.">
              Please check the form and try again.
            </.flash>
          </div>
          <.flash_buttons id="flash-buttons-bottom" />
        </section>
      </div>
    </Layouts.artsy_main>
    """
  end

  # The filter chips' sample collections: {key, name, number of works}.
  defp sample_chips do
    [
      {"all", "All works", 24},
      {"crows", "Crows", 7},
      {"shore", "Shore animals", 4},
      {"legends", "Legends", 5}
    ]
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

  # Trial until Phase D: switches for the look of warnings and errors and
  # the place of all messages. Plain radio buttons; the script in root.html.heex remembers the
  # choice in this browser and applies it on every page of the app.
  # phx-update="ignore" stops LiveView from redrawing them (and so un-ticking
  # them) when this page changes.
  defp message_trial(assigns) do
    ~H"""
    <div id="message-trial" phx-update="ignore" class="mb-6 rounded-box bg-base-200 p-5">
      <h2 class="text-xl mb-1">Trying out messages</h2>
      <p class="mb-4 text-sm text-muted">
        Until Phase D. The look is for warnings and errors only (success and
        information stay tinted); the place is for all messages. The choice
        applies to every page of the app, in this browser only.
      </p>
      <fieldset class="mb-3 flex flex-wrap items-center gap-x-6 gap-y-2">
        <legend class="float-left mr-4 font-medium">Look of warnings and errors:</legend>
        <.trial_choice name="msg-look" value="tinted" label="Tinted" />
        <.trial_choice name="msg-look" value="solid" label="Solid" />
      </fieldset>
      <fieldset class="flex flex-wrap items-center gap-x-6 gap-y-2">
        <legend class="float-left mr-4 font-medium">Place of all messages:</legend>
        <.trial_choice name="msg-place" value="top" label="Top" />
        <.trial_choice name="msg-place" value="higher" label="Higher up" />
        <.trial_choice name="msg-place" value="centre" label="Centre" />
      </fieldset>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true

  defp trial_choice(assigns) do
    ~H"""
    <label class="field-check">
      <input type="radio" name={@name} value={@value} />
      <span>{@label}</span>
    </label>
    """
  end

  # The row of buttons that show real flash messages. Appears twice
  # (top and bottom of the page), so each copy needs its own id.
  attr :id, :string, required: true

  defp flash_buttons(assigns) do
    ~H"""
    <div id={@id} class="flex flex-wrap gap-3">
      <.button phx-click="flash" phx-value-kind="success">Show a success message</.button>
      <.button phx-click="flash" phx-value-kind="info">Show an information message</.button>
      <.button phx-click="flash" phx-value-kind="warning">Show a warning</.button>
      <.button phx-click="flash" phx-value-kind="error">Show an error message</.button>
      <.button phx-click="flash" phx-value-kind="both">Show two at once</.button>
      <.button phx-click="flash" phx-value-kind="after_move">
        Show one after moving to the home page
      </.button>
    </div>
    """
  end
end
