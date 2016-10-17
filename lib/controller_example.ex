defmodule ControllerExample do
  use Controller

  def show(conn) do
    text conn, "Hello World!!, params[id] = #{conn.params["id"]}"
  end

  def show2(conn) do
    text conn, "show2!!"
  end
end
