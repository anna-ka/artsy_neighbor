defmodule ArtsyNeighbor do
  @moduledoc """
  ArtsyNeighbor keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  The platform's name, as shown in system messages, admin changes to
  orders, the inbox and emails. It lives in one place,
  `config :artsy_neighbor, :platform_name` in `config/config.exs`, so a
  rename is one line there. No fallback: if the setting is missing,
  this raises at once instead of quietly showing an old name.
  """
  def platform_name do
    Application.fetch_env!(:artsy_neighbor, :platform_name)
  end
end
