defmodule ArtsyNeighbor.FakeS3 do
  @moduledoc """
  A pretend S3 server for tests of `ArtsyNeighbor.Storage.S3`.

  ex_aws sends every request through an "HTTP client" module named in
  its config. In tests we name this module instead of the real one, so
  requests never leave the computer: they read and change a map of
  files kept in memory (an `Agent`), keyed by `{bucket, key}`.

  It understands just the requests `Storage.S3` makes, in the
  "virtual host" style (`https://<bucket>.<host>/<key>`):

    * `PUT /<key>` — store a file (and its headers);
    * `GET /<key>` — read a file (404 if missing);
    * `GET /?list-type=2&prefix=...` — list keys starting with a prefix;
    * `POST /?delete` — delete several keys at once.

  Use `start_link/0` in a test's setup (via `start_supervised!/1`).
  Not for async tests: there is one shared store.
  """

  @behaviour ExAws.Request.HttpClient

  def start_link(_options \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}}
  end

  @doc "Every stored `{bucket, key}`, sorted (for assertions)."
  def stored_keys do
    Agent.get(__MODULE__, fn files -> files |> Map.keys() |> Enum.sort() end)
  end

  @doc "The stored file `%{body: ..., headers: ...}`, or `nil`."
  def get_file(bucket, key) do
    Agent.get(__MODULE__, fn files -> Map.get(files, {bucket, key}) end)
  end

  @impl true
  def request(method, url, body, headers, _http_opts \\ []) do
    uri = URI.parse(url)
    [bucket | _rest_of_host] = String.split(uri.host, ".")
    key = uri.path |> String.trim_leading("/") |> URI.decode()
    query = URI.decode_query(uri.query || "")

    handle(method, bucket, key, query, body, headers)
  end

  defp handle(:put, bucket, key, _query, body, headers) do
    file = %{body: body, headers: Map.new(headers)}
    Agent.update(__MODULE__, fn files -> Map.put(files, {bucket, key}, file) end)
    reply(200, "")
  end

  defp handle(:get, bucket, "", %{"list-type" => "2"} = query, _body, _headers) do
    prefix = Map.get(query, "prefix", "")

    keys =
      Enum.filter(stored_keys(), fn {stored_bucket, stored_key} ->
        stored_bucket == bucket and String.starts_with?(stored_key, prefix)
      end)

    contents =
      Enum.map_join(keys, "", fn {_bucket, stored_key} ->
        "<Contents><Key>#{stored_key}</Key><Size>1</Size></Contents>"
      end)

    reply(200, """
    <?xml version="1.0" encoding="UTF-8"?>
    <ListBucketResult><Name>#{bucket}</Name><Prefix>#{prefix}</Prefix>\
    <KeyCount>#{length(keys)}</KeyCount><IsTruncated>false</IsTruncated>\
    #{contents}</ListBucketResult>
    """)
  end

  defp handle(:get, bucket, key, _query, _body, _headers) do
    case get_file(bucket, key) do
      nil -> reply(404, "<Error><Code>NoSuchKey</Code></Error>")
      file -> reply(200, file.body)
    end
  end

  defp handle(:post, bucket, "", %{"delete" => _}, body, _headers) do
    keys =
      Regex.scan(~r{<Key>(.*?)</Key>}, body)
      |> Enum.map(fn [_whole_match, key] -> key end)

    Agent.update(__MODULE__, fn files ->
      Map.drop(files, Enum.map(keys, fn key -> {bucket, key} end))
    end)

    reply(200, "<DeleteResult></DeleteResult>")
  end

  defp reply(status, body) do
    {:ok, %{status_code: status, headers: [], body: body}}
  end
end
