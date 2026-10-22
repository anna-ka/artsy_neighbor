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
  alias ArtsyNeighbor.Categories
  alias ArtsyNeighbor.Products
  alias ArtsyNeighbor.Conversations

  import ArtsyNeighborWeb.CustomComponents,
    only: [
      product_card: 1,
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

  # Query params of the Shop tab's filter form.
  @filter_params ["search", "category_id", "collection_id", "sort_by"]

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
    categories =
      Enum.map(Categories.list_categories(), fn category -> {category.name, category.id} end)

    # The same collections as the Works tab's cards: none without works,
    # no "Uncategorized".
    collection_options =
      socket.assigns.audience
      |> shown_collections(artist)
      |> Enum.map(fn collection -> {collection.name, collection.id} end)

    filters = Map.take(params, @filter_params)

    products =
      case socket.assigns.audience do
        :public -> Products.filter_artist_products(artist.id, filters)
        :owner_preview -> Products.filter_artist_products_for_owner_preview(artist.id, filters)
      end

    socket
    |> assign(:categories, categories)
    |> assign(:collection_options, collection_options)
    |> assign(:products, products)
    |> assign(:form, to_form(filters))
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

  # Shop tab: the filter form changed. Puts the filters in the address,
  # which reloads the works (handle_params/3).
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_params)
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)

    query = Map.merge(socket.assigns.kept_params, filters)

    {:noreply, push_patch(socket, to: tab_path(socket.assigns.artist, :shop, query))}
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
        categories={@categories}
        collection_options={@collection_options}
        products={@products}
        clear_path={tab_path(@artist, :shop, @kept_params)}
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

  # Shop tab: announcement, filters, all available works, pickup and
  # delivery. (Redesigned in steps 4 and 5 of the artist-page plan.)
  attr :artist, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true
  attr :collection_options, :list, required: true
  attr :products, :list, required: true
  attr :clear_path, :string, required: true

  defp shop_tab(assigns) do
    ~H"""
    <div
      :if={@artist.announcement_active && @artist.announcement not in [nil, ""]}
      class="alert alert-info mt-6 text-sm"
    >
      {@artist.announcement}
    </div>

    <section class="my-6">
      <.filter_form
        form={@form}
        categories={@categories}
        collection_options={@collection_options}
        clear_path={@clear_path}
      />
    </section>

    <section class="bg-base-200 py-12">
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        <.product_card :for={product <- @products} product={product} />
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

  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true
  attr :collection_options, :list, required: true
  attr :clear_path, :string, required: true, doc: "The Shop tab with no filters"

  defp filter_form(assigns) do
    ~H"""
    <.form for={@form} id="filter-form" phx-change="filter" phx-submit="filter">
      <div class="flex flex-wrap gap-4 items-end">
        <%!-- Search --%>
        <div class="flex-1 min-w-48">
          <.input
            field={@form[:search]}
            type="text"
            label="Search"
            placeholder="Search products..."
            autocomplete="off"
            phx-debounce="1000"
          />
        </div>

        <%!-- Filter by Category --%>
        <div class="min-w-48">
          <.input
            field={@form[:category_id]}
            type="select"
            label="Category"
            prompt="All categories"
            options={@categories}
          />
        </div>

        <%!-- Filter by Collection --%>
        <div class="min-w-48">
          <.input
            field={@form[:collection_id]}
            type="select"
            label="Collection"
            prompt="All collections by artist"
            options={@collection_options}
          />
        </div>

        <%!-- Sort By --%>
        <div class="min-w-48">
          <.input
            field={@form[:sort_by]}
            type="select"
            label="Sort by"
            prompt="Default"
            options={[
              {"Price: Low to High", "price_asc"},
              {"Price: High to Low", "price_desc"},
              {"Collection", "collection"},
              {"Category", "category"}
            ]}
          />
        </div>

        <%!-- Reset --%>
        <div>
          <.link patch={@clear_path} class="btn btn-ghost">Clear</.link>
        </div>
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
