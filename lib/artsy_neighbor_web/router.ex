defmodule ArtsyNeighborWeb.Router do
  use ArtsyNeighborWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArtsyNeighborWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ArtsyNeighborWeb do
    pipe_through :browser

    # get "/", PageController, :home
    live "/", HomeLive
    live "/products", ProductLive.Index
    live "/products/:id", ProductLive.Show

    live "/artists", ArtistLive.Index
    live "/artists/:id", ArtistLive.Show

    live "/admin/artists", AdminArtistLive.Index
    live "/admin/artists/new", AdminArtistLive.Form, :new
    live "/admin/artists/:id/edit", AdminArtistLive.Form, :edit

    live "/admin/categories", AdminCategoryLive.Index, :index
    live "/admin/categories/new", AdminCategoryLive.Form, :new
    live "/admin/categories/:id", AdminCategoryLive.Show, :show
    live "/admin/categories/:id/edit", AdminCategoryLive.Form, :edit

    live "/categories", CategoryLive.Index, :index
    live "/categories/:id", CategoryLive.Show, :show

    get "/contactus", ContactusController, :contactus
  end



  # Other scopes may use custom stacks.
  # scope "/api", ArtsyNeighborWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:artsy_neighbor, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ArtsyNeighborWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
