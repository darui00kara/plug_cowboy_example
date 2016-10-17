defmodule MacroTest do
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defmatch
    end
  end

  defmacro defmatch() do
    quote do
      def unquote(:match)(
        http_method,
        #path = ["example", "show", {:var!, [context: RouterPath, import: Kernel], [:id]}]) do
        path = ["example", "show", unquote(Macro.var(:id, nil))]) do
        {http_method, path}
      end
    end
  end
end

defmodule MacroExample do
  use MacroTest
end

defmodule NoHygiene do
  defmacro interference do
    quote do
      unquote(Macro.var(:a, nil)) = 10
    end
  end
end
