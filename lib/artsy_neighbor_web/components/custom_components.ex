defmodule ArtsyNeighborWeb.CustomComponents do
  use ArtsyNeighborWeb, :html

  @doc """
  Renders a product card displaying product details.

  Used on the home page and product listing page.

  """

  attr :product, :map, required: true, doc: "An ArtsyNeighbor.Product struct"

  attr :dom_id, :string,
    default: nil,
    doc: "Optional DOM id for the product card (required when using streams)"

  def product_card(assigns) do
    assigns =
      assign(
        assigns,
        :image_path,
        assigns.product.product_images
        |> Enum.sort_by(fn img -> img.position end)
        |> List.first()
        |> case do
          nil -> "/images/placeholder-product.jpg"
          img -> img.path
        end
      )

    ~H"""
    <.link navigate={~p"/products/#{@product}"} id={@dom_id}>
      <div class="bg-base-200 rounded-lg shadow-md p-3 pb-2">
        <div class="h-60 rounded mb-2 overflow-hidden bg-gray-100 flex items-center justify-center">
          <img
            src={@image_path}
            alt={@product.title}
            class="w-full h-full object-cover"
          />
        </div>

        <h3 class="font-normal text-gray-600 mb-1">{@product.title}</h3>
        <p class="text-gray-600 text-sm mb-1">{@product.artist.nickname}</p>
        <p class="text-sm text-gray-600">CA${Decimal.to_string(@product.price)}</p>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a category card displaying category details.

  Used on the home page.
  """

  attr :category, :map,
    required: true,
    doc: "Category of type ArtsyNeighbor.Categories.Category struct"

  def category_card(assigns) do
    assigns =
      assign(
        assigns,
        :image_url,
        case assigns.category.main_img do
          nil -> "/images/placeholder-category.jpg"
          "" -> "/images/placeholder-category.jpg"
          url -> url
        end
      )

    ~H"""
    <.link navigate={~p"/products?#{[category_id: @category.id]}"}>
      <div
        style={"background-image: url(#{@image_url})"}
        class="rounded-lg h-64 flex items-end justify-center pb-10 bg-cover bg-center relative bg-gray-200"
      >
        <button class="btn rounded-xl bg-white text-black hover:bg-gray-100 font-semibold">
          {@category.name}
        </button>
      </div>
    </.link>
    """
  end

  @doc """
  Renders one artwork as a card: its first photo (cropped to a landscape
  4:3 shape), its title, a line of details and, unless turned off, its
  price. The whole card links to the product page.

  The details line is "Artist · location · materials, size", leaving out
  whatever the product doesn't have or the page turns off. Put cards in a `<div class="card-grid">`.

  Replaces `product_card/1`, which stays until every page has switched
  (Phase E of `docs/plans/2026-10-15-theme-and-components.md`).

  ## Examples

      <.artwork_card product={product} />
      <.artwork_card product={product} show_price={false} />
      <.artwork_card product={product} show_artist={false} />
      <.artwork_card product={product} location="Fernwood" show_size={false} />
  """
  attr :product, :map,
    required: true,
    doc: "An ArtsyNeighbor.Products.Product, with :product_images and :artist preloaded"

  attr :show_price, :boolean,
    default: true,
    doc: "false leaves the price out (the home page is a gallery, not a shop window)"

  attr :show_artist, :boolean,
    default: true,
    doc: "false leaves the artist's name out (on the artist's own page)"

  attr :show_size, :boolean, default: true, doc: "false leaves the size out"

  # Text, not an on/off switch: artists have no neighbourhood field yet.
  # When they do, a page passes it in, e.g. location={product.artist.neighbourhood}.
  attr :location, :string,
    default: nil,
    doc: "The artist's neighbourhood, e.g. \"Fernwood\"; nil (the default) shows none"

  attr :rest, :global, doc: "e.g. id, needed when the card is in a stream"

  def artwork_card(assigns) do
    assigns =
      assign(assigns,
        image_path: first_image_path(assigns.product),
        details: artwork_details(assigns)
      )

    # alt="" because the title right under the photo already names the
    # work; a screen reader would otherwise read it twice.
    ~H"""
    <.link navigate={~p"/products/#{@product}"} class="artwork-card" {@rest}>
      <div class="artwork-card-pic"><img src={@image_path} alt="" /></div>
      <h3 class="artwork-card-title">{@product.title}</h3>
      <p :if={@details != ""} class="artwork-card-sub">{@details}</p>
      <p :if={@show_price} class="artwork-card-price">{format_price(@product.price)}</p>
    </.link>
    """
  end

  # The path of the product's first photo (lowest position), or the
  # placeholder picture when it has none.
  defp first_image_path(product) do
    images = Enum.sort_by(product.product_images, fn image -> image.position end)

    case images do
      [] -> "/images/placeholder-product.jpg"
      [first | _rest] -> first.path
    end
  end

  # "Maren Holt · Fernwood · Oil on canvas, 70 × 50 cm", from the card's
  # assigns: each part only when there is something to show and the page
  # hasn't turned it off. "" when there is nothing at all.
  defp artwork_details(assigns) do
    product = assigns.product

    artist_name =
      case product.artist do
        %{nickname: nickname} when assigns.show_artist -> nickname
        _no_artist_or_hidden -> nil
      end

    size =
      if assigns.show_size do
        artwork_size(product)
      else
        nil
      end

    materials_and_size =
      [product.materials, size]
      |> Enum.reject(fn part -> part in [nil, ""] end)
      |> Enum.join(", ")

    [artist_name, assigns.location, materials_and_size]
    |> Enum.reject(fn part -> part in [nil, ""] end)
    |> Enum.join(" · ")
  end

  # "70 × 50 cm" from whichever of width, length and height are filled in;
  # nil when none are.
  defp artwork_size(product) do
    numbers =
      [product.width, product.length, product.height]
      |> Enum.reject(fn number -> is_nil(number) end)
      |> Enum.map(fn number -> number |> Decimal.normalize() |> Decimal.to_string(:normal) end)

    case numbers do
      [] -> nil
      # Non-breaking spaces (\u00A0), so a size never breaks across lines.
      _some -> Enum.join(numbers, "\u00A0×\u00A0") <> "\u00A0" <> product.units
    end
  end

  # "CA$350": whole dollars only, rounded to the nearest dollar (349.99
  # shows as 350, 349.49 as 349). The product page and orders keep the
  # exact price. A price under 50 cents would round to "CA$0" and look
  # free, so it keeps its cents instead ("CA$0.45").
  defp format_price(price) do
    dollars = price |> Decimal.round(0, :half_up) |> Decimal.to_integer()

    if dollars == 0 do
      "CA$" <> Decimal.to_string(Decimal.round(price, 2), :normal)
    else
      "CA$" <> Integer.to_string(dollars)
    end
  end

  @doc ~S"""
  Renders a group of works as a card: one photo (cropped to a landscape
  4:3 shape) with the group's name in a white label at the bottom. The
  whole card is a link.

  For site categories on the home page and for an artist's own
  collections, which is why it takes plain values rather than a
  category. Put cards in a `<div class="card-grid">`.

  Replaces `category_card/1`, which stays until every page has switched.

  ## Example

      <.collection_card
        name={category.name}
        image={category.main_img}
        navigate={~p"/products?#{[category_id: category.id]}"}
      />
  """
  attr :name, :string, required: true
  attr :image, :string, default: nil, doc: "Path of the photo; nil shows the placeholder"
  attr :navigate, :string, required: true
  attr :rest, :global, doc: "e.g. id"

  def collection_card(assigns) do
    image_path =
      case assigns.image do
        nil -> "/images/placeholder-category.jpg"
        "" -> "/images/placeholder-category.jpg"
        path -> path
      end

    assigns = assign(assigns, :image_path, image_path)

    ~H"""
    <.link navigate={@navigate} class="collection-card" {@rest}>
      <img src={@image_path} alt="" />
      <span class="collection-card-name">{@name}</span>
    </.link>
    """
  end

  @doc """
  Renders a banner with an optional tagline.
  """

  slot :inner_block, required: true
  slot :tagline

  def headsup_banner(assigns) do
    # assigns = assign(assigns, :value, "SOME TEXT")
    assigns = assign(assigns, :emoji, ~w(🥸 🤩 🥳) |> Enum.random())

    ~H"""
    <div class="headline">
      <h1>
        {render_slot(@inner_block)}
      </h1>
      <div :for={tagline <- @tagline} class="tagline">
        {render_slot(tagline, @emoji)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a site-wide announcement banner.

  ## Examples

      <.site_banner show={true} variant="info">
        New products added! Check out our latest collection.
      </.site_banner>

      <.site_banner show={true} variant="warning">
        Holiday shipping: Order by Dec 20th for delivery before Christmas!
      </.site_banner>

      @variant == "test" && "bg-[#eb410b] text-black",
      [#eb410b]

  """

  attr :show, :boolean, default: false, doc: "Whether to show the banner"

  attr :variant, :string,
    default: "info",
    values: ~w(info warning success error test),
    doc: "Banner color variant"

  slot :inner_block, required: true

  def site_wide_banner(assigns) do
    ~H"""
    <div
      :if={@show}
      class={[
        "w-full py-3 px-4 text-center text-sm font-bold",
        @variant == "info" && "bg-info text-info-content",
        @variant == "test" && "bg-black text-white",
        @variant == "warning" && "bg-amber-500 text-white",
        @variant == "success" && "bg-green-600 text-white",
        @variant == "error" && "bg-red-600 text-white"
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button_artsy>Default</.button_artsy>
      <.button_artsy variant="primary">Primary Button</.button_artsy>
      <.button_artsy variant="secondary">Secondary Button</.button_artsy>
      <.button_artsy variant="outline">Outline Button</.button_artsy>
      <.button_artsy variant="ghost">Ghost Button</.button_artsy>
      <.button_artsy variant="danger">Delete</.button_artsy>
      <.button_artsy size="wide">Wide Button</.button_artsy>
      <.button_artsy size="block">Full Width Button</.button_artsy>
      <.button_artsy navigate={~p"/"}>Home</.button_artsy>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any, default: nil

  attr :variant, :string,
    default: "primary",
    values: ~w(primary secondary outline ghost danger soft)

  attr :size, :string, default: "normal", values: ~w(normal wide block sm lg)
  attr :disable_with, :string, default: nil, doc: "Text to display while the form is submitting"
  slot :inner_block, required: true

  def button_artsy(%{rest: rest} = assigns) do
    # Define your custom variants here
    variants = %{
      "primary" => "btn btn-primary",
      "secondary" => "btn btn-secondary",
      "outline" => "btn btn-outline",
      "ghost" => "btn btn-ghost",
      "danger" => "btn bg-red-600 text-white hover:bg-red-700",
      "soft" => "btn btn-primary btn-soft"
    }

    # Define size classes
    size_classes = %{
      "normal" => "",
      "wide" => "btn-wide",
      "block" => "btn-block",
      "sm" => "btn-sm",
      "lg" => "btn-lg"
    }

    # If user provides custom class, use it; otherwise use variant + size
    button_class =
      if assigns[:class] do
        assigns[:class]
      else
        variant_class = Map.get(variants, assigns[:variant], variants["primary"])
        size_class = Map.get(size_classes, assigns[:size], "")
        "#{variant_class} #{size_class}" |> String.trim()
      end

    assigns = assign(assigns, :button_class, button_class)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@button_class} phx-disable-with={@disable_with} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a back button with navigation support.

  Mimicks the .nback component from Phoenix 1.7.
  """

  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="text-sm text-base-content/60 hover:text-base-content font-semibold"
    >
      <.icon name="hero-arrow-left" class="h-3 w-3" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a table with generic styling. Closely mimics the .table component from Phoenix 1.8
  but adds some additional features.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
    attr :col_class, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def form_table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={[
              @row_click && "hover:cursor-pointer",
              col[:col_class]
            ]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders the view/edit/restore/soft-delete/hard-delete action buttons for
  an admin index row. Shared by AdminArtistLive.Index and
  AdminProductLive.Index. Labels and confirm texts are passed in by the
  caller rather than generated here, because the wording differs between
  entities (different cascade side effects and irreversibility caveats) —
  this component shares the structure, not the copy.

  restore/hard-delete always fire "restore"/"delete" respectively (both
  callers already agree on these two event names); soft-delete's event
  name is the one genuine variation ("remove" for Artist, "archive" for
  Product), so it's the one taken as an attr.

  ## Examples

      <.status_actions
        id={artist.id}
        view_path={~p"/artists/\#{artist}"}
        edit_path={~p"/admin/artists/\#{artist}/edit"}
        show_restore={artist.status != :active}
        restore_confirm="Restore ...?"
        soft_delete_event="remove"
        soft_delete_label="mark removed"
        soft_delete_confirm="Mark ... as removed?"
        hard_delete_confirm="Permanently delete ...?"
      />
  """
  attr :id, :any, required: true, doc: "the record's id, used for phx-value-id"
  attr :view_path, :string, required: true
  attr :edit_path, :string, required: true
  attr :show_restore, :boolean, required: true
  attr :restore_confirm, :string, required: true
  attr :soft_delete_event, :string, required: true
  attr :soft_delete_label, :string, required: true
  attr :soft_delete_confirm, :string, required: true
  attr :hard_delete_confirm, :string, required: true

  def status_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <.link navigate={@view_path}>
        <button class="btn btn-ghost btn-xs">view</button>
      </.link>

      <.link navigate={@edit_path}>
        <button class="btn btn-ghost btn-xs">edit</button>
      </.link>

      <.link
        :if={@show_restore}
        phx-click="restore"
        phx-value-id={@id}
        data-confirm={@restore_confirm}
        data-confirm-yes="Yes, restore"
        data-confirm-kind="ordinary"
      >
        <button class="btn btn-ghost btn-xs text-success">restore</button>
      </.link>

      <.link
        phx-click={@soft_delete_event}
        phx-value-id={@id}
        data-confirm={@soft_delete_confirm}
        data-confirm-yes={"Yes, #{@soft_delete_label}"}
      >
        <button class="btn btn-ghost btn-xs text-warning">{@soft_delete_label}</button>
      </.link>

      <.link phx-click="delete" phx-value-id={@id} data-confirm={@hard_delete_confirm}>
        <button class="btn btn-ghost btn-xs text-error">delete</button>
      </.link>
    </div>
    """
  end
end
