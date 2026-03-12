defmodule ArtsyNeighborWeb.OfferArtLive do
  use ArtsyNeighborWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Offer Your Art")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.artsy_main flash={@flash}>

      <%!-- Hero --%>
      <div class="text-center py-16 border-b border-base-300">
        <h1 class="text-5xl font-bold mb-4">Share your art with your community</h1>
        <p class="text-xl text-base-content/70 max-w-2xl mx-auto mb-8">
          Artsy Neighbor connects local artists with art lovers nearby.
          Create your artist profile and start selling today — no fees to get started.
        </p>
        <.link navigate={~p"/vendor"} class="btn btn-primary btn-lg">
          Go to Artist Dashboard
        </.link>
      </div>

      <%!-- Benefits --%>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-8 py-16 border-b border-base-300">

        <div class="text-center px-4">
          <h3 class="text-xl font-semibold mb-2">Your own shop</h3>
          <p class="text-base-content/70">
            Create a beautiful profile and showcase your work to local buyers who appreciate handmade art.
          </p>
        </div>

        <div class="text-center px-4">
          <h3 class="text-xl font-semibold mb-2">Local community</h3>
          <p class="text-base-content/70">
            Connect with buyers in your area. No competing with mass-produced goods from across the world.
          </p>
        </div>

        <div class="text-center px-4">
          <h3 class="text-xl font-semibold mb-2">Keep more earnings</h3>
          <p class="text-base-content/70">
            Lower fees than big platforms. More money stays with you and your craft.
          </p>
        </div>

      </div>

      <%!-- How it works --%>
      <div class="py-16 border-b border-base-300">
        <h2 class="text-3xl font-bold text-center mb-10">How it works</h2>
        <ol class="max-w-xl mx-auto space-y-6">
          <li class="flex gap-4">
            <span class="text-2xl font-bold text-primary">1</span>
            <div>
              <h4 class="font-semibold">Create an account</h4>
              <p class="text-base-content/70">Register with your email — no password needed, we use magic links.</p>
            </div>
          </li>
          <li class="flex gap-4">
            <span class="text-2xl font-bold text-primary">2</span>
            <div>
              <h4 class="font-semibold">Build your artist profile</h4>
              <p class="text-base-content/70">Tell buyers who you are, what you create, and where you're based.</p>
            </div>
          </li>
          <li class="flex gap-4">
            <span class="text-2xl font-bold text-primary">3</span>
            <div>
              <h4 class="font-semibold">List your products</h4>
              <p class="text-base-content/70">Add photos, descriptions, and prices. Your work goes live immediately.</p>
            </div>
          </li>
        </ol>
      </div>

      <%!-- Bottom CTA --%>
      <div class="text-center py-16">
        <h2 class="text-3xl font-bold mb-4">Ready to start?</h2>
        <div class="flex justify-center gap-4">
          <.link navigate={~p"/vendor"} class="btn btn-primary btn-lg">
            Artist Dashboard
          </.link>
          <.link navigate={~p"/users/register"} class="btn btn-outline btn-lg">
            Create an account
          </.link>
        </div>
      </div>

    </Layouts.artsy_main>
    """
  end
end
