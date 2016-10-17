defmodule Router do
  defmacro __using__(plug_adapter_options \\ []) do
    quote do
      use Mapper
      @before_compile unquote(__MODULE__)
      use Plug.Builder

      @options unquote(plug_adapter_options)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      plug :dispatch

      def dispatch(conn, _opts \\ []) do
        Router.perform_dispatch(conn, __MODULE__)
      end

      def start do
        IO.puts ">> Running #{__MODULE__} with Cowboy"
        Plug.Adapters.Cowboy.http __MODULE__, []
      end
    end
  end

  def perform_dispatch(conn, router) do
    fetch_query_parames = Plug.Conn.fetch_query_params(conn)
    http_method         = fetch_query_parames.method |> String.downcase |> :erlang.binary_to_atom(:utf8)
    split_path          = RouterPath.split_from_conn(fetch_query_parames)

    IO.inspect({fetch_query_parames, http_method, split_path})
    apply(router, :match, [fetch_query_parames, http_method, split_path])
  end
end
