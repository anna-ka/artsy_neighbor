defmodule ArtsyNeighborWeb.ArtistLive.Show do
  @moduledoc """
  The artist's public page: a header (photos, name, area, mediums, bio)
  and four tabs below it, each with its own address:

    * Works   — `/artists/:id`         (live_action `:works`)
    * Shop    — `/artists/:id/store`   (live_action `:shop`)
    * Commissions — `/artists/:id/commissions` (live_action `:commissions`)
    * Contact — `/artists/:id/contact` (live_action `:contact`)

  Switching tabs is a LiveView patch: the page stays, `handle_params/3`
  runs again and only what's below the tabs changes. On every tab but
  Works the header is "compact" (smaller photo, shorter bio) so the
  tab's own content starts higher.

  The owner of an artist profile that isn't public yet can see it with
  `?preview=1` (the vendor dashboard links here that way). Tab links
  carry `preview`, `return_to` and `return_label` along, so switching
  tabs keeps the preview and the "Back to ..." link.
  """
  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Conversations

  import ArtsyNeighborWeb.CustomComponents,
    only: [
      filter_chip: 1,
      artwork_card: 1,
      collection_card: 1,
      section_heading: 1,
      button_artsy: 1,
      report_link: 1,
      chip: 1,
      show_more: 1,
      placeholder: 1
    ]

  # Query params that every tab link keeps.
  @kept_params ["preview", "return_to", "return_label"]

  # Query params of the Shop tab's filters.
  @filter_params ["search", "category_id", "collection_id", "sort_by"]

  # The Shop tab's sort choices besides the default, "Newest first"
  # (which has no sort_by in the address). Anything else in the address
  # is ignored.
  @sort_values ["price_asc", "price_desc"]

  # How many works the Shop tab shows at first, and how many more each
  # "Show more works" adds. 12 fills whole rows of 2, 3 or 4 cards.
  @page_size 12

  def mount(_params, _session, socket) do
    {:ok, assign(socket, return_to: nil, return_label: nil, photo_index: 0, bio_open: false)}
  end

  def handle_params(%{"id" => id} = params, _uri, socket) do
    artist = Artists.get_artist(id)

    cond do
      artist == nil ->
        {:noreply, artist_not_found(socket)}

      artist.status == :active ->
        {:noreply, load_page(socket, artist, params, :public)}

      owner_previewing?(artist, params, socket) ->
        socket =
          socket
          |> load_page(artist, params, :owner_preview)
          |> put_flash(:info, "Preview — your profile is not yet visible to the public.")

        {:noreply, socket}

      true ->
        {:noreply, artist_not_found(socket)}
    end
  end

  defp artist_not_found(socket) do
    socket
    |> put_flash(:error, "Artist not found.")
    |> push_navigate(to: ~p"/artists")
  end

  # True when the logged-in vendor is looking at their own profile
  # with ?preview=1.
  defp owner_previewing?(artist, params, socket) do
    scope = socket.assigns.current_scope
    viewer_artist = scope && scope.artist

    Map.get(params, "preview") == "1" && viewer_artist != nil && viewer_artist.id == artist.id
  end

  # Assigns for the header, then for the tab being shown. `audience` is
  # :public, or :owner_preview when the owner previews a profile that
  # isn't public yet; the tabs pick their queries by it.
  defp load_page(socket, artist, params, audience) do
    artist_images = Enum.sort_by(artist.artist_images, fn image -> image.position end)

    # Switching tabs keeps the photo being shown (the compact header shows
    # just that one); another artist starts at their first photo.
    same_artist? = socket.assigns[:artist] != nil && socket.assigns.artist.id == artist.id
    photo_index = if same_artist?, do: socket.assigns.photo_index, else: 0

    socket
    |> assign(:return_to, Map.get(params, "return_to"))
    |> assign(:return_label, Map.get(params, "return_label"))
    |> assign(:kept_params, Map.take(params, @kept_params))
    |> assign(:artist, artist)
    |> assign(:audience, audience)
    |> assign(:page_title, artist.nickname)
    |> assign(:artist_images, artist_images)
    |> assign(:photo_index, photo_index)
    # Every tab starts with the bio shortened, as the compact header
    # allows fewer lines.
    |> assign(:bio_open, false)
    |> load_tab(socket.assigns.live_action, artist, params)
  end

  # Featured works: the 4 newest available works, until artists can
  # choose their own (NOTES.md #23).
  defp load_tab(socket, :works, artist, _params) do
    featured_products =
      case socket.assigns.audience do
        :public -> Products.list_newest_artist_products(artist.id, 4)
        :owner_preview -> Products.list_newest_artist_products_for_owner_preview(artist.id, 4)
      end

    socket
    |> assign(:featured_products, featured_products)
    |> assign(:collections, shown_collections(socket.assigns.audience, artist))
  end

  defp load_tab(socket, :shop, artist, params) do
    filters =
      params
      |> Map.take(@filter_params)
      |> Map.reject(fn {key, value} -> key == "sort_by" && value not in @sort_values end)

    {products, category_counts} =
      case socket.assigns.audience do
        :public ->
          {Products.filter_artist_products(artist.id, filters),
           Products.count_artist_products_by_category(artist.id)}

        :owner_preview ->
          {Products.filter_artist_products_for_owner_preview(artist.id, filters),
           Products.count_artist_products_by_category_for_owner_preview(artist.id)}
      end

    # All the artist's works, before any filter: the sum of the category counts.
    total_count =
      Enum.reduce(category_counts, 0, fn {_id, _name, count}, sum -> sum + count end)

    socket
    |> assign(:filters, filters)
    |> assign(:form, to_form(filters))
    |> assign(:products, products)
    |> assign(:total_count, total_count)
    |> assign(:category_counts, category_counts)
    # The same collections as the Works tab's cards: none without works,
    # no "Uncategorized".
    |> assign(:collections, shown_collections(socket.assigns.audience, artist))
    # Any change of filters starts again with the first page of works.
    |> assign(:shown_count, @page_size)
  end

  defp load_tab(socket, :commissions, _artist, _params), do: socket
  defp load_tab(socket, :contact, _artist, _params), do: socket

  # The artist's collections that have works to show (Works tab cards,
  # Shop tab filter).
  defp shown_collections(:public, artist),
    do: Products.list_public_collections_for_artist(artist.id)

  defp shown_collections(:owner_preview, artist),
    do: Products.list_collections_for_owner_preview(artist.id)

  # The address of one tab, keeping the preview and "Back to ..." params.
  defp tab_path(artist, :works, query), do: ~p"/artists/#{artist}?#{query}"
  defp tab_path(artist, :shop, query), do: ~p"/artists/#{artist}/store?#{query}"
  defp tab_path(artist, :commissions, query), do: ~p"/artists/#{artist}/commissions?#{query}"
  defp tab_path(artist, :contact, query), do: ~p"/artists/#{artist}/contact?#{query}"

  # Shop tab: puts the filters in the address, which reloads the works
  # (handle_params/3). Empty filters are left out of the address.
  defp patch_shop(socket, filters) do
    filters = Map.reject(filters, fn {_key, value} -> value in [nil, ""] end)
    query = Map.merge(socket.assigns.kept_params, filters)

    push_patch(socket, to: tab_path(socket.assigns.artist, :shop, query))
  end

  # Shop tab: the filter form changed (search, category, sort). The
  # chosen collection comes along in a hidden field.
  def handle_event("filter", params, socket) do
    {:noreply, patch_shop(socket, Map.take(params, @filter_params))}
  end

  # Shop tab: a collection chip was pressed ("" is "All works"). The
  # other filters stay as they are.
  def handle_event("choose_collection", %{"id" => id}, socket) do
    filters = Map.put(socket.assigns.filters, "collection_id", id)
    {:noreply, patch_shop(socket, filters)}
  end

  # Shop tab: "Show more works".
  def handle_event("show_more", _params, socket) do
    {:noreply, assign(socket, :shown_count, socket.assigns.shown_count + @page_size)}
  end

  # Header: an arrow on the photo was pressed. The index wraps around, so
  # "next" on the last photo shows the first one.
  def handle_event("show_photo", %{"index" => index}, socket) do
    photo_count = length(socket.assigns.artist_images)

    photo_index =
      case Integer.parse(index) do
        {number, ""} when photo_count > 0 -> Integer.mod(number, photo_count)
        _ -> 0
      end

    {:noreply, assign(socket, :photo_index, photo_index)}
  end

  # Header: "Show full bio ›" / "Show less ‹".
  def handle_event("toggle_bio", _params, socket) do
    {:noreply, assign(socket, :bio_open, !socket.assigns.bio_open)}
  end

  # Commissions and Contact tabs: "Send message". Finds or creates a conversation between
  # the current user (buyer) and the artist (seller), then navigates to
  # that conversation's page.
  def handle_event("message_artist", _params, socket) do
    artist_id = socket.assigns.artist.id
    buyer_id = socket.assigns.current_scope.user.id
    {:ok, conversation} = Conversations.find_or_create_conversation(buyer_id, artist_id)
    {:noreply, push_navigate(socket, to: ~p"/messages/#{conversation.id}")}
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
      top_space={false}
    >
      <%!-- "Back to ...": just under the category bar, lined up with
           "All categories" and styled like it. Only when the page was
           opened with return_to and return_label. --%>
      <.link :if={@return_to && @return_label} navigate={@return_to} class="back-under-menu">
        ← {@return_label}
      </.link>
      <%!-- Header: photos left, details right. Compact on every tab but Works. --%>
      <div class={["artist-top", @live_action != :works && "compact"]}>
        <.artist_photos
          artist={@artist}
          images={@artist_images}
          photo_index={@photo_index}
          controls={@live_action == :works}
        />

        <div class="artist-details">
          <h1>{@artist.nickname}</h1>
          <%!-- The artist's own motto: the same fixed text for everyone
               until artists can set one (NOTES.md #26) --%>
          <.placeholder what="Artist's motto">
            <div class="artist-motto">Bursting with colour</div>
          </.placeholder>
          <div class="artist-area">{area_label(@artist.area_code)}</div>

          <div :if={@artist.medium not in [nil, []]} class="artist-mediums chip-row">
            <.chip :for={medium <- @artist.medium}>{medium}</.chip>
          </div>

          <%!-- Bio: the first few lines (3 on Works, 2 in the compact
               header, none in the compact header on phones), then
               "Show full bio ›". The BioClamp hook (app.js) shows that
               button only if the bio is longer than those lines. --%>
          <div id="artist-bio" class="artist-bio" phx-hook="BioClamp">
            <h2 class="artist-bio-label">About the artist</h2>
            <div
              id="artist-bio-text"
              class={["artist-bio-text", !@bio_open && "clamped"]}
              data-bio-text
            >
              <p :for={paragraph <- bio_paragraphs(@artist.bio)}>{paragraph}</p>
            </div>
            <.show_more
              phx-click="toggle_bio"
              aria-controls="artist-bio-text"
              aria-expanded={to_string(@bio_open)}
            >
              {if @bio_open, do: "Show less ‹", else: "Show full bio ›"}
            </.show_more>
          </div>
        </div>
      </div>

      <nav class="artist-tabs" aria-label="Artist page sections">
        <.link
          :for={
            {tab, label} <- [
              works: "Works",
              shop: "Shop",
              commissions: "Commissions",
              contact: "Contact"
            ]
          }
          patch={tab_path(@artist, tab, @kept_params)}
          class="artist-tab"
          aria-current={if @live_action == tab, do: "page"}
        >
          {label}
        </.link>
      </nav>

      <.works_tab
        :if={@live_action == :works}
        artist={@artist}
        featured_products={@featured_products}
        collections={@collections}
        kept_params={@kept_params}
      />

      <.shop_tab
        :if={@live_action == :shop}
        artist={@artist}
        form={@form}
        filters={@filters}
        products={@products}
        shown_count={@shown_count}
        total_count={@total_count}
        category_counts={@category_counts}
        collections={@collections}
      />

      <.commissions_tab
        :if={@live_action == :commissions}
        artist={@artist}
        current_scope={@current_scope}
      />

      <.contact_tab
        :if={@live_action == :contact}
        artist={@artist}
        current_scope={@current_scope}
      />

      <%!-- Under every tab --%>
      <div class="artist-report">
        <.report_link
          :if={@current_scope && @current_scope.user}
          subject="vendor"
          id={@artist.id}
          return_to={~p"/artists/#{@artist.id}"}
          return_label="Artist page"
        >
          Report a concern about this artist
        </.report_link>
      </div>
    </Layouts.artsy_main>
    """
  end

  # Header: the artist's photos, one at a time, in a tall 7:10 frame.
  # With more than one photo, the Works tab adds arrows and dots on top
  # of the photo (so they take no extra room); the compact header is too
  # small for them and shows just the current photo. No photos: an
  # empty cream frame of the same shape.
  attr :artist, :map, required: true
  attr :images, :list, required: true
  attr :photo_index, :integer, required: true
  attr :controls, :boolean, required: true, doc: "Show the arrows and dots"

  defp artist_photos(assigns) do
    assigns = assign(assigns, :photo_count, length(assigns.images))

    ~H"""
    <div
      class="artist-photo"
      aria-roledescription="carousel"
      aria-label={"Photos of #{@artist.nickname}"}
    >
      <img
        :for={{image, index} <- Enum.with_index(@images)}
        src={image.path}
        alt={"#{@artist.nickname}, photo #{index + 1} of #{@photo_count}"}
        hidden={index != @photo_index}
      />

      <%= if @controls && @photo_count > 1 do %>
        <button
          type="button"
          class="carousel-arrow prev"
          phx-click="show_photo"
          phx-value-index={@photo_index - 1}
          aria-label="Previous photo"
        >
          ‹
        </button>
        <button
          type="button"
          class="carousel-arrow next"
          phx-click="show_photo"
          phx-value-index={@photo_index + 1}
          aria-label="Next photo"
        >
          ›
        </button>
        <div class="carousel-dots" aria-hidden="true">
          <span
            :for={index <- 0..(@photo_count - 1)}
            class={index == @photo_index && "current"}
          >
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  # The artist's area: only the postal district, the first 3 characters
  # of their postal code ("V8V · Victoria"). The full code can point to a
  # single block, so it's never shown. A proper neighbourhood name comes
  # later (NOTES.md #28).
  defp area_label(nil), do: "Victoria"

  defp area_label(postal_code) do
    district = postal_code |> String.trim() |> String.slice(0, 3) |> String.upcase()
    "#{district} · Victoria"
  end

  # The bio as paragraphs: every line break the artist typed starts a new
  # paragraph (one Enter or a blank line alike); empty lines are dropped.
  defp bio_paragraphs(nil), do: []

  defp bio_paragraphs(bio) do
    bio
    |> String.split(~r/\R/)
    |> Enum.map(fn line -> String.trim(line) end)
    |> Enum.reject(fn line -> line == "" end)
  end

  # Works tab: Featured works with "See all works ›" (which opens the
  # Shop tab), a thin line, then the artist's collections. Each section
  # only when it has something in it; no available works at all shows a
  # short note instead.
  attr :artist, :map, required: true
  attr :featured_products, :list, required: true
  attr :collections, :list, required: true, doc: "From list_public_collections_for_artist/1"
  attr :kept_params, :map, required: true

  defp works_tab(assigns) do
    ~H"""
    <section :if={@featured_products != []} class="artist-works-section">
      <.section_heading>Featured works</.section_heading>
      <div class="card-grid">
        <.artwork_card
          :for={product <- @featured_products}
          product={product}
          show_artist={false}
        />
      </div>
      <div class="artist-see-all">
        <.link patch={tab_path(@artist, :shop, @kept_params)}>See all works ›</.link>
      </div>
    </section>

    <p :if={@featured_products == []} class="artist-no-works">
      {@artist.nickname} has no works for sale right now.
    </p>

    <hr :if={@featured_products != [] && @collections != []} class="artist-divider" />

    <%!-- One card per collection, each opening the Shop tab with only
         that collection's works --%>
    <section :if={@collections != []} class="artist-works-section">
      <.section_heading>Collections by {@artist.nickname}</.section_heading>
      <div class="card-grid">
        <.collection_card
          :for={collection <- @collections}
          name={collection.name}
          image={collection_image(collection)}
          navigate={
            tab_path(
              @artist,
              :shop,
              Map.put(@kept_params, "collection_id", collection.id)
            )
          }
        />
      </div>
    </section>
    """
  end

  # The first photo of a collection's first work, or nil.
  defp collection_image(collection) do
    with %{} = product <- List.first(collection.products),
         %{} = image <- List.first(product.product_images) do
      image.path
    else
      _ -> nil
    end
  end

  # Shop tab: the artist's announcement, filters (search, category, sort,
  # collection chips), the works a page at a time, then pickup and
  # delivery (redesigned in step 5 of the artist-page plan).
  attr :artist, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :filters, :map, required: true, doc: "The filters in the address"
  attr :products, :list, required: true, doc: "All works matching the filters"
  attr :shown_count, :integer, required: true, doc: "How many of them to show"
  attr :total_count, :integer, required: true, doc: "All the artist's works, unfiltered"
  attr :category_counts, :list, required: true
  attr :collections, :list, required: true

  defp shop_tab(assigns) do
    ~H"""
    <section class="shop">
      <%!-- The artist's own announcement, only when they've turned it on --%>
      <div
        :if={@artist.announcement_active && @artist.announcement not in [nil, ""]}
        class="shop-notice"
      >
        <strong>Note from {@artist.nickname}:</strong> {@artist.announcement}
      </div>

      <p :if={@total_count == 0} class="artist-no-works">
        {@artist.nickname} has no works for sale right now.
      </p>

      <div :if={@total_count > 0} class="shop-filters">
        <.filter_form
          form={@form}
          filters={@filters}
          artist={@artist}
          category_counts={@category_counts}
        />

        <%!-- Collections as chips: one tap, all of them in sight --%>
        <div :if={@collections != []} class="chip-row" role="group" aria-label="Show works from">
          <.filter_chip
            pressed={Map.get(@filters, "collection_id") in [nil, ""]}
            count={@total_count}
            phx-click="choose_collection"
            phx-value-id=""
          >
            All works
          </.filter_chip>
          <.filter_chip
            :for={collection <- @collections}
            pressed={Map.get(@filters, "collection_id") == to_string(collection.id)}
            count={length(collection.products)}
            phx-click="choose_collection"
            phx-value-id={collection.id}
          >
            {collection.name}
          </.filter_chip>
        </div>
      </div>

      <div class="card-grid">
        <.artwork_card
          :for={product <- Enum.take(@products, @shown_count)}
          product={product}
          show_artist={false}
        />
      </div>

      <p :if={@total_count > 0 && @products == []} class="shop-no-results">
        No works match your choice. Try another word, or choose "All works".
      </p>

      <%!-- A button rather than endless scrolling, so the footer stays
           within reach and people know how much there is --%>
      <div :if={length(@products) > @shown_count} class="shop-show-more">
        <span>Showing {@shown_count} of {length(@products)} works</span>
        <.button phx-click="show_more">Show more works</.button>
      </div>
    </section>

    <section :if={@artist.delivery_options != []} class="mt-6">
      <h2 class="text-sm font-semibold text-base-content/60 mb-2">Delivery Options</h2>
      <ul class="space-y-1">
        <%= for option <- @artist.delivery_options do %>
          <li class="text-sm text-base-content/80">
            <span class="font-medium">{delivery_option_label(option)}</span>
            <%= if (get_in(@artist.delivery_info, [option]) || "") != "" do %>
              <span class="text-base-content/60">
                — {get_in(@artist.delivery_info, [option])}
              </span>
            <% end %>
          </li>
        <% end %>
      </ul>
    </section>
    """
  end

  # Shop tab: search, category and sort in one row, ending at the
  # right edge. The category dropdown lists only the categories the
  # artist has works in, and is left out when that's just one.
  #
  # On phones the search box shares its row with a "Filter and sort"
  # button, which opens category and sort on rows of their own below.
  # The button works in the browser alone (JS.toggle_class, nothing
  # sent to the server), and says how many of the two are changed from
  # the default, e.g. "Filter and sort (1)", so nothing is hidden
  # without a hint.
  attr :form, Phoenix.HTML.Form, required: true
  attr :filters, :map, required: true
  attr :artist, :map, required: true
  attr :category_counts, :list, required: true

  defp filter_form(assigns) do
    category_options =
      Enum.map(assigns.category_counts, fn {id, name, count} -> {"#{name} (#{count})", id} end)

    changed_count =
      Enum.count(["category_id", "sort_by"], fn key -> Map.get(assigns.filters, key) end)

    assigns =
      assigns
      |> assign(:category_options, category_options)
      |> assign(:changed_count, changed_count)

    ~H"""
    <.form for={@form} id="filter-form" class="shop-tools" phx-change="filter" phx-submit="filter">
      <input
        type="search"
        name={@form[:search].name}
        value={@form[:search].value}
        class="field-input shop-search"
        placeholder={"Search #{@artist.nickname}'s works"}
        aria-label={"Search #{@artist.nickname}'s works"}
        autocomplete="off"
        phx-debounce="1000"
      />
      <%!-- The chosen collection (set by the chips), so it stays when
           the search, category or sort changes --%>
      <input type="hidden" name={@form[:collection_id].name} value={@form[:collection_id].value} />

      <.button
        type="button"
        class="shop-filter-toggle"
        aria-controls="shop-options"
        aria-expanded="false"
        phx-click={
          JS.toggle_class("open", to: "#shop-options")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
      >
        Filter and sort{if @changed_count > 0, do: " (#{@changed_count})"}
      </.button>

      <div id="shop-options" class="shop-options">
        <label :if={length(@category_options) > 1} class="shop-option">
          Category
          <select name={@form[:category_id].name} class="field-input shop-select">
            <option value="">All categories</option>
            {Phoenix.HTML.Form.options_for_select(@category_options, @form[:category_id].value)}
          </select>
        </label>
        <label class="shop-option">
          Sort by
          <select name={@form[:sort_by].name} class="field-input shop-select">
            {Phoenix.HTML.Form.options_for_select(
              [
                {"Newest first", ""},
                {"Price: low to high", "price_asc"},
                {"Price: high to low", "price_desc"}
              ],
              @form[:sort_by].value
            )}
          </select>
        </label>
      </div>
    </.form>
    """
  end

  # Commissions tab: fixed text for now, the same for every artist, and
  # a button to message them. Until artists have a yes/no commissions
  # setting it says every artist takes commissions (NOTES.md).
  attr :artist, :map, required: true
  attr :current_scope, :any, required: true

  defp commissions_tab(assigns) do
    ~H"""
    <section class="artist-tab-body">
      <div class="artist-panel">
        <h2 class="artist-panel-title">{@artist.nickname} takes commissions</h2>
        <p>
          Would you like a work made especially for you? Send {@artist.nickname} a message to tell them what you have in mind. You will hear back about
          what is possible, how long it would take and what it would cost.
        </p>
        <.message_button current_scope={@current_scope} />
      </div>
    </section>
    """
  end

  # Contact tab: send a message, and the artist's links elsewhere online.
  # (Redesigned in step 6 of the artist-page plan.)
  attr :artist, :map, required: true
  attr :current_scope, :any, required: true

  defp contact_tab(assigns) do
    ~H"""
    <div class="mt-8">
      <.message_button current_scope={@current_scope} />
    </div>

    <div :if={@artist.homepage || @artist.instagram || @artist.facebook} class="mt-8">
      <h2 class="text-sm font-semibold text-base-content/60 mb-2">Online</h2>
      <div class="flex flex-wrap gap-3">
        <a :if={@artist.homepage} href={@artist.homepage} target="_blank" rel="noopener">
          Website
        </a>
        <a :if={@artist.instagram} href={@artist.instagram} target="_blank" rel="noopener">
          Instagram
        </a>
        <a :if={@artist.facebook} href={@artist.facebook} target="_blank" rel="noopener">
          Facebook
        </a>
      </div>
    </div>
    """
  end

  # "Send message" for a logged-in visitor, "Log in to message" otherwise.
  attr :current_scope, :any, required: true

  defp message_button(assigns) do
    ~H"""
    <%= if @current_scope && @current_scope.user do %>
      <.button_artsy variant="primary" phx-click="message_artist">
        Send message
      </.button_artsy>
    <% else %>
      <.button_artsy variant="primary" navigate={~p"/users/log-in"}>
        Log in to message
      </.button_artsy>
    <% end %>
    """
  end

  defp delivery_option_label("pickup"), do: "Pickup at the artist's studio"
  defp delivery_option_label("artist_delivery"), do: "Artist delivers"
  defp delivery_option_label("shipping"), do: "Shipping"
  defp delivery_option_label("other"), do: "Other"
  defp delivery_option_label(other), do: other
end
