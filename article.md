## ゴール

- Phoenixフレームワーク(v0.1.1)のMapperを作成する
- Phoenixフレームワーク(v0.1.1)のルーティングのマクロ展開を追う

## 開発環境

- Mac OS: v10.11.6
- Elixir: v1.3.3
  - Phoenix: v0.1.1

## はじめに

この記事は、古いPhoenixフレームワークの解析？を行っている記事です。
有識者の方には、いまさらな内容ですのであしからず・・・

この記事では"Alchemist Report 001~003"を元に行っています。
そのため、そちらを先に見ることをおすすめします。

さて、本記事で行うことを書いていきましょう。
PathモジュールをMapperモジュールへ組み込み、まともなルーティングができるようにします。
また、ルーティングのマクロ展開がどのように行われているのかを追跡します。(tracking!!)

何ができるようになるか？
ルーティングパスで指定するパラメータを取得できるようになります。

何がわかるか？
Phoenixフレームワーク(v0.1.1)におけるルーティングのマクロ展開がわかるようになります。

さてと始めましょう。

#### Caution:$                                                                                                      
古いバージョンのソースなので、非推奨になったモジュールや機能があったりしました。
私の方でElixir v1.3.3で動くように修正している部分があります。
また、最低限動作する部分のみを抜き出していますので、全容を把握したいっという方がいましたら、
公式のソースコードを読んでください。

## コンテキスト

### やりたいこと

いきなりですが、以下のようなルーティングを処理できるようにしたい。

#### Example:

```elixir
defmodule RouterExample do
  use Router

  get "example/show/:id", ControllerExample, :show
end
```

そして、パス中のパラメータを取得できるようにしたい。

#### Example:

```elixir
defmodule ControllerExample do
  use Controller

  def show(conn) do
    text conn, "Hello World!!, params[id] = #{conn.params["id"]}"
  end
end
```

前回までに解析したPathモジュールから、ここで使う機能は以下の2つ。

#### Example:

```elixir
iex> RouterPath.matched_arg_list_with_ast_bindings("example/show/:id")
["example", "show", {:id, [], nil}]

iex> RouterPath.params_with_ast_bindings("example/show/:id") 
[{"id", {:id, [], nil}}]
```

### マクロの展開を追跡する

まずはマクロの展開を追跡することからやっていきます。
以下のルーティングパスを例に追跡していきます。

#### Example:

```elixir
get "example/show/:id", ControllerExample, :show
```

上記の記述はMapperモジュールのマクロで定義されていますね。
そして、モジュールアトリビュートを使って値の蓄積を行っています。

#### Example:

```elixir
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
```

上記の値を取得しているのが、下記の部分。
Module.get_attribute/3の部分で取得して、defmatch/1へ渡している。

#### Exmaple:

```elixir
defmacro __before_compile__(env) do
  routes = Enum.reverse(Module.get_attribute(env.module, :routes))
  routes_ast = Enum.reduce routes, nil, fn route, acc ->
    quote do
      defmatch(unquote(route))
      unquote(acc)
    end
  end

  ...
end
```

肝心のdefmatch/1の内容が以下。

#### Example:

```elixir
defmacro defmatch({http_method, path, controller, action, _options}) do
    path_args = RouterPath.matched_arg_list_with_ast_bindings(path)
    params_list_with_bindings = RouterPath.params_with_ast_bindings(path)

    quote do
      def unquote(:match)(conn, unquote(http_method), unquote(path_args)) do
        conn = %{conn | params: Map.merge(conn.params, Map.new(unquote(params_list_with_bindings)))}

        apply(unquote(controller), unquote(action), [conn])
      end
    end
  end
```

ここでPathモジュールの機能を使っていますね。
matched_arg_list_with_ast_bindings/1は、match/3の第三引数に指定しています。

#### Example:

```elixir
iex> RouterPath.matched_arg_list_with_ast_bindings("example/show/:id")
["example", "show", {:id, [], nil}]
iex> Macro.to_string(["example", "show", {:id, [], nil}])
"[\"example\", \"show\", id]" -> ["example", "show", id]

## ようは、こんな感じの関数を作りたいわけですね。
def match(conn, :get, ["example", "show", id]) do
  ..
end
```

上記のようにすることで、
HTTPメソッドとパスでパターンマッチさせた関数を実行できるというわけです。
そして関数内部で、各コントローラに対応したアクション関数を呼び出すということです。

もうひとつの機能はどうなっているでしょうか。
(ここまでくるとほぼ分かっている気もしますが・・・)
params_with_ast_bindings/1は、match/3の関数内でconn.paramsとマージしています。

#### Example:

```elixir
iex> params = %{}
%{}
iex> params_with_ast_bindings = RouterPath.params_with_ast_bindings("example/show/:id")
[{"id", {:id, [], nil}}]
iex> Map.merge(params, Map.new(params_with_ast_bindings))
%{"id" => {:id, [], nil}} -> %{"id" => id}
```

上記のようなMapができあがり、conn.paramsで参照できるようになります。
そして、{"id" => id}の変数idは、引数にある["example", "show", id]で一致します。
(ここら辺でvar/2が必要なのかな？)
なかなか、動的ですね〜(良いやり方なのかは知りませんが、面白い！)

### ここまでの各ソースコード

perform_dispatch/2のsplit_pathの部分を修正しています。

#### File: lib/router.ex

```elixir
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
```

defmatch/1の部分を修正しています。

