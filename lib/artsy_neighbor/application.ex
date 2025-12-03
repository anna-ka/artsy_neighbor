defmodule ArtsyNeighbor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ArtsyNeighborWeb.Telemetry,
      ArtsyNeighbor.Repo,
      {DNSCluster, query: Application.get_env(:artsy_neighbor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ArtsyNeighbor.PubSub},
      # Start a worker by calling: ArtsyNeighbor.Worker.start_link(arg)
      # {ArtsyNeighbor.Worker, arg},
      # Start to serve requests, typically the last entry
      ArtsyNeighborWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArtsyNeighbor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArtsyNeighborWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
