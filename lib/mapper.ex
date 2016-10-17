defmodule Mapper do
  defmacro __using__(_options) do
    quote do
      Module.register_attribute __MODULE__, :routes, accumulate: true,
                                                     persist: false
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(env) do
    routes = Enum.reverse(Module.get_attribute(env.module, :routes))
    routes_ast = Enum.reduce routes, nil, fn route, acc ->
      quote do
        defmatch(unquote(route))
        unquote(acc)
      end
    end

    quote do
      def __routes__ do
        Enum.reverse(@routes)
      end

      unquote(routes_ast)

      def match(conn, method, path) do
        Controller.not_found(conn, method, path)
      end
    end
  end

  defmacro defmatch({http_method, path, controller, action, _options}) do
    path_args = RouterPath.matched_arg_list_with_ast_bindings(path)
    params_list_with_bindings = RouterPath.params_with_ast_bindings(path)

    IO.inspect({:path_args, path_args})
    IO.inspect({:params_list_with_bindings, params_list_with_bindings})

    quote do
      def unquote(:match)(conn, unquote(http_method), unquote(path_args)) do
        IO.inspect({:conn_params_before, conn.params})
        conn = %{conn | params: Map.merge(conn.params, Map.new(unquote(params_list_with_bindings)))}
        IO.inspect({:conn_params_after, conn.params})

        apply(unquote(controller), unquote(action), [conn])
      end
    end
  end

  defmacro get(path, controller, action, options \\ []) do
    add_route(:get, path, controller, action, options)
  end

  defp add_route(verb, path, controller, action, options) do
    quote bind_quoted: [verb: verb,
                        path: path,
                        controller: controller,
                        action: action,
                        options: options] do

      @routes {verb, path, controller, action, options}
    end
  end
end
