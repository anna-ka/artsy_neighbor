defmodule ArtsyNeighborWeb.Router do
  use ArtsyNeighborWeb, :router

  import ArtsyNeighborWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArtsyNeighborWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    #plug :spy
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  def spy(conn, _opts) do
    greeting = ~w(Hi Howdy Hello) |> Enum.random()

    conn = assign(conn, :greeting, greeting)

    IO.inspect(conn)

    conn
  end

  scope "/", ArtsyNeighborWeb do
    pipe_through :browser



    #generated
    # live "/products", ProductLive.Index, :index
    # live "/products/new", ProductLive.Form, :new
    # live "/products/:id", ProductLive.Show, :show
    # live "/products/:id/edit", ProductLive.Form, :edit

    #generated
    # live "/product_images", ProductImageLive.Index, :index
    # live "/product_images/new", ProductImageLive.Form, :new
    # live "/product_images/:id", ProductImageLive.Show, :show
    # live "/product_images/:id/edit", ProductImageLive.Form, :edit

    #generated
    # live "/product_options", ProductOptionLive.Index, :index
    # live "/product_options/new", ProductOptionLive.Form, :new
    # live "/product_options/:id", ProductOptionLive.Show, :show
    # live "/product_options/:id/edit", ProductOptionLive.Form, :edit

    # get "/", PageController, :home
    live "/", HomeLive
    live "/products", ProductLive.Index
    live "/products/:id", ProductLive.Show

    live "/artists", ArtistLive.Index
    live "/artists/:id", ArtistLive.Show

    live "/categories", CategoryLive.Index, :index
    live "/categories/:id", CategoryLive.Show, :show

    get "/contactus", ContactusController, :contactus
  end


  #scope for admin panels
  scope "/", ArtsyNeighborWeb do
    pipe_through [  :browser, :require_authenticated_user, :require_admin_user]

    live_session :require_admin,
      on_mount: [
        {ArtsyNeighborWeb.UserAuth, :mount_current_scope},
        {ArtsyNeighborWeb.UserAuth, :require_authenticated},
        {ArtsyNeighborWeb.UserAuth, :require_admin}
      ] do

        live "/admin/artists", AdminArtistLive.Index
        live "/admin/artists/new", AdminArtistLive.Form, :new
        live "/admin/artists/:id/edit", AdminArtistLive.Form, :edit

        live "/admin/products", AdminProductLive.Index, :index
        live "/admin/products/new", AdminProductLive.Form, :new
        live "/admin/products/:id", AdminProductLive.Show, :show
        live "/admin/products/:id/edit", AdminProductLive.Form, :edit

        live "/admin/categories", AdminCategoryLive.Index, :index
        live "/admin/categories/new", AdminCategoryLive.Form, :new
        live "/admin/categories/:id", AdminCategoryLive.Show, :show
        live "/admin/categories/:id/edit", AdminCategoryLive.Form, :edit

    end



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

  ## Authentication routes

  scope "/", ArtsyNeighborWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ArtsyNeighborWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ArtsyNeighborWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ArtsyNeighborWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
