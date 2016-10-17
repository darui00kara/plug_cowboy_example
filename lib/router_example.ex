defmodule RouterExample do
  use Router

  get "example/show/:id", ControllerExample, :show
  get "example/show2", ControllerExample, :show2
end