#### File: lib/mapper.ex

```elixir
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

    quote do
      def unquote(:match)(conn, unquote(http_method), unquote(path_args)) do
        conn = %{conn | params: Map.merge(conn.params, Map.new(unquote(params_list_with_bindings)))}

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
```

#### File: lib/router_path.ex

```elixir
defmodule RouterPath do
  def split(path) do
    String.split(path, "/")
  end

  def join([]) do
    ""
  end
  def join(split_path) do
    Elixir.Path.join(split_path)
  end

  def split_from_conn(conn) do
    conn.path_info |> join |> split
  end

  def var_ast(var_name) when is_binary(var_name) do
    var_ast(:erlang.binary_to_atom(var_name, :utf8))
  end
  def var_ast(var_name) do
    #quote do: var!(unquote(var_name))
    quote do: unquote(Macro.var(var_name, nil))
  end

  def ensure_leading_slash(path = <<"/" <> _rest>>) do
    path
  end
  def ensure_leading_slash(path) do
    "/" <> path
  end

  def ensure_no_leading_slash(<<"/" <> rest>>) do
    rest
  end
  def ensure_no_leading_slash(path) do
    path
  end

  def param_names(path) do
    Regex.scan(~r/[\:\*]{1}\w+/, path)
    |> List.flatten
    |> Enum.map(&String.strip(&1, ?:))
    |> Enum.map(&String.strip(&1, ?*))
  end

  defp replace_param_names_with_values(param_names, param_values, path) do
    Enum.reduce param_names, path, fn param_name, path_acc ->
      value = param_values[:erlang.binary_to_atom(param_name, :utf8)] |> to_string
      String.replace(path_acc, ~r/[\:\*]{1}#{param_name}/, value)
    end
  end

  def build(path, []) do
    ensure_leading_slash(path)
  end
  def build(path, param_values) do
    path
    |> param_names
    |> replace_param_names_with_values(param_values, path)
    |> ensure_leading_slash
  end

  def matched_param_ast_bindings(path) do
    path
    |> split
    |> Enum.map(fn
      <<":" <> param>> -> var_ast(param)
      <<"*" <> param>> -> quote do: Phoenix.Router.Path.join(unquote(var_ast(param)))
      _part -> nil
    end)
    |> Enum.filter(&is_tuple(&1))
  end

  def params_with_ast_bindings(path) do
    Enum.zip(param_names(path), matched_param_ast_bindings(path))
  end

  def matched_arg_list_with_ast_bindings(path) do
    path
    |> ensure_no_leading_slash
    |> split
    |> Enum.chunk(2, 1, [nil])
    |> Enum.map(fn [part, next] -> part_to_ast_binding(part, next) end)
    |> Enum.filter(fn part -> part end)
  end
  defp part_to_ast_binding(<<"*" <> _splat_name>>, nil) do
    nil
  end
  defp part_to_ast_binding(<<":" <> param_name>>, <<"*" <> splat_name>>) do
    {:|, [], [var_ast(param_name), var_ast(splat_name)]}
  end
  defp part_to_ast_binding(<<":" <> param_name>>, _next) do
    var_ast(param_name)
  end
  defp part_to_ast_binding(part, <<"*" <> splat_name>>) do
    {:|, [], [part, var_ast(splat_name)]}
  end
  defp part_to_ast_binding(part, _next) do
    part
  end
end
```

#### File: controller.ex

```elixir
defmodule Controller do
  import Plug.Conn

  defmacro __using__(_options) do
    quote do
      import Plug.Conn
      import unquote(__MODULE__)
    end
  end

  def text(conn, text) do
    text(conn, 200, text)
  end
  def text(conn, status, text) do
    send_response(conn, status, "text/plain", text)
  end

  def not_found(conn, method, path) do
      text conn, 404, "No route matches #{method} to #{inspect path}"
  end

  def send_response(conn, status, content_type, data) do
     conn
     |> put_resp_content_type(content_type)
     |> send_resp(status, data)
  end
end
```

#### File: router_example.ex

```elixir
defmodule RouterExample do
  use Router

  get "example/show/:id", ControllerExample, :show
  get "example/show2", ControllerExample, :show2
end
```

#### File: controller_example.ex

```elixir
defmodule ControllerExample do
  use Controller

  def show(conn) do
    text conn, "Hello World!!, params[id] = #{conn.params["id"]}"
  end

  def show2(conn) do
    text conn, "show2!!"
  end
end
```

## 終わりに

ひとつひとつ解析すると時間かかりますね。
もう少しざっくりでも良かった気がします。
とりあえず、今回やっている部分を押さえておけば、v0.1.1はだいたい問題ないはずです。

そういえば、var!/1やらvar/2が必要なのかちょっと疑問があります。
Hygieneについてはどうにも理解が足りないらしい。
マクロの外にも影響させたいときに使うのは知っているが・・・それ以上のことはいまいちわからん。

今後の予定としては、
Phoenixチュートリアルの方にいったん戻りますので、レポートの更新頻度は低めになります。(多分)
時間ができれば、またTips的な感じで記事作っていきます。

あぁできれば、EExを組み込むところとか、PubSubとかWebSocketのあたりもやりたいのですが、
チュートリアル進めないと、冬用の本が・・・

## 参考
[Github - phoenixframework/phoenix (v0.1.1) - mapper.ex](https://github.com/phoenixframework/phoenix/blob/v0.1.1/lib/phoenix/router/mapper.ex)
