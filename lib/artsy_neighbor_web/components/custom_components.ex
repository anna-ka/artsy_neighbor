defmodule ArtsyNeighborWeb.CustomComponents do

  use ArtsyNeighborWeb, :html


  @doc """
  Renders a product card displaying product details.

  Used on the home page and product listing page.

  """

  attr :product, :map, required: true, doc: "An ArtsyNeighbor.Product struct"

  def product_card(assigns) do
      ~H"""
        <div class="bg-artsy-bg rounded-lg shadow-md p-3 pb-2">
                <div class="h-60 rounded mb-2 overflow-hidden bg-gray-100 flex items-center justify-center">
                  <img
                    src={@product.image}
                    alt={@product.title}
                    class="w-full h-full object-cover"
                  />
                </div>

                <h3 class="font-normal text-gray-600 mb-1"><%= @product.title %></h3>
                <p class="text-gray-600 text-sm mb-1"><%= @product.artist_name %></p>
                <p class="text-sm text-gray-600">CA$<%= :erlang.float_to_binary(@product.price, decimals: 2) %></p>
              </div>
        """
    end


    @doc """
    Renders a category card displaying category details.

    Used on the home page.
    """

  attr :category, :map, required: true, doc: "Category name of type ArtsyNeighbor.ProductCategory struct"

  def category_card(assigns) do
    ~H"""
      <div
          style={"background-image: url(#{@category.image})"}
          class="rounded-lg h-64 flex items-end justify-center pb-10 bg-cover bg-center relative">
          <button class="btn rounded-xl bg-white text-black hover:bg-gray-100 font-semibold"><%= @category.title %></button>
        </div>

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
      <%= render_slot(@inner_block) %>
    </h1>
    <div :for={tagline <- @tagline} class="tagline">
      <%= render_slot(tagline, @emoji)  %>
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
  """

  attr :show, :boolean, default: false, doc: "Whether to show the banner"
  attr :variant, :string, default: "info", values: ~w(info warning success error), doc: "Banner color variant"
  slot :inner_block, required: true

  def site_wide_banner(assigns) do
    ~H"""
    <div :if={@show} class={[
      "w-full py-3 px-4 text-center text-sm font-medium",
      @variant == "info" && "bg-artsy-teal text-white",
      @variant == "warning" && "bg-amber-500 text-white",
      @variant == "success" && "bg-green-600 text-white",
      @variant == "error" && "bg-red-600 text-white"
    ]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

end
