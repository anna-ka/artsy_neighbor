defmodule ArtsyNeighbor.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `ArtsyNeighbor.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias ArtsyNeighbor.Accounts.User
  alias ArtsyNeighbor.Artists
  alias ArtsyNeighbor.Accounts

  defstruct user: nil, artist: nil, admin: false

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """

  def for_user(%User{} = user) do
    artist = Artists.get_artist_by_user_id(user.id)
    admin  = Accounts.admin?(user.id)
    %__MODULE__{user: user, artist: artist, admin: admin}
  end






  def for_user(nil), do: nil
end
