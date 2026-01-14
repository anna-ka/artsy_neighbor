 defmodule ArtsyNeighborWeb.ProductLive.Index do

  use ArtsyNeighborWeb, :live_view

  alias ArtsyNeighbor.Products
  import ArtsyNeighborWeb.CustomComponents, only: [product_card: 1]

  #mount
  def mount(_params, _session, socket) do
    socket = stream(socket, :products, Products.list_products())
    {:ok, socket}
  end

 def render(assigns) do
   ~H"""
    <Layouts.artsy_main flash={@flash}>
     <section >
      <h1 class="text-4xl font-bold mt-6 text-black">List of products</h1>
    </section>

    <section>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6" id="products-list" phx-update="stream">

        <.product_card :for={{dom_id, product} <- @streams.products} product={product} dom_id={dom_id} />

        </div>
    </section>
    </Layouts.artsy_main>
   """
 end




#  def handle_event(event, _, socket) do
#   #  socket = assign(socket, key: value)
#    {:noreply, socket}
#  end

 end
