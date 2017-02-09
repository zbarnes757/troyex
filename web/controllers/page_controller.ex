defmodule Troyex.PageController do
  use Troyex.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
