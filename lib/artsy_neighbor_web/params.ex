defmodule ArtsyNeighborWeb.Params do
  @moduledoc """
  Helpers for values that come from the browser (event params, URL
  params). They may be forged, so they are checked before use: a bad
  value gets an error message instead of crashing the page.
  """

  # The largest number a Postgres `bigint` can hold, which is the type
  # of every id column. A bigger number makes the database query itself
  # fail (and crash the page), so parse_id/1 refuses it first.
  @max_id 9_223_372_036_854_775_807

  @doc """
  Turns an id sent by the browser ("12") into an integer. Returns nil
  for anything that can't be a real id: not a whole number ("abc",
  "12abc"), zero or negative, or too big for the database.
  """
  def parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} when parsed >= 1 and parsed <= @max_id -> parsed
      _ -> nil
    end
  end

  def parse_id(_other), do: nil
end
