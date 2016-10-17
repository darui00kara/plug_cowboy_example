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
