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
