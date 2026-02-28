defmodule ExArchFixture.Bad.Domain.Service do
  alias ExArchFixture.Bad.Web.Endpoint

  def run do
    Endpoint.call()
  end
end
